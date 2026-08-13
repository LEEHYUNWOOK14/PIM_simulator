#!/usr/bin/env python3
"""Independently audit and clean-regenerate the complete wbq research GDS."""

from __future__ import annotations

import hashlib
import html
import json
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from merge_final_rtl_gds import merge

ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "reports/final_integrated_gds_execution"
OUTPUT = ROOT / "output/final_integrated_gds"
RECIPE = OUTPUT / "recipe/final_gds_merge_recipe.json"
FINAL_GDS = OUTPUT / "final/merged_final_physical.gds"
FINAL_LYP = OUTPUT / "final/merged_final_physical.lyp"
MERGE_REPORT = OUTPUT / "validation/merged_final_physical_report.json"
CAMERA = OUTPUT / "validation/klayout_fixed_camera.png"
DISCLAIMER = "RESEARCH ARTIFACT — NOT FOR FABRICATION"

REQUIRED_REPORTS = [
    "00_environment_and_baseline_report.html",
    "01_wbq_functional_regression_report.html",
    "02_wbq_synthesis_report.html",
    "03_wbq_placement_report.html",
    "04_wbq_global_route_report.html",
    "06_clock_and_detailed_route_report.html",
    "07_rtl_gds_report.html",
    "08_overlay_merge_report.html",
]
REQUIRED_MANIFESTS = [
    "environment_manifest.json",
    "wbq_functional_manifest.json",
    "wbq_synthesis_manifest.json",
    "wbq_placement_manifest.json",
    "wbq_global_route_manifest.json",
    "wbq_phase6_cts_manifest.json",
    "wbq_phase6_post_cts_route_manifest.json",
    "wbq_phase7_detailed_route_manifest.json",
    "wbq_phase7_rtl_gds_manifest.json",
    "wbq_overlay_validation.json",
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    required = [RECIPE, FINAL_GDS, FINAL_LYP, MERGE_REPORT, CAMERA]
    required += [REPORTS / name for name in REQUIRED_REPORTS + REQUIRED_MANIFESTS]
    missing = [str(path) for path in required if not path.is_file() or path.stat().st_size == 0]
    if missing:
        print("WBQ_FINAL_COMPLETION_AUDIT FAIL missing/non-empty:\n" + "\n".join(missing))
        return 2

    manifests = {name: json.loads((REPORTS / name).read_text(encoding="utf-8-sig")) for name in REQUIRED_MANIFESTS}
    merge_report = json.loads(MERGE_REPORT.read_text(encoding="utf-8-sig"))
    phase_checks = {
        "environment": manifests["environment_manifest.json"].get("gate_pass") is True,
        "functional": manifests["wbq_functional_manifest.json"].get("gate_pass") is True,
        "synthesis": manifests["wbq_synthesis_manifest.json"].get("gate_pass") is True,
        "placement": manifests["wbq_placement_manifest.json"].get("gate_pass") is True,
        "global_route": manifests["wbq_global_route_manifest.json"].get("verdict") == "PASS_PF4",
        "cts": manifests["wbq_phase6_cts_manifest.json"].get("gate_pass") is True,
        "post_cts_route": manifests["wbq_phase6_post_cts_route_manifest.json"].get("gate_pass") is True,
        "detailed_route": manifests["wbq_phase7_detailed_route_manifest.json"].get("gate_pass") is True,
        "rtl_gds": manifests["wbq_phase7_rtl_gds_manifest.json"].get("status") == "PASS",
        "overlay": manifests["wbq_overlay_validation.json"].get("status") == "PASS",
        "merge": merge_report.get("status") == "PASS",
    }
    signoff_checks = {
        "detailed_route_not_signoff": manifests["wbq_phase7_detailed_route_manifest.json"].get("manufacturing_signoff") is False,
        "rtl_gds_not_signoff": manifests["wbq_phase7_rtl_gds_manifest.json"].get("signoff") is False,
        "overlay_not_signoff": manifests["wbq_overlay_validation.json"].get("signoff") is False,
        "merge_not_signoff": merge_report.get("signoff") is False,
        "merge_disclaimer": DISCLAIMER in merge_report.get("claim_boundary", ""),
    }
    original_hash = sha256(FINAL_GDS)
    persisted_checks = {
        "merged_gds_hash": merge_report.get("output", {}).get("gds_sha256") == original_hash,
        "rtl_shapes": merge_report.get("geometry", {}).get("post_readback_shapes", {}).get("rtl", 0) > 0,
        "overlay_shapes": merge_report.get("geometry", {}).get("post_readback_shapes", {}).get("overlay", 0) > 0,
        "two_top_instances": merge_report.get("cell_namespace", {}).get("output_top_instance_count") == 2,
        "two_anchors": len(merge_report.get("anchors", [])) == 2,
        "zero_anchor_residual": merge_report.get("max_anchor_residual_um") == 0.0,
        "camera_nonempty": CAMERA.stat().st_size > 0,
    }

    with tempfile.TemporaryDirectory(prefix="stob_wbq_clean_regeneration_") as temp_name:
        temp = Path(temp_name)
        recipe = json.loads(RECIPE.read_text(encoding="utf-8-sig"))
        recipe["output"] = {
            **recipe["output"],
            "gds": str(temp / "merged_final_physical.gds"),
            "lyp": str(temp / "merged_final_physical.lyp"),
            "report": str(temp / "merged_final_physical_report.json"),
        }
        clean_recipe = temp / "final_gds_merge_recipe.json"
        clean_recipe.write_text(json.dumps(recipe, indent=2) + "\n", encoding="utf-8")
        clean_report = merge(clean_recipe)
        clean_gds = temp / "merged_final_physical.gds"
        clean_hash = sha256(clean_gds)
        regeneration = {
            "status": clean_report.get("status"),
            "temporary_output_was_clean": True,
            "original_gds_sha256": original_hash,
            "regenerated_gds_sha256": clean_hash,
            "byte_identical": clean_hash == original_hash,
        }

    all_checks = {**phase_checks, **signoff_checks, **persisted_checks,
                  "clean_regeneration_byte_identical": regeneration["byte_identical"]}
    status = "PASS" if all(all_checks.values()) else "FAIL"
    artifacts = {
        "recipe": RECIPE, "final_gds": FINAL_GDS, "final_lyp": FINAL_LYP,
        "merge_report": MERGE_REPORT, "fixed_camera_png": CAMERA,
        **{name: REPORTS / name for name in REQUIRED_REPORTS + REQUIRED_MANIFESTS},
    }
    payload = {
        "schema_version": 1,
        "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        "status": status,
        "classification": "routed_research_artifact" if status == "PASS" else "unknown",
        "manufacturing_signoff": False,
        "git_sha_before_completion_commit": subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True
        ).strip(),
        "checks": all_checks,
        "clean_regeneration": regeneration,
        "known_limitations": {
            "final_drc_violations": manifests["wbq_phase7_detailed_route_manifest.json"].get("metrics", {}).get("final_drc_violations"),
            "antenna_violating_nets": manifests["wbq_phase7_detailed_route_manifest.json"].get("metrics", {}).get("antenna_violating_nets"),
            "timing_signoff": False,
            "foundry_drc_lvs": False,
            "ir_em_signoff": False,
            "overlay_geometry": "illustrative/estimated/modelled",
        },
        "artifacts": {
            name: {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)}
            for name, path in artifacts.items()
        },
        "reproduction_command": "PYTHONPATH=tools python3 tools/audit_wbq_final_completion.py",
        "claim_boundary": DISCLAIMER + ". Research visualization and reproducibility artifact only; not tape-out or fabrication readiness.",
    }
    completion = REPORTS / "wbq_final_completion_manifest.json"
    final_html = REPORTS / "09_final_completion_report.html"
    completion.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    esc = lambda value: html.escape(str(value))
    final_html.write_text(f"""<!doctype html><html lang=\"ko\"><head><meta charset=\"utf-8\"><title>STOB PIM2 최종 연구 GDS 완료 보고서</title><style>body{{font-family:system-ui,sans-serif;max-width:1120px;margin:32px auto;color:#182235}}h1,h2{{color:#173f6b}}table{{border-collapse:collapse;width:100%}}th,td{{padding:10px;border-bottom:1px solid #ddd;text-align:left}}th{{background:#eef3f8}}.verdict{{padding:18px;background:{'#e7f6ed' if status=='PASS' else '#fdecec'};border-left:6px solid {'#168154' if status=='PASS' else '#a12626'}}}code{{word-break:break-all}}</style></head><body><h1>STOB_PIM2_FINAL_INTEGRATED_RESEARCH_GDS</h1><div class=\"verdict\"><strong>{status}</strong><br>현재 wbq RTL → CTS → detailed route → RTL GDS → overlay → merged GDS → clean regeneration</div><h2>Final artifact</h2><table><tr><th>GDS</th><td>{esc(FINAL_GDS)}</td></tr><tr><th>SHA-256</th><td><code>{original_hash}</code></td></tr><tr><th>Clean regeneration</th><td>{esc(regeneration)}</td></tr><tr><th>Fixed camera</th><td>{esc(CAMERA)}</td></tr></table><h2>Known limitations</h2><pre>{esc(json.dumps(payload['known_limitations'], indent=2))}</pre><p><strong>{DISCLAIMER}.</strong> 제조 승인, tape-out, foundry DRC/LVS, timing, IR/EM signoff 결과가 아니다.</p></body></html>""", encoding="utf-8")
    print(f"WBQ_FINAL_COMPLETION_AUDIT {status} gds_sha256={original_hash}")
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
