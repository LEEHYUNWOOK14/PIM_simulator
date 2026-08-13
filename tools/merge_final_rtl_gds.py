#!/usr/bin/env python3
"""Safely merge final routed RTL GDS/OASIS with the canonical TSV overlay."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import jsonschema
from klayout_python import kdb

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "design/floorplan/final_gds_merge_recipe.schema.json"
ORIENTATIONS = {
    "R0": ((1, 0, 0, 1), 0, False),
    "R90": ((0, -1, 1, 0), 90, False),
    "R180": ((-1, 0, 0, -1), 180, False),
    "R270": ((0, 1, -1, 0), 270, False),
    "MX": ((1, 0, 0, -1), 0, True),
    "MY": ((-1, 0, 0, 1), 180, True),
    "MXR90": ((0, 1, 1, 0), 90, True),
    "MYR90": ((0, -1, -1, 0), 270, True),
}


class MergeError(RuntimeError):
    pass


def absolute(value: str) -> Path:
    path = Path(os.path.expandvars(value))
    return path.resolve() if path.is_absolute() else (ROOT / path).resolve()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def point(item: dict[str, Any]) -> tuple[float, float]:
    return float(item["x_um"]), float(item["y_um"])


def apply_matrix(matrix: tuple[int, int, int, int], value: tuple[float, float], scale: float = 1.0) -> tuple[float, float]:
    a, b, c, d = matrix
    x, y = value
    return scale * (a * x + b * y), scale * (c * x + d * y)


def manifest_target(manifest: dict[str, Any], reference: dict[str, str]) -> tuple[float, float]:
    collection_name = {
        "tsv_bundle": "tsv_bundles", "micro_bump_bundle": "micro_bump_bundles",
        "block": "blocks", "reserved_region": "reserved_regions",
    }[reference["object_type"]]
    id_key = "bundle_id" if reference["object_type"] in {"tsv_bundle", "micro_bump_bundle"} else ("instance" if reference["object_type"] == "block" else "region_id")
    matches = [item for item in manifest[collection_name] if item[id_key] == reference["object_id"]]
    if len(matches) != 1:
        raise MergeError(f"manifest anchor object not uniquely found: {reference}")
    item = matches[0]
    mode = reference["point"]
    if reference["object_type"] in {"tsv_bundle", "micro_bump_bundle"}:
        if mode == "lower_left_element_center":
            return float(item["x_um"]), float(item["y_um"])
        if mode != "centroid":
            raise MergeError(f"bundle anchor does not support point={mode}")
        return (float(item["x_um"]) + (int(item["columns"]) - 1) * float(item["pitch_um"]) / 2,
                float(item["y_um"]) + (int(item["rows"]) - 1) * float(item["pitch_um"]) / 2)
    if mode != "center":
        raise MergeError(f"rectangle anchor requires point=center: {reference}")
    return float(item["x_um"]) + float(item["width_um"]) / 2, float(item["y_um"]) + float(item["height_um"]) / 2


def used_layers(layout: kdb.Layout, top: kdb.Cell) -> dict[tuple[int, int], int]:
    result: dict[tuple[int, int], int] = {}
    for index in layout.layer_indexes():
        info = layout.get_info(index)
        iterator = top.begin_shapes_rec(index)
        count = 0
        while not iterator.at_end():
            count += 1
            iterator.next()
        if count:
            result[(info.layer, info.datatype)] = count
    return result


def remap_rtl_layers(layout: kdb.Layout, top: kdb.Cell, config: dict[str, Any]) -> tuple[dict, dict]:
    before = used_layers(layout, top)
    rules = config["rules"]
    sources = [(r["from"]["layer"], r["from"]["datatype"]) for r in rules]
    if len(sources) != len(set(sources)):
        raise MergeError("duplicate source layer mapping")
    missing = sorted(set(sources) - set(before))
    if missing:
        raise MergeError(f"mapped RTL source layers are absent below selected top: {missing}")
    unmapped = sorted(set(before) - set(sources))
    policy = config["unmapped_rtl_policy"]
    if unmapped and policy == "error":
        raise MergeError(f"unmapped RTL layers rejected: {unmapped}")
    if policy == "drop":
        for pair in unmapped:
            index = layout.find_layer(*pair)
            if index >= 0:
                layout.clear_layer(index)

    occupied = set(before) | {(r["to"]["layer"], r["to"]["datatype"]) for r in rules}
    temporary: list[tuple[int, int]] = []
    candidate = 65535
    for _ in rules:
        while (candidate, 65535) in occupied:
            candidate -= 1
        if candidate < 60000:
            raise MergeError("too many layer rules for collision-safe temporary mapping")
        temporary.append((candidate, 65535)); occupied.add((candidate, 65535)); candidate -= 1
    for rule, temp in zip(rules, temporary):
        source_index = layout.find_layer(rule["from"]["layer"], rule["from"]["datatype"])
        temp_index = layout.layer(kdb.LayerInfo(*temp))
        layout.move_layer(source_index, temp_index)
    for rule, temp in zip(rules, temporary):
        temp_index = layout.find_layer(*temp)
        target_index = layout.layer(kdb.LayerInfo(rule["to"]["layer"], rule["to"]["datatype"]))
        layout.move_layer(temp_index, target_index)
    return before, used_layers(layout, top)


def namespace_layout(layout: kdb.Layout, prefix: str) -> dict[str, str]:
    mapping: dict[str, str] = {}
    used: set[str] = set()
    for cell in layout.each_cell():
        original = cell.name
        stem = re.sub(r"[^A-Za-z0-9_$?]", "_", f"{prefix}{original}")[:110]
        name = stem
        counter = 1
        while name in used:
            suffix = f"_{counter}"
            name = stem[:120-len(suffix)] + suffix
            counter += 1
        cell.name = name; used.add(name); mapping[original] = name
    return mapping


def solve_placement(config: dict[str, Any], manifest: dict[str, Any], dbu_um: float) -> tuple[float, float, list[dict]]:
    matrix = ORIENTATIONS[config["orientation"]][0]
    scale = float(config["physical_scale"])
    if not config["allow_non_unit_scale"] and not math.isclose(scale, 1.0, abs_tol=1e-15):
        raise MergeError("non-unit physical scaling is disabled; DBU normalization is not physical scaling")
    resolved = []
    for anchor in config["anchors"]:
        source = point(anchor["source_um"])
        target = point(anchor["target_um"]) if "target_um" in anchor else manifest_target(manifest, anchor["target_manifest_ref"])
        oriented = apply_matrix(matrix, source, scale)
        resolved.append({"name": anchor["name"], "source_um": source, "target_um": target,
                         "translation_candidate_um": (target[0] - oriented[0], target[1] - oriented[1])})
    if config["translation_mode"] == "from_anchors":
        if not resolved:
            raise MergeError("translation_mode=from_anchors requires at least one anchor")
        tx = sum(a["translation_candidate_um"][0] for a in resolved) / len(resolved)
        ty = sum(a["translation_candidate_um"][1] for a in resolved) / len(resolved)
    else:
        if "translation_um" not in config:
            raise MergeError("translation_mode=explicit requires translation_um")
        tx, ty = point(config["translation_um"])
    tx = round(tx / dbu_um) * dbu_um
    ty = round(ty / dbu_um) * dbu_um
    tolerance = float(config["anchor_tolerance_um"])
    for anchor in resolved:
        transformed = apply_matrix(matrix, anchor["source_um"], scale)
        actual = transformed[0] + tx, transformed[1] + ty
        residual = math.hypot(actual[0] - anchor["target_um"][0], actual[1] - anchor["target_um"][1])
        anchor["transformed_um"] = actual; anchor["residual_um"] = residual
        for key in ("source_um", "target_um", "translation_candidate_um", "transformed_um"):
            anchor[key] = list(anchor[key])
        if config.get("anchors") and residual > tolerance:
            raise MergeError(f"anchor {anchor['name']} residual {residual:.9g} um exceeds {tolerance} um")
    return tx, ty, resolved


def transformed_bbox_um(box: kdb.Box, source_dbu: float, matrix: tuple[int, int, int, int], scale: float, tx: float, ty: float) -> list[float]:
    corners = [(box.left * source_dbu, box.bottom * source_dbu), (box.left * source_dbu, box.top * source_dbu),
               (box.right * source_dbu, box.bottom * source_dbu), (box.right * source_dbu, box.top * source_dbu)]
    points = [apply_matrix(matrix, p, scale) for p in corners]
    return [min(p[0] for p in points)+tx, min(p[1] for p in points)+ty,
            max(p[0] for p in points)+tx, max(p[1] for p in points)+ty]


def add_lyp_property(root: ET.Element, name: str, layer: int, datatype: int, color: str) -> None:
    prop = ET.SubElement(root, "properties")
    for tag, value in (("frame-color", color), ("fill-color", color), ("frame-brightness", "0"),
                       ("fill-brightness", "0"), ("dither-pattern", "I3"), ("visible", "true"),
                       ("transparent", "false"), ("name", name), ("source", f"{layer}/{datatype}@1")):
        ET.SubElement(prop, tag).text = value


def write_lyp(path: Path, overlay_lyp: Path | None, rules: list[dict]) -> None:
    if overlay_lyp and overlay_lyp.exists():
        root = ET.parse(overlay_lyp).getroot()
    else:
        root = ET.Element("layer-properties")
    existing = {node.text for node in root.findall(".//source")}
    colors = ["#4c78a8", "#f58518", "#54a24b", "#e45756", "#72b7b2", "#b279a2", "#ff9da6", "#9d755d"]
    for index, rule in enumerate(rules):
        layer, datatype = rule["to"]["layer"], rule["to"]["datatype"]
        source = f"{layer}/{datatype}@1"
        if source not in existing:
            add_lyp_property(root, "RTL_" + rule["name"].upper(), layer, datatype, colors[index % len(colors)])
            existing.add(source)
    path.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)


def merge(recipe_path: str | Path, force: bool = False) -> dict[str, Any]:
    recipe_file = absolute(str(recipe_path))
    recipe = load_json(recipe_file)
    jsonschema.Draft202012Validator(load_json(SCHEMA)).validate(recipe)
    rtl_path = absolute(recipe["inputs"]["rtl"]["path"])
    overlay_path = absolute(recipe["inputs"]["overlay"]["path"])
    manifest_path = absolute(recipe["inputs"]["floorplan_manifest"])
    overlay_lyp = absolute(recipe["inputs"]["overlay_lyp"]) if recipe["inputs"].get("overlay_lyp") else None
    output_gds = absolute(recipe["output"]["gds"]); output_lyp = absolute(recipe["output"]["lyp"]); report_path = absolute(recipe["output"]["report"])
    for path in (rtl_path, overlay_path, manifest_path):
        if not path.is_file(): raise MergeError(f"required input missing: {path}")
    if output_gds in {rtl_path, overlay_path}:
        raise MergeError("output GDS must not overwrite an input")
    if output_gds.exists() and not force:
        raise MergeError(f"output exists; pass --force to replace generated output: {output_gds}")
    for key, path in (("rtl", rtl_path), ("overlay", overlay_path)):
        expected = recipe["inputs"][key].get("expected_sha256")
        if expected and sha256(path).lower() != expected.lower():
            raise MergeError(f"{key} SHA-256 mismatch")

    rtl = kdb.Layout(); rtl.read(str(rtl_path))
    overlay = kdb.Layout(); overlay.read(str(overlay_path))
    rtl_top = rtl.cell(recipe["inputs"]["rtl"]["top_cell"])
    overlay_top = overlay.cell(recipe["inputs"]["overlay"]["top_cell"])
    if rtl_top is None: raise MergeError("RTL top cell not found")
    if overlay_top is None: raise MergeError("overlay top cell not found")
    if rtl.dbu <= 0 or overlay.dbu <= 0: raise MergeError("invalid input DBU")
    rtl_before, rtl_after = remap_rtl_layers(rtl, rtl_top, recipe["layer_mapping"])
    overlay_layers = used_layers(overlay, overlay_top)
    collisions = sorted(set(rtl_after) & set(overlay_layers))
    if collisions and recipe["layer_mapping"]["forbid_overlay_collisions"]:
        raise MergeError(f"RTL/overlay output layer collision rejected: {collisions}")
    if recipe["verification"]["require_rtl_shapes"] and not sum(rtl_after.values()): raise MergeError("RTL top has no shapes")
    if recipe["verification"]["require_overlay_shapes"] and not sum(overlay_layers.values()): raise MergeError("overlay top has no shapes")

    manifest = load_json(manifest_path)
    dbu = float(recipe["output"]["dbu_um"])
    minimum_anchors = int(recipe["verification"]["minimum_anchor_count"])
    if recipe["verification"]["require_anchor_alignment"] and len(recipe["placement"]["anchors"]) < minimum_anchors:
        raise MergeError(f"anchor alignment requires at least {minimum_anchors} anchors")
    tx, ty, anchors = solve_placement(recipe["placement"], manifest, dbu)
    matrix, angle, mirror = ORIENTATIONS[recipe["placement"]["orientation"]]
    rtl_bbox = transformed_bbox_um(rtl_top.bbox(), rtl.dbu, matrix, float(recipe["placement"]["physical_scale"]), tx, ty)
    die = manifest["die"]
    die_bbox = [float(die["x_um"]), float(die["y_um"]), float(die["x_um"]+die["width_um"]), float(die["y_um"]+die["height_um"])]
    within_die = rtl_bbox[0] >= die_bbox[0]-dbu and rtl_bbox[1] >= die_bbox[1]-dbu and rtl_bbox[2] <= die_bbox[2]+dbu and rtl_bbox[3] <= die_bbox[3]+dbu
    if recipe["verification"]["enforce_rtl_within_manifest_die"] and not within_die:
        raise MergeError(f"transformed RTL bbox outside manifest die: rtl={rtl_bbox} die={die_bbox}")

    if recipe["namespaces"]["rtl_prefix"] == recipe["namespaces"]["overlay_prefix"]:
        raise MergeError("RTL and overlay namespace prefixes must differ")
    rtl_names = namespace_layout(rtl, recipe["namespaces"]["rtl_prefix"])
    overlay_names = namespace_layout(overlay, recipe["namespaces"]["overlay_prefix"])
    imported_names = set(rtl_names.values()) | set(overlay_names.values())
    if set(rtl_names.values()) & set(overlay_names.values()):
        raise MergeError("namespaced RTL/overlay cell collision")
    if recipe["output"]["top_cell"] in imported_names:
        raise MergeError("output top collides with an imported namespaced cell")
    target = kdb.Layout(); target.dbu = dbu
    output_top = target.create_cell(recipe["output"]["top_cell"])
    rtl_container = target.create_cell(rtl_top.name); rtl_container.copy_tree(rtl_top)
    overlay_container = target.create_cell(overlay_top.name); overlay_container.copy_tree(overlay_top)
    # KLayout copy_tree converts coordinates between source and target DBU.
    # References therefore carry only intentional physical scaling, never a
    # second DBU ratio (which would geometrically scale the design twice).
    overlay_mag = 1.0
    rtl_mag = float(recipe["placement"]["physical_scale"])
    output_top.insert(kdb.CellInstArray(overlay_container.cell_index(), kdb.CplxTrans(overlay_mag, 0, False, 0, 0)))
    output_top.insert(kdb.CellInstArray(rtl_container.cell_index(), kdb.CplxTrans(rtl_mag, angle, mirror, round(tx/dbu), round(ty/dbu))))

    output_gds.parent.mkdir(parents=True, exist_ok=True); report_path.parent.mkdir(parents=True, exist_ok=True)
    temp_gds = output_gds.with_name(output_gds.stem + ".tmp" + output_gds.suffix)
    if temp_gds.exists(): temp_gds.unlink()
    target.write(str(temp_gds)); temp_gds.replace(output_gds)
    write_lyp(output_lyp, overlay_lyp, recipe["layer_mapping"]["rules"])

    checked = kdb.Layout(); checked.read(str(output_gds)); checked_top = checked.cell(recipe["output"]["top_cell"])
    if checked_top is None: raise MergeError("independent output readback lost top cell")
    output_layers = used_layers(checked, checked_top)
    if not output_layers: raise MergeError("independent output readback found no shapes")
    bbox = checked_top.bbox()
    report = {
        "status": "PASS", "generated_at": datetime.now(timezone.utc).isoformat(), "signoff": False,
        "recipe": str(recipe_file),
        "inputs": {
            "rtl": {"path": str(rtl_path), "sha256": sha256(rtl_path), "dbu_um": rtl.dbu, "top": recipe["inputs"]["rtl"]["top_cell"], "layers_before": {f"{a}/{b}": n for (a,b),n in sorted(rtl_before.items())}},
            "overlay": {"path": str(overlay_path), "sha256": sha256(overlay_path), "dbu_um": overlay.dbu, "top": recipe["inputs"]["overlay"]["top_cell"], "layers": {f"{a}/{b}": n for (a,b),n in sorted(overlay_layers.items())}},
            "manifest": {"path": str(manifest_path), "sha256": sha256(manifest_path)}
        },
        "normalization": {"output_dbu_um": dbu, "method": "KLayout copy_tree cross-layout DBU conversion; references do not repeat the DBU ratio", "orientation": recipe["placement"]["orientation"], "physical_scale": recipe["placement"]["physical_scale"], "translation_um": [tx,ty], "rtl_reference_magnification": rtl_mag, "overlay_reference_magnification": overlay_mag},
        "anchors": anchors, "minimum_anchor_count": minimum_anchors, "max_anchor_residual_um": max((a["residual_um"] for a in anchors), default=None),
        "layer_mapping": {"rules": recipe["layer_mapping"]["rules"], "rtl_layers_after": {f"{a}/{b}": n for (a,b),n in sorted(rtl_after.items())}, "overlay_collisions": [f"{a}/{b}" for a,b in collisions]},
        "cell_namespace": {"rtl": rtl_names, "overlay": overlay_names, "output_top": checked_top.name, "output_cell_count": checked.cells()},
        "geometry": {"manifest_die_bbox_um": die_bbox, "transformed_rtl_bbox_um": rtl_bbox, "rtl_within_manifest_die": within_die,
                     "merged_bbox_um": [bbox.left*checked.dbu,bbox.bottom*checked.dbu,bbox.right*checked.dbu,bbox.top*checked.dbu]},
        "output": {"gds": str(output_gds), "gds_sha256": sha256(output_gds), "bytes": output_gds.stat().st_size, "lyp": str(output_lyp), "layers": {f"{a}/{b}": n for (a,b),n in sorted(output_layers.items())}},
        "claim_boundary": "Geometry integration only; does not establish DRC/LVS, timing, IR-drop, SI/PI, package, thermal, or silicon signoff."
    }
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"FINAL_RTL_GDS_MERGE PASS top={checked_top.name} cells={checked.cells()} anchors={len(anchors)} output={output_gds}")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--recipe", required=True)
    parser.add_argument("--force", action="store_true", help="replace only the recipe output GDS")
    args = parser.parse_args()
    try:
        merge(args.recipe, args.force)
    except (MergeError, jsonschema.ValidationError, OSError, ValueError) as exc:
        print(f"FINAL_RTL_GDS_MERGE FAIL: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
