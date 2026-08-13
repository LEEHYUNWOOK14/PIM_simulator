#!/usr/bin/env python3
"""Audit active final-GDS execution files for desktop-specific hardcoded paths."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ACTIVE = [
    ROOT / "verification/groot_normalization/run_normalization_hbm_top_sky130_mapping.sh",
    ROOT / "verification/groot_normalization/eda_environment.sh",
    ROOT / "verification/groot_normalization/preflight_final_gds_environment.sh",
    *(ROOT / "flow/designs/sky130hd" / name / "config.mk" for name in (
        "normalization_hbm_adapter_feasibility",
        "normalization_hbm_feasibility",
        "normalization_hbm_feasibility_v2",
        "stob_pim2",
    )),
]
PATTERN = re.compile(r"/home/chandler|/mnt/c/orfs|C:[\\/]")


def main() -> int:
    findings = []
    for path in ACTIVE:
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if PATTERN.search(line):
                findings.append({
                    "path": str(path.relative_to(ROOT)),
                    "line": number,
                    "text": line.strip(),
                    "classification": "blocking_active_path",
                })
    output = ROOT / "reports/final_integrated_gds_execution/portability_audit.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema_version": 1,
        "active_files": [str(path.relative_to(ROOT)) for path in ACTIVE],
        "blocking_count": len(findings),
        "historical_count": 0,
        "findings": findings,
        "scope": "Active Phase 0-2 entry points and ORFS design configs; historical experiment scripts are audited separately before reuse.",
    }
    output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"FINAL_GDS_PORTABILITY_AUDIT {'PASS' if not findings else 'FAIL'} blocking={len(findings)}")
    return 0 if not findings else 1


if __name__ == "__main__":
    raise SystemExit(main())

