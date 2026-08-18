#!/usr/bin/env python3
"""Run the WBQ Phase-4 collector and decision gate with durable status."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_STATUS = (
    ROOT / "reports/final_integrated_gds_execution/wbq_pipeline_status.json"
)
DEFAULT_DECISION = (
    ROOT / "reports/final_integrated_gds_execution/wbq_post_route_decision.json"
)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def absolute(value: str | Path) -> Path:
    path = Path(value)
    return path.resolve() if path.is_absolute() else (ROOT / path).resolve()


def load_status(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {
            "schema_version": 1,
            "pipeline": "WBQ_POST_ROUTE_TRANSITION",
            "stages": {},
        }
    try:
        document = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError, json.JSONDecodeError):
        document = {}
    if not isinstance(document, dict):
        document = {}
    document.setdefault("schema_version", 1)
    document.setdefault("pipeline", "WBQ_POST_ROUTE_TRANSITION")
    document.setdefault("stages", {})
    return document


def write_status(path: Path, document: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    document["updated_at_utc"] = utc_now()
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def set_stage(
    status_path: Path,
    stage: str,
    status: str,
    next_stage: str,
    *,
    command: list[str] | None = None,
    detail: str | None = None,
) -> dict[str, Any]:
    document = load_status(status_path)
    stages = document["stages"]
    entry = stages.setdefault(stage, {})
    if status == "RUNNING":
        entry["started_at_utc"] = utc_now()
        entry.pop("finished_at_utc", None)
    else:
        entry["finished_at_utc"] = utc_now()
    entry["status"] = status
    entry["next_stage"] = next_stage
    if command is not None:
        entry["command"] = command
    if detail is not None:
        entry["detail"] = detail
    document["status"] = status
    document["current_stage"] = stage
    document["next_stage"] = next_stage
    write_status(status_path, document)
    return document


def run_command(
    status_path: Path,
    stage: str,
    command: list[str],
    next_stage_on_pass: str,
) -> bool:
    set_stage(
        status_path,
        stage,
        "RUNNING",
        next_stage_on_pass,
        command=command,
    )
    completed = subprocess.run(command, cwd=ROOT, check=False)
    if completed.returncode != 0:
        set_stage(
            status_path,
            stage,
            "FAIL",
            "STOP",
            command=command,
            detail=f"exit_code={completed.returncode}",
        )
        return False
    set_stage(
        status_path,
        stage,
        "PASS",
        next_stage_on_pass,
        command=command,
        detail="exit_code=0",
    )
    return True


def mark_waiting_approval(
    status_path: Path,
    stage: str,
    reason: str,
) -> None:
    set_stage(
        status_path,
        stage,
        "WAITING_APPROVAL",
        f"RESUME_{stage}_AFTER_APPROVAL",
        detail=reason,
    )


def run_pipeline(status_path: Path, decision_path: Path) -> int:
    collector_command = [
        sys.executable,
        str(ROOT / "tools/collect_wbq_global_route_evidence.py"),
    ]
    decision_command = [
        sys.executable,
        str(ROOT / "tools/decide_wbq_post_route.py"),
        "--output",
        str(decision_path),
    ]
    if not run_command(
        status_path,
        "collect_global_route_evidence",
        collector_command,
        "decide_post_route",
    ):
        return 1
    if not run_command(
        status_path,
        "decide_post_route",
        decision_command,
        "READ_DECISION",
    ):
        return 1

    try:
        decision = json.loads(decision_path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        set_stage(
            status_path,
            "decide_post_route",
            "FAIL",
            "STOP",
            command=decision_command,
            detail=f"invalid decision output: {error}",
        )
        return 1
    selected = decision.get("decision")
    if decision.get("evidence_valid") is not True or selected not in {
        "PHASE5_HIERARCHICAL_ARCHITECTURE",
        "PHASE6_CLOCK_AND_DETAILED_ROUTE",
    }:
        set_stage(
            status_path,
            "decide_post_route",
            "FAIL",
            "STOP",
            command=decision_command,
            detail=f"decision={selected!r} evidence_valid={decision.get('evidence_valid')!r}",
        )
        return 1

    document = set_stage(
        status_path,
        "decide_post_route",
        "PASS",
        selected,
        command=decision_command,
        detail=f"decision={selected}",
    )
    document["decision"] = selected
    document["verdict"] = decision.get("verdict")
    document["decision_path"] = str(decision_path)
    write_status(status_path, document)
    print(f"WBQ_POST_ROUTE_TRANSITION PASS next_stage={selected}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--status", default=str(DEFAULT_STATUS))
    parser.add_argument("--decision", default=str(DEFAULT_DECISION))
    parser.add_argument("--waiting-approval-stage")
    parser.add_argument(
        "--approval-reason",
        default="An external operation is waiting for explicit authorization.",
    )
    args = parser.parse_args()
    status_path = absolute(args.status)
    if args.waiting_approval_stage:
        mark_waiting_approval(
            status_path,
            args.waiting_approval_stage,
            args.approval_reason,
        )
        print(
            "WBQ_POST_ROUTE_TRANSITION WAITING_APPROVAL "
            f"stage={args.waiting_approval_stage}"
        )
        return 0
    return run_pipeline(status_path, absolute(args.decision))


if __name__ == "__main__":
    raise SystemExit(main())
