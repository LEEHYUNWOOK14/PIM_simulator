#!/usr/bin/env python3
"""Export canonical blocks, TSV/bump bundles, keep-outs and reserved regions to KLayout GDS."""
from __future__ import annotations

import argparse
import json
import re
from datetime import datetime
from pathlib import Path
from typing import Any

import gdstk
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
TOP = "STOB_LOGIC_DIE_FLOORPLAN_NOT_SIGNOFF"
SIGNAL_ORDER = ["data", "command_address", "clock", "power", "ground", "spare", "unknown"]
SIGNAL_LAYERS = {name: 120 + index for index, name in enumerate(SIGNAL_ORDER)}
BUMPLAYERS = {name: 140 + index for index, name in enumerate(SIGNAL_ORDER)}
REGION_LAYERS = {"phy": 150, "pdn": 151, "clock": 152, "decap": 153, "routing": 154, "pad": 155, "package": 156, "thermal": 157, "other": 158}
THERMAL_LAYERS = list(range(200, 216))


def absolute(path: str | Path) -> Path:
    value = Path(path)
    return value if value.is_absolute() else ROOT / value


def rect(cell: gdstk.Cell, item: dict[str, Any], layer: int, datatype: int = 0) -> None:
    x, y = float(item["x_um"]), float(item["y_um"])
    cell.add(gdstk.rectangle((x, y), (x + float(item["width_um"]), y + float(item["height_um"])), layer=layer, datatype=datatype))


def points(bundle: dict[str, Any]) -> list[tuple[float, float]]:
    return [
        (float(bundle["x_um"]) + column * float(bundle["pitch_um"]), float(bundle["y_um"]) + row * float(bundle["pitch_um"]))
        for column in range(int(bundle["columns"]))
        for row in range(int(bundle["rows"]))
    ]


def centroid(bundle: dict[str, Any]) -> tuple[float, float]:
    values = points(bundle)
    return sum(x for x, _ in values) / len(values), sum(y for _, y in values) / len(values)


def cell_name(prefix: str, identifier: str) -> str:
    return (prefix + "_" + re.sub(r"[^A-Za-z0-9_]", "_", identifier))[:120]


