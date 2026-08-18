#!/usr/bin/env python3
"""Issue B25's hash-pinned authorization for exactly one global route."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "reports/groot_normalization/quad_local_b25"
PHYSICAL = REPORT / "physical"
RESULT = Path("/home/forstobpim/OpenROAD-flow-scripts/flow/results/sky130hd/normalization_hbm_quad_local_b25/base")
PLACEMENT = PHYSICAL / "b25_placement_execution_report.json"
SMOKE = PHYSICAL / "b25_route_pin_smoke_execution_report.json"
DECISION = REPORT / "b25_eco_decision.json"
CHEAP = REPORT / "cheap_gate_manifest.json"
RUNNER = ROOT / "verification/groot_normalization/run_wbq_quad_local_b25_global_route.sh"
TCL = ROOT / "verification/groot_normalization/wbq_quad_local_b25_global_route.tcl"
PARSER = ROOT / "tools/analyze_variant_residual_congestion.py"
STRICT_GATE = ROOT / "tools/decide_b25_phase6_strict_gate.py"
SNAPSHOT = ROOT / "tools/capture_openroad_stage_snapshot.py"
COMPARE = ROOT / "tools/compare_openroad_stage_snapshots.py"
MONITOR = ROOT / "tools/monitor_openroad_service.py"
OUTPUT = REPORT / "b25_global_route_authorization.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
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
        raise FileExistsError(f"refusing to overwrite B25 route authorization: {OUTPUT}")
    required = [PLACEMENT, SMOKE, DECISION, CHEAP, RUNNER, TCL, PARSER, STRICT_GATE, SNAPSHOT, COMPARE, MONITOR]
    if not all(path.is_file() and path.stat().st_size for path in required):
        raise FileNotFoundError("one or more B25 route-authorization inputs are missing")
    placement = load(PLACEMENT)
    smoke = load(SMOKE)
    decision = load(DECISION)
    cheap = load(CHEAP)
    runner_text = RUNNER.read_text(encoding="utf-8")
    tcl_text = TCL.read_text(encoding="utf-8")
    odb_item = placement.get("outputs", {}).get("b25_place_odb", {})
    sdc_item = placement.get("outputs", {}).get("b25_place_sdc", {})
    odb = Path(odb_item.get("path", ""))
    sdc = Path(sdc_item.get("path", ""))
    smoke_item = smoke.get("outputs", {}).get("smoke_odb", {})
    smoke_odb = Path(smoke_item.get("path", ""))
    output_paths = [
        PHYSICAL / "b25_global_route_invocation.json",
        PHYSICAL / "b25_global_route_execution_report.json",
        PHYSICAL / "b25_global_route.log",
        REPORT / "b25_residual_congestion_analysis.json",
        REPORT / "b25_residual_congestion_analysis.md",
    ]
    artifact_root = Path("/dev/shm/wbq_b25_phase6_10/quad_local_b25_route")
    output_paths.extend(
        artifact_root / name
        for name in (
            "b25_quad_local.route_guide",
            "b25_quad_local.congestion.rpt",
            "b25_quad_local_global_route.odb",
            "b25_quad_local_global_route.sdc",
        )
    )
    conditions = {
        "placement_pass": placement.get("status") == "PASS"
        and placement.get("placement_legality_and_fence_audit") == "PASS"
        and placement.get("authorizes") == ["B25_SINGLE_GLOBAL_ROUTE"],
        "placement_outputs_match": odb.is_file()
        and sdc.is_file()
        and sha256(odb) == odb_item.get("sha256")
        and sha256(sdc) == sdc_item.get("sha256"),
        "route_pin_smoke_pass": smoke.get("status") == "PASS"
        and smoke.get("authorizes") == ["B25_GLOBAL_ROUTE_AUTHORIZATION"],
        "route_pin_smoke_output_matches": smoke_odb.is_file()
        and sha256(smoke_odb) == smoke_item.get("sha256"),
        "cheap_gate_pass": cheap.get("overall_result") == "PASS"
        and "B25_SINGLE_GLOBAL_ROUTE" in cheap.get("authorizes", []),
        "structural_eco_selected": decision.get("decision") == "SELECT_B25_AGGREGATED_COMPLETION_DESCRIPTOR_ECO"
        and decision.get("selected_eco", {}).get("single_independent_variable") == "completion_descriptor_transport_structure",
        "b21_route_policy_locked": all(
            marker in tcl_text
            for marker in ("set columns 25", "set pitch 300.0", "set x0 1500.0", "set y0 1000.0")
        ),
        "one_cugr_iteration": "$iterations != 1" in tcl_text and tcl_text.count("global_route \\") == 1,
        "runner_refuses_duplicates": "refusing duplicate" in runner_text,
        "runner_records_exact_pids": all(marker in runner_text for marker in ("wrapper_pid", "compute_pid", "launcher_pid")),
        "runner_has_fail_closed_traps": all(marker in runner_text for marker in ("trap 'on_signal INT' INT", "trap 'on_signal TERM' TERM", "write_fail_closed_manifest")),
        "direct_numeric_parser": "analyze_variant_residual_congestion.py" in runner_text,
        "no_prior_route_artifact": not any(path.exists() for path in output_paths),
    }
    passed = all(conditions.values())
    inputs = {
        "placement_execution_report": evidence(PLACEMENT),
        "route_pin_smoke_report": evidence(SMOKE),
        "b25_eco_decision": evidence(DECISION),
        "b25_cheap_gate": evidence(CHEAP),
        "b25_place_odb": evidence(odb) if odb.is_file() else {"path": str(odb), "sha256": None},
        "b25_place_sdc": evidence(sdc) if sdc.is_file() else {"path": str(sdc), "sha256": None},
        "route_pin_smoke_odb": evidence(smoke_odb) if smoke_odb.is_file() else {"path": str(smoke_odb), "sha256": None},
        "route_runner": evidence(RUNNER),
        "route_tcl": evidence(TCL),
        "direct_numeric_parser": evidence(PARSER),
        "strict_phase6_gate": evidence(STRICT_GATE),
        "silence_snapshot_tool": evidence(SNAPSHOT),
        "silence_compare_tool": evidence(COMPARE),
        "heartbeat_monitor": evidence(MONITOR),
    }
    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "variant": "B25",
        "stage": "single_global_route_authorization",
        "decision": "PASS" if passed else "BLOCKED",
        "conditions": {name: "PASS" if value else "FAIL" for name, value in conditions.items()},
        "inputs": inputs,
        "policy": {
            "global_route_invocation_limit": 1,
            "cugr_congestion_iterations": 1,
            "route_grid": {"columns": 25, "pitch_um": 300.0, "x0_um": 1500.0, "y0_um": 1000.0},
            "service": "wbq-b25-global-route.service",
            "fail_closed": True,
        },
        "authorizes": ["B25_SINGLE_GLOBAL_ROUTE"] if passed else [],
        "next_stage": "B25_SINGLE_GLOBAL_ROUTE" if passed else None,
    }
    OUTPUT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"B25_GLOBAL_ROUTE_AUTHORIZATION {payload['decision']}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
