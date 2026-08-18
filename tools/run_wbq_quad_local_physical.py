#!/usr/bin/env python3
"""Durable B-only placement then global-route state machine."""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
B2 = os.environ.get("WBQ_B2", "0") == "1"
REPORT = ROOT / (
    "reports/groot_normalization/quad_local_b2"
    if B2
    else "reports/groot_normalization/quad_local_ab"
)
VARIANT = (
    "logic_die_normalization_hbm_quad_local_b2_top"
    if B2
    else "logic_die_normalization_hbm_quad_local_ab_top"
)
STATUS = REPORT / "physical_pipeline_status.json"
CURRENT_STAGE = "startup"


def update(state: str, stage: str, message: str, next_stage: str | None) -> None:
    payload = {
        "schema_version": 1,
        "variant": VARIANT,
        "state": state,
        "stage": stage,
        "message": message,
        "next_stage": next_stage,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    temporary = STATUS.with_suffix(".tmp")
    temporary.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    temporary.replace(STATUS)


def run(stage: str, script: str, next_stage: str | None) -> None:
    global CURRENT_STAGE
    CURRENT_STAGE = stage
    update("running", stage, f"executing {script}", next_stage)
    result = subprocess.run(["bash", script], cwd=ROOT)
    if result.returncode:
        update("fail", stage, f"{script} exited {result.returncode}", None)
        raise RuntimeError(f"{script} failed with exit code {result.returncode}")
    update("pass", stage, f"{script} passed", next_stage)


def interrupted(signum: int, _frame: object) -> None:
    update(
        "fail",
        CURRENT_STAGE,
        f"interrupted by signal {signal.Signals(signum).name}",
        "rerun_after_diagnosis",
    )
    raise SystemExit(128 + signum)


def main() -> int:
    global CURRENT_STAGE
    REPORT.mkdir(parents=True, exist_ok=True)
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    CURRENT_STAGE = "cheap_gate"
    gate_path = REPORT / "cheap_gate_manifest.json"
    gate = json.loads(gate_path.read_text(encoding="utf-8"))
    if gate.get("overall_result") != "PASS":
        update("fail", "cheap_gate", "cheap gate manifest is not PASS", None)
        return 2
    update("pass", "cheap_gate", "all nine cheap gates passed", "placement")
    run("placement", "verification/groot_normalization/run_wbq_quad_local_place.sh", "global_route")
    run("global_route", "verification/groot_normalization/run_wbq_quad_local_global_route.sh", None)
    update(
        "pass",
        "complete",
        f"{'B2' if B2 else 'B'} placement and global route completed; Phase 6 remains blocked",
        None,
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"WBQ_QUAD_LOCAL_PHYSICAL FAIL: {error}", file=sys.stderr)
        raise
