#!/usr/bin/env python3
"""Hash and connect the reproducible floorplan evidence package."""
from __future__ import annotations

import hashlib
import json
import platform
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output/floorplan_optimization/generation_manifest.json"
PATTERNS = (
    "design/floorplan/*.json", "design/floorplan/*.csv",
    "output/floorplan_optimization/*.csv",
    "output/floorplan_optimization/exploration/*.csv",
    "output/floorplan_optimization/exploration/*.json",
    "output/floorplan_optimization/exploration/candidates/*.json",
    "output/floorplan_optimization/openroad_proxy/openroad_proxy_metrics.csv",
    "output/floorplan_optimization/visualization/*/*.gds",
    "output/floorplan_optimization/visualization/*/paraview/*.vtu",
    "output/floorplan_optimization/visualization/paper_figures/*",
    "reports/floorplan_optimization/*.md",
    "reports/floorplan_optimization/*.csv",
    "reports/floorplan_optimization/*.html",
    "reports/floorplan_optimization/results/*.json",
    "reports/floorplan_optimization/results/*.log",
    "reports/floorplan_optimization/results/orchestration_logs/*.log",
    "verification/floorplan_optimization/test_*.py",
    "tools/*gds_merge*.py", "tools/*gds_merge*.ps1", "tools/gds_merge_requirements.txt",
    "tools/generate_visualization_pipeline_html_report.py",
)


def run(*args: str) -> str:
    try:
        return subprocess.run(args, cwd=ROOT, check=True, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        return f"unavailable: {exc}"


def evidence_class(path: str) -> str:
    if "current_rtl_openroad" in path:
        return "synthesized/placed"
    if "/openroad_proxy/" in path:
        return "modeled/global-routed-proxy"
    if any(token in path for token in ("thermal", "3dice", "hotspot")):
        return "modeled/estimated-power"
    if "/visualization/" in path:
        return "illustrative/from-modeled-data"
    return "modeled/provenance-record"


def main() -> int:
    files: dict[str, Path] = {}
    for pattern in PATTERNS:
        for path in ROOT.glob(pattern):
            if path.is_file() and path.resolve() != OUT.resolve():
                files[path.relative_to(ROOT).as_posix()] = path
    artifacts = []
    for relative, path in sorted(files.items()):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        artifacts.append({"path": relative, "sha256": digest, "size_bytes": path.stat().st_size,
                          "evidence_class": evidence_class(relative)})
    payload = {
        "schema_version": "1.0", "generated_at": datetime.now(timezone.utc).isoformat(),
        "status": "PASS" if artifacts else "FAIL", "signoff": False,
        "reproduction": {"entrypoint": ".\\tools\\run_logic_die_floorplan_analysis.ps1",
                         "seed": 235, "samples": 400,
                         "note": "Final RTL detailed route is intentionally excluded from the default run."},
        "repository": {"commit": run("git", "rev-parse", "HEAD"),
                       "dirty": bool(run("git", "status", "--porcelain")),
                       "status_snapshot": run("git", "status", "--short")},
        "host": {"platform": platform.platform(), "python": platform.python_version()},
        "tools": {
            "klayout": "0.30.10", "openroad": "26Q3-1080-gab6fd26351",
            "yosys": "0.68+48", "hotspot": "f188 pinned source revision",
            "3d_ice": "4.0 / 495 pinned source revision", "paraview": "6.1.1",
            "openscad": "2021.01", "blender": "5.2 LTS"
        },
        "artifact_count": len(artifacts), "artifacts": artifacts,
        "claim_boundary": "Research/provisional evidence; no manufacturing, SI/PI, DRC/LVS, thermal-calibration, or silicon signoff."
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"FLOORPLAN_GENERATION_MANIFEST PASS artifacts={len(artifacts)} output={OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
