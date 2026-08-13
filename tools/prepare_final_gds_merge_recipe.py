#!/usr/bin/env python3
"""Inventory two layouts and emit a hash-pinned, reviewable merge recipe."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import klayout.db as kdb

from merge_final_rtl_gds import ROOT, absolute, sha256, used_layers


def parse_anchor(value: str) -> dict:
    fields = value.split(":")
    if len(fields) != 5:
        raise argparse.ArgumentTypeError("anchor must be name:source_x_um:source_y_um:target_x_um:target_y_um")
    name, sx, sy, tx, ty = fields
    return {"name": name, "source_um": {"x_um": float(sx), "y_um": float(sy)},
            "target_um": {"x_um": float(tx), "y_um": float(ty)}}


def parse_manifest_anchor(value: str) -> dict:
    fields = value.split(":")
    if len(fields) != 6:
        raise argparse.ArgumentTypeError("manifest anchor must be name:source_x_um:source_y_um:object_type:object_id:point")
    name, sx, sy, object_type, object_id, target_point = fields
    return {"name": name, "source_um": {"x_um": float(sx), "y_um": float(sy)},
            "target_manifest_ref": {"object_type": object_type, "object_id": object_id, "point": target_point}}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rtl-gds", required=True); parser.add_argument("--rtl-top", required=True)
    parser.add_argument("--overlay-gds", required=True); parser.add_argument("--overlay-top", required=True)
    parser.add_argument("--manifest", required=True); parser.add_argument("--overlay-lyp")
    parser.add_argument("--recipe", required=True); parser.add_argument("--output-root", required=True)
    parser.add_argument("--report", help="optional report path outside output-root")
    parser.add_argument("--orientation", default="R0", choices=["R0","R90","R180","R270","MX","MY","MXR90","MYR90"])
    parser.add_argument("--anchor", action="append", type=parse_anchor, default=[])
    parser.add_argument("--manifest-anchor", action="append", type=parse_manifest_anchor, default=[])
    parser.add_argument("--anchor-tolerance-um", type=float, default=0.01)
    parser.add_argument("--minimum-anchor-count", type=int, default=2)
    args = parser.parse_args()
    anchors = args.anchor + args.manifest_anchor
    if not anchors:
        parser.error("at least one --anchor or --manifest-anchor is required; physical placement must not be guessed")
    if len(anchors) < args.minimum_anchor_count:
        parser.error(f"at least {args.minimum_anchor_count} anchors are required")
    rtl_path, overlay_path = absolute(args.rtl_gds), absolute(args.overlay_gds)
    rtl = kdb.Layout(); rtl.read(str(rtl_path)); overlay = kdb.Layout(); overlay.read(str(overlay_path))
    rtl_top, overlay_top = rtl.cell(args.rtl_top), overlay.cell(args.overlay_top)
    if rtl_top is None or overlay_top is None: raise SystemExit("selected top cell missing")
    rtl_layers, overlay_layers = used_layers(rtl, rtl_top), used_layers(overlay, overlay_top)
    occupied = set(overlay_layers)
    rules = []
    next_safe = 1
    for layer, datatype in sorted(rtl_layers):
        target = (layer, datatype)
        if target in occupied:
            while (next_safe, 0) in occupied or (next_safe, 0) in rtl_layers:
                next_safe += 1
            if next_safe >= 100: raise SystemExit("no collision-free layer below overlay range; provide a manual recipe")
            target = (next_safe, 0); next_safe += 1
        occupied.add(target)
        rules.append({"name": f"source_{layer}_{datatype}" + ("_AUTO_REMAP_REVIEW" if target != (layer,datatype) else ""),
                      "from": {"layer": layer, "datatype": datatype}, "to": {"layer": target[0], "datatype": target[1]}})
    output_root = absolute(args.output_root)
    recipe = {
        "schema_version": "1.0",
        "inputs": {
            "rtl": {"path": str(rtl_path), "top_cell": args.rtl_top, "expected_sha256": sha256(rtl_path)},
            "overlay": {"path": str(overlay_path), "top_cell": args.overlay_top, "expected_sha256": sha256(overlay_path)},
            "floorplan_manifest": str(absolute(args.manifest)),
            "overlay_lyp": str(absolute(args.overlay_lyp)) if args.overlay_lyp else None,
        },
        "output": {"gds": str(output_root / "merged_final_physical.gds"), "lyp": str(output_root / "merged_final_physical.lyp"),
                   "report": str(absolute(args.report)) if args.report else str(output_root / "merged_final_physical_report.json"), "top_cell": "STOB_FINAL_PHYSICAL_MERGED_NOT_SIGNOFF", "dbu_um": 0.001},
        "namespaces": {"rtl_prefix": "RTL__", "overlay_prefix": "OVERLAY__"},
        "layer_mapping": {"unmapped_rtl_policy": "error", "forbid_overlay_collisions": True, "rules": rules},
        "placement": {"orientation": args.orientation, "physical_scale": 1.0, "allow_non_unit_scale": False,
                      "translation_mode": "from_anchors", "anchor_tolerance_um": args.anchor_tolerance_um, "anchors": anchors},
        "verification": {"require_anchor_alignment": True, "minimum_anchor_count": args.minimum_anchor_count, "require_rtl_shapes": True, "require_overlay_shapes": True,
                         "enforce_rtl_within_manifest_die": True},
    }
    recipe_path = absolute(args.recipe); recipe_path.parent.mkdir(parents=True, exist_ok=True)
    recipe_path.write_text(json.dumps(recipe, indent=2), encoding="utf-8")
    print(f"FINAL_GDS_MERGE_RECIPE PASS rtl_layers={len(rtl_layers)} overlay_layers={len(overlay_layers)} rules={len(rules)} output={recipe_path}")
    return 0


if __name__ == "__main__": raise SystemExit(main())