def write_lyp(path: Path) -> None:
    colors = {
        "die": "#303030", "block": "#32cd32", "keepout": "#ff4d4d", "connectivity": "#f5f5f5",
        "data": "#1f77b4", "command_address": "#ff7f0e", "clock": "#e377c2",
        "power": "#d62728", "ground": "#2f2f2f", "spare": "#bcbd22", "unknown": "#7f7f7f",
        "phy": "#9467bd", "pdn": "#8c564b", "decap": "#17becf", "routing": "#00bcd4",
    }
    entries = [(100, 0, "DIE_OUTLINE", colors["die"]), (110, 0, "LOGIC_BLOCKS", colors["block"]), (130, 0, "TSV_KEEP_OUT", colors["keepout"]), (170, 0, "CONNECTIVITY", colors["connectivity"]), (199, 0, "OBJECT_LABELS", "#ffffff")]
    entries += [(layer, 0, f"TSV_{name.upper()}", colors[name]) for name, layer in SIGNAL_LAYERS.items()]
    entries += [(layer, 0, f"MICROBUMP_{name.upper()}", colors[name]) for name, layer in BUMPLAYERS.items()]
    entries += [(layer, 0, f"RESERVED_{name.upper()}", colors.get(name, "#aaaaaa")) for name, layer in REGION_LAYERS.items()]
    thermal_colors = ["#000004", "#0d0829", "#2a0a5e", "#450a69", "#60136e", "#781c6d", "#922568", "#aa2e5d", "#c43c4e", "#dc5039", "#ed6925", "#f8850f", "#fca50a", "#f6c53a", "#f2e661", "#fcffa4"]
    entries += [(layer, 0, f"THERMAL_BIN_{index:02d}_LOW_TO_HIGH", thermal_colors[index]) for index, layer in enumerate(THERMAL_LAYERS)]
    lines = ["<?xml version=\"1.0\" encoding=\"utf-8\"?>", "<layer-properties>"]
    for layer, datatype, name, color in entries:
        lines += ["  <properties>", f"    <frame-color>{color}</frame-color>", f"    <fill-color>{color}</fill-color>", "    <frame-brightness>0</frame-brightness>", "    <fill-brightness>0</fill-brightness>", "    <dither-pattern>I3</dither-pattern>", "    <visible>true</visible>", "    <transparent>false</transparent>", f"    <name>{name}</name>", f"    <source>{layer}/{datatype}@1</source>", "  </properties>"]
    lines.append("</layer-properties>")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def export(manifest_path: str, output_dir: str, thermal_field: str | None = None) -> dict[str, Any]:
    manifest = json.loads(absolute(manifest_path).read_text(encoding="utf-8-sig"))
    output = absolute(output_dir)
    output.mkdir(parents=True, exist_ok=True)
    library = gdstk.Library(unit=1e-6, precision=1e-9)
    top = library.new_cell(TOP)
    rect(top, manifest["die"], 100)
    block_centers = {}
    for index, block in enumerate(manifest["blocks"], 1):
        datatype = {"illustrative": 1, "estimated": 2, "placed": 3, "synthesized": 4}.get(block["classification"], 0)
        block_cell = library.new_cell(cell_name("BLOCK", block["instance"]))
        local_block = {"x_um": 0, "y_um": 0, "width_um": block["width_um"], "height_um": block["height_um"]}
        rect(block_cell, local_block, 110, datatype)
        block_cell.add(gdstk.Label(f"BLOCK:{block['instance']} [{block['classification']}]", (float(block["width_um"]) / 2, float(block["height_um"]) / 2), layer=199, texttype=1))
        top.add(gdstk.Reference(block_cell, (float(block["x_um"]), float(block["y_um"]))))
        center = (float(block["x_um"]) + float(block["width_um"]) / 2, float(block["y_um"]) + float(block["height_um"]) / 2)
        block_centers[block["instance"]] = center
    bundle_centers = {bundle["bundle_id"]: centroid(bundle) for bundle in manifest["tsv_bundles"] + manifest["micro_bump_bundles"]}
    tsv_shapes = 0
    bump_shapes = 0
    for bundle in manifest["tsv_bundles"]:
        radius = float(bundle["diameter_um"]) / 2
        koz_radius = radius + float(bundle["keepout_um"])
        bundle_cell = library.new_cell(cell_name("TSV", bundle["bundle_id"]))
        for column in range(int(bundle["columns"])):
            for row in range(int(bundle["rows"])):
                point = (column * float(bundle["pitch_um"]), row * float(bundle["pitch_um"]))
                bundle_cell.add(gdstk.ellipse(point, radius, layer=SIGNAL_LAYERS[bundle["signal_class"]]))
                bundle_cell.add(gdstk.ellipse(point, koz_radius, layer=130, datatype=SIGNAL_ORDER.index(bundle["signal_class"])))
                tsv_shapes += 1
        bundle_cell.add(gdstk.Label(f"{bundle['bundle_id']}:{bundle['signal_class']}:{len(points(bundle))}", (0, 0), layer=199, texttype=2))
        top.add(gdstk.Reference(bundle_cell, (float(bundle["x_um"]), float(bundle["y_um"]))))
    for bundle in manifest["micro_bump_bundles"]:
        radius = float(bundle["diameter_um"]) / 2
        bundle_cell = library.new_cell(cell_name("BUMP", bundle["bundle_id"]))
        for column in range(int(bundle["columns"])):
            for row in range(int(bundle["rows"])):
                point = (column * float(bundle["pitch_um"]), row * float(bundle["pitch_um"]))
                bundle_cell.add(gdstk.ellipse(point, radius, layer=BUMPLAYERS[bundle["signal_class"]]))
                bump_shapes += 1
        bundle_cell.add(gdstk.Label(f"{bundle['bundle_id']}:{bundle['signal_class']}:{len(points(bundle))}", (0, 0), layer=199, texttype=3))
        top.add(gdstk.Reference(bundle_cell, (float(bundle["x_um"]), float(bundle["y_um"]))))
    for region in manifest["reserved_regions"]:
        rect(top, region, REGION_LAYERS[region["role"]], 1 if region["blocks_prohibited"] else 0)
        top.add(gdstk.Label(f"RESERVED:{region['region_id']} [{region['classification']}]", (region["x_um"] + region["width_um"] / 2, region["y_um"] + region["height_um"] / 2), layer=199, texttype=4))
    for corridor in manifest["routing_corridors"]:
        rect(top, corridor, REGION_LAYERS["routing"], 0)
    for bundle in manifest["micro_bump_bundles"]:
        source = bundle_centers.get(bundle["source"])
        if source:
            target = bundle_centers[bundle["bundle_id"]]
            if source != target:
                top.add(gdstk.FlexPath([source, target], 8.0, layer=170, datatype=SIGNAL_ORDER.index(bundle["signal_class"])))
        for destination in bundle["destinations"]:
            target = block_centers.get(destination)
            if target:
                top.add(gdstk.FlexPath([bundle_centers[bundle["bundle_id"]], target], 8.0, layer=170, datatype=SIGNAL_ORDER.index(bundle["signal_class"])))
    thermal_bins = 0
    thermal_range_K = None
    if thermal_field:
        thermal_path = absolute(thermal_field)
        with np.load(thermal_path) as fields:
            temperature = fields["temperature_K"]
        active = np.max(temperature[2:19], axis=0)
        low, high = float(active.min()), float(active.max())
        span = max(high - low, 1e-12)
        dx = float(manifest["die"]["width_um"]) / active.shape[1]
        dy = float(manifest["die"]["height_um"]) / active.shape[0]
        thermal_cell = library.new_cell("THERMAL_FIELD_REFERENCE_SOLVER_NOT_SIGNOFF")
        for y in range(active.shape[0]):
            for x in range(active.shape[1]):
                quantized = min(15, int(16 * (float(active[y, x]) - low) / span))
                thermal_cell.add(gdstk.rectangle((x * dx, y * dy), ((x + 1) * dx, (y + 1) * dy), layer=THERMAL_LAYERS[quantized]))
                thermal_bins += 1
        thermal_cell.add(gdstk.Label(f"THERMAL_MODELED_K:{low:.6f}:{high:.6f}:NOT_SIGNOFF", (0, 0), layer=199, texttype=5))
        top.add(gdstk.Reference(thermal_cell))
        thermal_range_K = [low, high]
    gds_path = output / "logic_die_floorplan.gds"
    lyp_path = output / "logic_die_floorplan.lyp"
    # Fixed stream timestamps make clean regeneration byte-for-byte stable.
    library.write_gds(gds_path, timestamp=datetime(1970, 1, 1))
    write_lyp(lyp_path)
    die = manifest["die"]
    expected_bbox_um = [
        float(die["x_um"]),
        float(die["y_um"]),
        float(die["x_um"]) + float(die["width_um"]),
        float(die["y_um"]) + float(die["height_um"]),
    ]
    report = {
        "status": "PASS", "top_cell": TOP, "manifest": str(absolute(manifest_path)),
        "gds": str(gds_path), "lyp": str(lyp_path),
        "geometry": {
            "expected_top_bbox_um": expected_bbox_um,
            "bbox_source": "manifest.die",
            "gds_timestamp_utc": "1970-01-01T00:00:00Z",
        },
        "counts": {"blocks": len(manifest["blocks"]), "tsv_bundles": len(manifest["tsv_bundles"]), "tsv_shapes": tsv_shapes, "micro_bump_bundles": len(manifest["micro_bump_bundles"]), "micro_bump_shapes": bump_shapes, "reserved_regions": len(manifest["reserved_regions"]), "routing_corridors": len(manifest["routing_corridors"]), "thermal_bins": thermal_bins},
        "layer_map": {"die": 100, "blocks": 110, "tsv_signal_classes": SIGNAL_LAYERS, "tsv_keepout": 130, "micro_bump_signal_classes": BUMPLAYERS, "reserved_regions": REGION_LAYERS, "connectivity": 170, "labels": 199, "thermal_bins_low_to_high": THERMAL_LAYERS},
        "thermal_overlay": {"source": str(absolute(thermal_field)) if thermal_field else None, "range_K": thermal_range_K, "classification": "modeled", "signoff": False},
        "traceability": "block, TSV bundle and micro-bump bundle IDs are encoded as child-cell names and labels",
        "scope": "Manifest-driven research visualization; not a manufacturing mask set or signoff layout."
    }
    (output / "visualization_manifest.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"FLOORPLAN_GDS_EXPORTED tsv={tsv_shapes} bumps={bump_shapes} output={gds_path}")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", default="design/floorplan/logic_die_floorplan.json")
    parser.add_argument("--output", default="output/floorplan_optimization/baseline/visualization")
    parser.add_argument("--thermal-field", help="optional reference-solver NPZ temperature field")
    args = parser.parse_args()
    export(args.manifest, args.output, args.thermal_field)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
