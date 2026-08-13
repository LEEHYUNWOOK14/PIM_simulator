#!/usr/bin/env python3
"""Independently reopen the current wbq RTL GDS and freeze structural evidence."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from klayout_python import kdb

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/final_integrated_gds_execution"
RAW = ROOT / "reports/groot_normalization/physical_feasibility"
DEFAULT_GDS = ROOT / "output/final_integrated_gds/inputs/integrated_rtl_routed.gds"
DEFAULT_SOURCE = OUT / "wbq_phase7_detailed_route_manifest.json"
DEFAULT_LOG = RAW / "logic_die_normalization_hbm_top_wbq_phase7_rtl_gds_streamout.log"
METAL_LAYERS = {68, 69, 70, 71, 72}
VIA_LAYERS = {66, 67, 68, 69, 70, 71}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def count_recursive(cell, layer_index: int) -> int:
    count = 0
    iterator = cell.begin_shapes_rec(layer_index)
    while not iterator.at_end():
        count += 1
        iterator.next()
    return count


def inspect(gds_path: Path, source_path: Path, log_path: Path) -> dict:
    for path in (gds_path, source_path, log_path):
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"missing/non-empty RTL GDS evidence input: {path}")
    source = json.loads(source_path.read_text(encoding="utf-8-sig"))
    log = log_path.read_text(encoding="utf-8", errors="replace")
    actual_gds_hash = sha256(gds_path)
    logged_hashes = re.findall(r"^WBQ_RTL_GDS_OUTPUT_SHA256=(\S+)$", log, flags=re.MULTILINE)

    layout = kdb.Layout()
    layout.read(str(gds_path))
    tops = list(layout.top_cells())
    top_names = [cell.name for cell in tops]
    top = tops[0] if len(tops) == 1 else None
    layer_shapes: dict[str, int] = {}
    total_shapes = 0
    populated_metals: set[int] = set()
    via_shapes = 0
    if top is not None:
        for index in layout.layer_indices():
            info = layout.get_info(index)
            count = count_recursive(top, index)
            if count == 0:
                continue
            layer_shapes[f"{info.layer}/{info.datatype}"] = count
            total_shapes += count
            if info.layer in METAL_LAYERS and info.datatype in {20, 44}:
                populated_metals.add(info.layer)
            if info.layer in VIA_LAYERS and info.datatype in {44, 60}:
                via_shapes += count
    bbox = top.bbox() if top is not None else None
    bbox_um = None if bbox is None else [
        bbox.left * layout.dbu, bbox.bottom * layout.dbu,
        bbox.right * layout.dbu, bbox.top * layout.dbu,
    ]
    checks = {
        "phase7_gate_pass": source.get("gate_pass") is True,
        "phase7_not_manufacturing_signoff": source.get("manufacturing_signoff") is False,
        "streamout_exit_zero": "WBQ_RTL_GDS_EXIT_CODE=0" in log,
        "streamout_pass_marker": "NORMALIZATION_HBM_WBQ_PHASE7_RTL_GDS_STREAMOUT PASS" in log,
        "streamout_output_hash_match": bool(logged_hashes) and logged_hashes[-1] == actual_gds_hash,
        "exactly_one_top": len(tops) == 1,
        "expected_top": top_names == ["logic_die_normalization_hbm_top"],
        "dbu_positive": layout.dbu > 0,
        "bbox_nonempty": top is not None and not top.bbox().empty(),
        "hierarchy_nonempty": layout.cells() > 1,
        "geometry_nonempty": total_shapes > 0,
        "met1_through_met5_present": populated_metals == METAL_LAYERS,
        "via_geometry_present": via_shapes > 0,
    }
    return {
        "schema_version": 1,
        "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        "classification": "routed_research_artifact",
        "status": "PASS" if all(checks.values()) else "FAIL",
        "signoff": False,
        "git_sha": subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip(),
        "source_manifest": str(source_path),
        "source_manifest_sha256": sha256(source_path),
        "streamout_log": str(log_path),
        "streamout_log_sha256": sha256(log_path),
        "gds": {"path": str(gds_path), "bytes": gds_path.stat().st_size, "sha256": actual_gds_hash},
        "checks": checks,
        "geometry": {
            "top_cells": top_names,
            "dbu_um": layout.dbu,
            "bbox_um": bbox_um,
            "cell_count": layout.cells(),
            "recursive_shape_count": total_shapes,
            "populated_metal_gds_layers": sorted(populated_metals),
            "via_shape_count": via_shapes,
            "populated_layer_shapes": layer_shapes,
        },
        "streamout_boundary": "Pinned OpenROAD has no write_gds command; the official ORFS KLayout DEF-to-stream path was used.",
        "claim_boundary": "Structurally valid, independently reopened routed RTL GDS research artifact; no manufacturing signoff is claimed. RESEARCH ARTIFACT — NOT FOR FABRICATION",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gds", type=Path, default=DEFAULT_GDS)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--log", type=Path, default=DEFAULT_LOG)
    args = parser.parse_args()
    try:
        payload = inspect(args.gds.resolve(), args.source.resolve(), args.log.resolve())
    except (OSError, ValueError, json.JSONDecodeError, RuntimeError) as error:
        print(f"WBQ_PHASE7_RTL_GDS_READBACK FAIL error={error}")
        return 2
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "wbq_phase7_rtl_gds_manifest.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    esc = lambda value: html.escape(str(value))
    report = f"""<!doctype html><html lang=\"ko\"><head><meta charset=\"utf-8\"><title>WBQ RTL GDS 보고서</title><style>body{{font-family:system-ui,sans-serif;max-width:1080px;margin:32px auto;color:#182235}}h1,h2{{color:#173f6b}}table{{border-collapse:collapse;width:100%}}th,td{{padding:10px;border-bottom:1px solid #ddd;text-align:left}}th{{background:#eef3f8}}.verdict{{padding:16px;background:{'#e7f6ed' if payload['status']=='PASS' else '#fdecec'};border-left:6px solid {'#168154' if payload['status']=='PASS' else '#a12626'}}}</style></head><body><h1>Phase 7 — routed RTL GDS</h1><div class=\"verdict\"><strong>{payload['status']}</strong><br>Independent KLayout readback / signoff=false</div><h2>Geometry</h2><table><tr><th>Top</th><td>{esc(payload['geometry']['top_cells'])}</td></tr><tr><th>DBU / bbox µm</th><td>{esc(payload['geometry']['dbu_um'])} / {esc(payload['geometry']['bbox_um'])}</td></tr><tr><th>Cells / recursive shapes</th><td>{payload['geometry']['cell_count']:,} / {payload['geometry']['recursive_shape_count']:,}</td></tr><tr><th>Metal GDS layers</th><td>{esc(payload['geometry']['populated_metal_gds_layers'])}</td></tr><tr><th>Via shapes</th><td>{payload['geometry']['via_shape_count']:,}</td></tr><tr><th>GDS SHA-256</th><td><code>{payload['gds']['sha256']}</code></td></tr></table><p>Pinned OpenROAD에는 직접 GDS writer가 없어 ORFS 공식 KLayout DEF-to-stream 경로를 사용했다. 구조적 readback 결과이며 제조 signoff가 아니다. <strong>RESEARCH ARTIFACT — NOT FOR FABRICATION.</strong></p></body></html>"""
    (OUT / "07_rtl_gds_report.html").write_text(report, encoding="utf-8")
    print(f"WBQ_PHASE7_RTL_GDS_READBACK {payload['status']} sha256={payload['gds']['sha256']}")
    return 0 if payload["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
