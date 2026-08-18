#!/usr/bin/env python3
"""Issue a hash-pinned authorization for B6's sole global-route attempt."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "reports/groot_normalization/quad_local_b6"
PHYSICAL = REPORT / "physical"
PLACEMENT = PHYSICAL / "b6_placement_execution_report.json"
DECISION = REPORT / "b6_eco_decision.json"
PHYSICAL_AUTH = REPORT / "b6_physical_authorization.json"
RUNNER = ROOT / "verification/groot_normalization/run_wbq_quad_local_b6_global_route.sh"
TCL = ROOT / "verification/groot_normalization/wbq_quad_local_b6_global_route.tcl"
PARSER = ROOT / "tools/analyze_variant_residual_congestion.py"
STRICT_GATE = ROOT / "tools/decide_b6_phase6_strict_gate.py"
SNAPSHOT_TOOL = ROOT / "tools/capture_openroad_stage_snapshot.py"
COMPARE_TOOL = ROOT / "tools/compare_openroad_stage_snapshots.py"
OUTPUT = REPORT / "b6_global_route_authorization.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def evidence(path: Path) -> dict:
    return {"path": str(path), "sha256": sha256(path)}


def main() -> int:
    if OUTPUT.exists():
        raise FileExistsError(f"refusing to overwrite B6 route authorization: {OUTPUT}")
    placement = load(PLACEMENT)
    decision = load(DECISION)
    physical_auth = load(PHYSICAL_AUTH)
    runner_text = RUNNER.read_text(encoding="utf-8")
    tcl_text = TCL.read_text(encoding="utf-8")

    odb_item = placement.get("outputs", {}).get("b6_place_odb", {})
    sdc_item = placement.get("outputs", {}).get("b6_place_sdc", {})
    odb = Path(odb_item.get("path", ""))
    sdc = Path(sdc_item.get("path", ""))
    placement_outputs_match = (
        odb.is_file()
        and sdc.is_file()
        and sha256(odb) == odb_item.get("sha256")
        and sha256(sdc) == sdc_item.get("sha256")
    )
    route_outputs = [
        PHYSICAL / "b6_global_route_invocation.json",
        PHYSICAL / "b6_global_route_execution_report.json",
        PHYSICAL / "b6_global_route.log",
        REPORT / "b6_residual_congestion_analysis.json",
        REPORT / "b6_residual_congestion_analysis.md",
    ]
    artifact_root = Path("/dev/shm/wbq_b6_phase6_10/quad_local_b6")
    route_outputs.extend(
        artifact_root / name
        for name in (
            "b6_quad_local.route_guide",
            "b6_quad_local.congestion.rpt",
            "b6_quad_local_global_route.odb",
            "b6_quad_local_global_route.sdc",
        )
    )
    conditions = {
        "placement_pass": placement.get("status") == "PASS",
        "placement_audit_pass": placement.get("placement_legality_and_fence_audit") == "PASS",
        "placement_authorizes_one_route": "B6_SINGLE_GLOBAL_ROUTE" in placement.get("authorizes", []),
        "placement_outputs_match": placement_outputs_match,
        "physical_authorization_pass": physical_auth.get("decision") == "PASS",
        "selected_b6_policy": decision.get("decision") == "SELECT_B6_TARGETED_ANCHOR_LOCK_ECO",
        "one_route_invocation": decision.get("global_route", {}).get("invocation_limit") == 1,
        "one_cugr_iteration": decision.get("global_route", {}).get("cugr_congestion_iterations") == 1,
        "b6_only_paths": "quad_local_b5" not in runner_text and "WBQ_B5" not in tcl_text,
        "runner_refuses_duplicates": "refusing duplicate" in runner_text,
        "runner_records_compute_pid": "compute_pid" in runner_text and "launcher_pid" in runner_text and "wrapper_pid" in runner_text,
        "runner_has_signal_traps": "trap 'on_signal INT' INT" in runner_text and "trap 'on_signal TERM' TERM" in runner_text,
        "direct_numeric_parser": "analyze_variant_residual_congestion.py" in runner_text,
        "compact_parser_output": "--max-windows-in-output 0" in runner_text and "--max-hotspots-in-output 500" in runner_text,
        "tcl_one_iteration_guard": "$iterations != 1" in tcl_text,
        "tcl_single_route_command": tcl_text.count("global_route \\") == 1,
        "no_prior_route_artifact": not any(path.exists() for path in route_outputs),
    }
    passed = all(conditions.values())
    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "variant": "B6",
        "stage": "single_global_route_authorization",
        "decision": "PASS" if passed else "BLOCKED",
        "conditions": {key: "PASS" if value else "FAIL" for key, value in conditions.items()},
        "inputs": {
            "placement_execution_report": evidence(PLACEMENT),
            "b6_eco_decision": evidence(DECISION),
            "b6_physical_authorization": evidence(PHYSICAL_AUTH),
            "b6_place_odb": evidence(odb) if odb.is_file() else {"path": str(odb), "sha256": None},
            "b6_place_sdc": evidence(sdc) if sdc.is_file() else {"path": str(sdc), "sha256": None},
            "route_runner": evidence(RUNNER),
            "route_tcl": evidence(TCL),
            "direct_numeric_parser": evidence(PARSER),
            "strict_phase6_gate": evidence(STRICT_GATE),
            "silence_snapshot_tool": evidence(SNAPSHOT_TOOL),
            "silence_compare_tool": evidence(COMPARE_TOOL),
        },
        "policy": {
            "global_route_invocation_limit": 1,
            "cugr_congestion_iterations": 1,
            "service": "wbq-b6-global-route.service",
            "fail_closed": True,
        },
        "authorizes": ["B6_SINGLE_GLOBAL_ROUTE"] if passed else [],
        "next_stage": "B6_SINGLE_GLOBAL_ROUTE" if passed else None,
    }
    OUTPUT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"B6_GLOBAL_ROUTE_AUTHORIZATION {payload['decision']}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
