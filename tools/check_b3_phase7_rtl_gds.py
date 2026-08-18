#!/usr/bin/env python3
"""Independently reopen and gate the B3 Phase 7 routed RTL GDS."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path

from klayout_python import kdb


EXPECTED_TOP = "logic_die_normalization_hbm_quad_local_b2_top"
METALS = {68, 69, 70, 71, 72}
VIAS = {66, 67, 68, 69, 70, 71}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def count_recursive(cell, layer: int) -> int:
    count = 0
    iterator = cell.begin_shapes_rec(layer)
    while not iterator.at_end():
        count += 1
        iterator.next()
    return count


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--gds", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError(f"refusing to overwrite {args.output}")
    for path in (args.gds, args.source, args.log):
        if not path.is_file() or path.stat().st_size == 0:
            raise FileNotFoundError(path)
    source = json.loads(args.source.read_text(encoding="utf-8"))
    log = args.log.read_text(encoding="utf-8", errors="replace")
    actual_hash = sha256(args.gds)
    logged = re.findall(r"^WBQ_B3_RTL_GDS_OUTPUT_SHA256=(\S+)$", log, re.MULTILINE)
    layout = kdb.Layout()
    layout.read(str(args.gds))
    tops = list(layout.top_cells())
    top_names = [cell.name for cell in tops]
    top = tops[0] if len(tops) == 1 else None
    total_shapes = 0
    metals = set()
    via_shapes = 0
    if top is not None:
        for layer in layout.layer_indices():
            info = layout.get_info(layer)
            count = count_recursive(top, layer)
            total_shapes += count
            if count and info.layer in METALS and info.datatype in {20, 44}:
                metals.add(info.layer)
            if count and info.layer in VIAS and info.datatype in {44, 60}:
                via_shapes += count
    bbox = None if top is None else top.bbox()
    bbox_um = None if bbox is None else [bbox.left * layout.dbu, bbox.bottom * layout.dbu,
                                         bbox.right * layout.dbu, bbox.top * layout.dbu]
    checks = {
        "phase7_detailed_route_pass": source.get("status") == "PASS"
        and "B3_PHASE7_RTL_GDS_STREAMOUT" in source.get("authorizes", []),
        "streamout_exit_zero": "WBQ_B3_RTL_GDS_EXIT_CODE=0" in log,
        "streamout_hash_match": bool(logged) and logged[-1] == actual_hash,
        "exactly_one_expected_top": top_names == [EXPECTED_TOP],
        "dbu_positive": layout.dbu > 0,
        "bbox_nonempty": top is not None and not top.bbox().empty(),
        "hierarchy_nonempty": layout.cells() > 1,
        "geometry_nonempty": total_shapes > 0,
        "met1_through_met5_present": metals == METALS,
        "via_geometry_present": via_shapes > 0,
    }
    passed = all(checks.values())
    payload = {
        "schema_version": 1, "phase": 7, "variant": "B3_PHASE7_RTL_GDS",
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "status": "PASS" if passed else "FAIL", "signoff": False,
        "checks": checks,
        "source_manifest": {"path": str(args.source), "sha256": sha256(args.source)},
        "streamout_log": {"path": str(args.log), "sha256": sha256(args.log)},
        "gds": {"path": str(args.gds), "bytes": args.gds.stat().st_size, "sha256": actual_hash},
        "geometry": {"top_cells": top_names, "dbu_um": layout.dbu, "bbox_um": bbox_um,
                     "cell_count": layout.cells(), "recursive_shape_count": total_shapes,
                     "populated_metal_gds_layers": sorted(metals), "via_shape_count": via_shapes},
        "authorizes": ["B3_PHASE8_OVERLAY"] if passed else [],
        "next_stage": "B3_PHASE8_OVERLAY" if passed else None,
        "claim_boundary": "Structurally valid routed RTL GDS research artifact; not manufacturing signoff.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as stream:
        json.dump(payload, stream, indent=2); stream.write("\n")
    print(f"WBQ_B3_PHASE7_RTL_GDS_READBACK {payload['status']} sha256={actual_hash}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
