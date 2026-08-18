#!/usr/bin/env python3
"""Hash-pin B7 CTS only after the strict zero-congestion gate passes."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "reports/groot_normalization/quad_local_b7"
PHASE6 = REPORT / "phase6"
GATE = REPORT / "phase6_decision_gate.json"
PLACEMENT = REPORT / "physical/b7_placement_execution_report.json"
ROUTE = REPORT / "physical/b7_global_route_execution_report.json"
PHYSICAL_AUTH = REPORT / "b7_physical_authorization.json"
CONFIG = ROOT / "flow/designs/sky130hd/normalization_hbm_quad_local_b7/config.mk"
RUNNER = ROOT / "verification/groot_normalization/run_wbq_b7_phase6_cts.sh"
AUDIT_TCL = ROOT / "verification/groot_normalization/audit_wbq_b7_phase6_cts.tcl"
SNAPSHOT_TOOL = ROOT / "tools/capture_openroad_stage_snapshot.py"
COMPARE_TOOL = ROOT / "tools/compare_openroad_stage_snapshots.py"
OUTPUT = PHASE6 / "b7_phase6_cts_authorization.json"


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
        raise FileExistsError(f"refusing to overwrite B7 CTS authorization: {OUTPUT}")
    gate = load(GATE)
    placement = load(PLACEMENT)
    route = load(ROUTE)
    physical_auth = load(PHYSICAL_AUTH)
    config_text = CONFIG.read_text(encoding="utf-8")
    runner_text = RUNNER.read_text(encoding="utf-8")
    audit_text = AUDIT_TCL.read_text(encoding="utf-8")

    odb_item = placement.get("outputs", {}).get("b7_place_odb", {})
    sdc_item = placement.get("outputs", {}).get("b7_place_sdc", {})
    odb = Path(odb_item.get("path", ""))
    sdc = Path(sdc_item.get("path", ""))
    placement_hashes_match = (
        odb.is_file() and sdc.is_file()
        and sha256(odb) == odb_item.get("sha256")
        and sha256(sdc) == sdc_item.get("sha256")
    )
    b2_net = Path(physical_auth.get("inputs", {}).get("b2_mapped_netlist", {}).get("path", ""))
    b5_net = Path(physical_auth.get("inputs", {}).get("b5_mapped_netlist", {}).get("path", ""))
    mapped_netlist_unchanged = b2_net.is_file() and b5_net.is_file() and sha256(b2_net) == sha256(b5_net)
    phase_root = Path("/dev/shm/wbq_b7_phase6_10/phase6_cts")
    work_result = Path("/dev/shm/wbq_b7_phase6_10/orfs/results/sky130hd/normalization_hbm_quad_local_b7/base")
    prior_outputs = [
        PHASE6 / name
        for name in (
            "b7_phase6_cts_preflight.json", "b7_phase6_cts_invocation.json",
            "b7_phase6_cts_execution_report.json", "b7_phase6_cts.log", "b7_phase6_cts_audit.log",
        )
    ] + [
        phase_root / "b7_phase6_cts.odb", phase_root / "b7_phase6_cts.sdc",
        work_result / "4_1_cts.odb", work_result / "4_cts.odb", work_result / "4_cts.sdc",
    ]
    conditions = {
        "strict_gate_pass": gate.get("decision") == "PASS" and "B7_PHASE6_CTS" in gate.get("authorizes", []),
        "placement_pass": placement.get("status") == "PASS",
        "placement_hashes_match": placement_hashes_match,
        "pre_cts_route_valid": route.get("status") == "PASS" and route.get("invocation_count") == 1,
        "physical_authorization_pass": physical_auth.get("decision") == "PASS",
        "mapped_netlist_unchanged": mapped_netlist_unchanged,
        "b7_design_nickname": "DESIGN_NICKNAME = normalization_hbm_quad_local_b7" in config_text,
        "b7_top_name": "DESIGN_NAME = logic_die_normalization_hbm_quad_local_b2_top" in config_text,
        "explicit_cts_policy": "do-4_1_cts" in runner_text and "repair_clock_nets" in runner_text,
        "runner_records_compute_pid": "compute_pid" in runner_text and "wrapper_pid" in runner_text,
        "runner_has_signal_traps": "trap 'on_signal INT' INT" in runner_text and "trap 'on_signal TERM' TERM" in runner_text,
        "audit_requires_clock_network": "clock_net_count < 1" in audit_text,
        "audit_requires_legal_placement": "violations ne \"\"" in audit_text,
        "no_prior_cts_artifact": not any(path.exists() for path in prior_outputs),
    }
    passed = all(conditions.values())
    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "phase": 6,
        "variant": "B7_PHASE6_CTS",
        "decision": "PASS" if passed else "BLOCKED",
        "conditions": {key: "PASS" if value else "FAIL" for key, value in conditions.items()},
        "inputs": {
            "strict_phase6_gate": evidence(GATE),
            "placement_execution_report": evidence(PLACEMENT),
            "pre_cts_route_execution_report": evidence(ROUTE),
            "physical_authorization": evidence(PHYSICAL_AUTH),
            "b7_place_odb": evidence(odb) if odb.is_file() else {"path": str(odb), "sha256": None},
            "b7_place_sdc": evidence(sdc) if sdc.is_file() else {"path": str(sdc), "sha256": None},
            "config": evidence(CONFIG),
            "runner": evidence(RUNNER),
            "audit_tcl": evidence(AUDIT_TCL),
            "silence_snapshot_tool": evidence(SNAPSHOT_TOOL),
            "silence_compare_tool": evidence(COMPARE_TOOL),
        },
        "policy": {
            "service": "wbq-b7-phase6-cts.service",
            "openroad_compute_invocation_limit": 1,
            "clock_distribution": "ORFS TritonCTS with repair_clock_nets",
            "signal_layers": "met1-met5",
            "clock_layers": "met2-met5",
            "fail_closed": True,
        },
        "authorizes": ["B7_PHASE6_CTS_COMPUTE"] if passed else [],
        "next_stage": "B7_PHASE6_CTS_COMPUTE" if passed else None,
    }
    PHASE6.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"B7_PHASE6_CTS_AUTHORIZATION {payload['decision']}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
