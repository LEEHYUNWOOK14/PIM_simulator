#!/usr/bin/env python3
"""Affine-transform the validated canonical overlay into the current RTL GDS frame."""

from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "design/floorplan/logic_die_floorplan.json"
DEFAULT_RTL = ROOT / "reports/final_integrated_gds_execution/wbq_phase7_rtl_gds_manifest.json"
DEFAULT_OUTPUT = ROOT / "output/final_integrated_gds/inputs/floorplan_manifest.json"
DEFAULT_CSV = ROOT / "output/final_integrated_gds/inputs/tsv_connectivity.csv"
DEFAULT_TRANSFORM = ROOT / "output/final_integrated_gds/inputs/floorplan_transform.json"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def transform(source: dict, bbox_um: list[float]) -> dict:
    if len(bbox_um) != 4 or bbox_um[2] <= bbox_um[0] or bbox_um[3] <= bbox_um[1]:
        raise ValueError("RTL GDS bbox must be [left,bottom,right,top] with positive area")
    result = copy.deepcopy(source)
    old = source["die"]
    old_x, old_y = float(old["x_um"]), float(old["y_um"])
    old_w, old_h = float(old["width_um"]), float(old["height_um"])
    new_x, new_y = float(bbox_um[0]), float(bbox_um[1])
    new_w, new_h = float(bbox_um[2] - bbox_um[0]), float(bbox_um[3] - bbox_um[1])
    sx, sy = new_w / old_w, new_h / old_h
    radial = min(sx, sy)

    def x(value: float) -> float:
        return new_x + (float(value) - old_x) * sx

    def y(value: float) -> float:
        return new_y + (float(value) - old_y) * sy

    def rectangle(item: dict) -> None:
        item["x_um"] = x(item["x_um"])
        item["y_um"] = y(item["y_um"])
        item["width_um"] = float(item["width_um"]) * sx
        item["height_um"] = float(item["height_um"]) * sy

    result["die"] = {"x_um": new_x, "y_um": new_y, "width_um": new_w, "height_um": new_h}
    for block in result["blocks"]:
        rectangle(block)
        block["halo_um"] = float(block["halo_um"]) * radial
        if block.get("allowed_region") is not None:
            rectangle(block["allowed_region"])
        block["classification"] = "illustrative"
        block["confidence"] = "low"
        block["placement_source"] = "affine_transform_of_validated_canonical_overlay"
        block["status"] = "illustrative"
    for region in result["reserved_regions"] + result["routing_corridors"]:
        rectangle(region)
    for bundle in result["tsv_bundles"] + result["micro_bump_bundles"]:
        bundle["x_um"] = x(bundle["x_um"])
        bundle["y_um"] = y(bundle["y_um"])
        bundle["pitch_um"] = float(bundle["pitch_um"]) * radial
        bundle["diameter_um"] = float(bundle["diameter_um"]) * radial
        bundle["keepout_um"] = float(bundle["keepout_um"]) * radial
        bundle["classification"] = "illustrative"
        bundle["confidence"] = "low"
        bundle["geometry_source"] = "current_rtl_gds_bbox_affine_transform"
    result["manifest_id"] = "stob_wbq_current_rtl_gds_overlay_v1"
    result["evidence_snapshot"]["captured_at"] = datetime.now(timezone.utc).isoformat()
    result["evidence_snapshot"]["working_tree_dirty"] = True
    return result


def transform_evidence(source: dict, bbox_um: list[float]) -> dict:
    old = source["die"]
    old_x, old_y = float(old["x_um"]), float(old["y_um"])
    old_w, old_h = float(old["width_um"]), float(old["height_um"])
    new_x, new_y = float(bbox_um[0]), float(bbox_um[1])
    new_w, new_h = float(bbox_um[2] - bbox_um[0]), float(bbox_um[3] - bbox_um[1])
    sx, sy = new_w / old_w, new_h / old_h
    return {
        "schema_version": 1,
        "method": "axis_affine_with_uniform_radial_scaling",
        "source_die_bbox_um": [old_x, old_y, old_x + old_w, old_y + old_h],
        "target_rtl_gds_bbox_um": bbox_um,
        "scale_x": sx,
        "scale_y": sy,
        "radial_scale": min(sx, sy),
        "anchor_count": 2,
        "anchors": [
            {"name": "lower_left", "source_um": [old_x, old_y], "target_um": [new_x, new_y], "error_um": 0.0},
            {"name": "upper_right", "source_um": [old_x + old_w, old_y + old_h], "target_um": [new_x + new_w, new_y + new_h], "error_um": 0.0},
        ],
        "classification": "modeled",
        "claim_boundary": "Coordinate-frame adaptation of illustrative/estimated overlay geometry; not a manufacturer pin map or signoff alignment.",
    }


def write_csv(manifest: dict, path: Path) -> None:
    fields = ["bundle_id", "kind", "signal_class", "source", "destinations", "x_um", "y_um", "rows", "columns", "pitch_um", "diameter_um", "keepout_um", "redundancy_count", "bandwidth_bits", "direction", "geometry_source", "connectivity_source", "classification", "confidence"]
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for bundle in manifest["tsv_bundles"]:
            row = {field: bundle.get(field) for field in fields}
            row["destinations"] = ";".join(bundle["destinations"])
            writer.writerow(row)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--rtl-manifest", type=Path, default=DEFAULT_RTL)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--tsv-output", type=Path, default=DEFAULT_CSV)
    parser.add_argument("--transform-output", type=Path, default=DEFAULT_TRANSFORM)
    args = parser.parse_args()
    source_path, rtl_path = args.source.resolve(), args.rtl_manifest.resolve()
    if not source_path.is_file() or not rtl_path.is_file():
        print("WBQ_OVERLAY_PREPARE FAIL missing source or RTL GDS manifest")
        return 2
    source = json.loads(source_path.read_text(encoding="utf-8-sig"))
    rtl = json.loads(rtl_path.read_text(encoding="utf-8-sig"))
    if rtl.get("status") != "PASS" or rtl.get("signoff") is not False:
        print("WBQ_OVERLAY_PREPARE FAIL RTL GDS manifest is not a non-signoff PASS")
        return 2
    result = transform(source, rtl.get("geometry", {}).get("bbox_um", []))
    result["evidence_snapshot"]["source_manifest_hashes"][str(source_path)] = sha256(source_path)
    result["evidence_snapshot"]["source_manifest_hashes"][str(rtl_path)] = sha256(rtl_path)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    write_csv(result, args.tsv_output)
    args.transform_output.parent.mkdir(parents=True, exist_ok=True)
    args.transform_output.write_text(
        json.dumps(transform_evidence(source, rtl["geometry"]["bbox_um"]), indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"WBQ_OVERLAY_PREPARE PASS manifest={args.output} tsv_csv={args.tsv_output} transform={args.transform_output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
