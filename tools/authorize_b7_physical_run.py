#!/usr/bin/env python3
"""Fail-closed B7 placement authorization after the fresh phi smoke."""

from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
B2 = ROOT / "reports/groot_normalization/quad_local_b2"
B5 = ROOT / "reports/groot_normalization/quad_local_b5"
B6 = ROOT / "reports/groot_normalization/quad_local_b6"
B7 = ROOT / "reports/groot_normalization/quad_local_b7"
OUTPUT = B7 / "b7_physical_authorization.json"


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    return value if isinstance(value, dict) else {}


def command_block(text: str, command: str) -> str:
    match = re.search(rf"^{command} \\\n(.*?)(?=^puts )", text, re.MULTILINE | re.DOTALL)
    if not match:
        raise RuntimeError(f"missing {command} command block")
    return command + " \\\n" + match.group(1)


def main() -> int:
    if OUTPUT.exists():
        raise FileExistsError(f"refusing to overwrite B7 authorization: {OUTPUT}")
    decision_path = B7 / "b7_eco_decision.json"
    smoke_path = B7 / "physical/b7_smoke_execution_report.json"
    b6_manifest_path = B6 / "physical/b6_placement_execution_report.json"
    cheap_path = B5 / "cheap_gate_manifest.json"
    mapped_path = B5 / "b5_mapped_locality_audit.json"
    workload_path = ROOT / "reports/groot_normalization/results/quad_local_b5_actual_trace/accuracy_summary.json"
    b2_net = B2 / "logic_die_normalization_hbm_quad_local_b2_top_sky130.v"
    b5_net = B5 / "logic_die_normalization_hbm_quad_local_b2_top_sky130.v"
    b6_tcl_path = ROOT / "verification/groot_normalization/wbq_quad_local_b6_targeted_place.tcl"
    b7_tcl_path = ROOT / "verification/groot_normalization/wbq_quad_local_b7_phi_place.tcl"
    runner_path = ROOT / "verification/groot_normalization/run_wbq_quad_local_b7_placement.sh"
    silence_snapshot = ROOT / "tools/capture_openroad_stage_snapshot.py"
    silence_compare = ROOT / "tools/compare_openroad_stage_snapshots.py"

    decision = load(decision_path)
    smoke = load(smoke_path)
    b6 = load(b6_manifest_path)
    cheap = load(cheap_path)
    mapped = load(mapped_path)
    workload = load(workload_path)
    b6_tcl = b6_tcl_path.read_text(encoding="utf-8")
    b7_tcl = b7_tcl_path.read_text(encoding="utf-8")
    runner = runner_path.read_text(encoding="utf-8")
    gates = cheap.get("gates", [])
    checks = mapped.get("checks", [])
    profiles = workload.get("profiles", [])
    smoke_inputs_match = all(
        Path(item["path"]).is_file() and sha(Path(item["path"])) == item["sha256"]
        for item in smoke.get("inputs", {}).values()
    )
    smoke_outputs_match = all(
        Path(item["path"]).is_file() and sha(Path(item["path"])) == item["sha256"]
        for item in smoke.get("outputs", {}).values()
    )
    b6_global = command_block(b6_tcl, "global_placement")
    b7_global = command_block(b7_tcl, "global_placement")
    b6_detail = command_block(b6_tcl, "detailed_placement")
    b7_detail = command_block(b7_tcl, "detailed_placement")
    placement_attempts = (
        B7 / "physical/b7_place.log",
        B7 / "physical/b7_place_invocation.json",
        B7 / "physical/b7_placement_execution_report.json",
    )
    conditions = {
        "selected_one_variable_phi_recovery": decision.get("decision") == "SELECT_B7_LOWER_MAX_PHI_ECO"
        and decision.get("selected_eco", {}).get("single_independent_variable") == "global_placement.max_phi_coef"
        and decision.get("selected_eco", {}).get("before") == 1.05
        and decision.get("selected_eco", {}).get("after") == 1.01,
        "preauthorization_fail_closed": decision.get("authorizes") == [],
        "b6_sealed_gpl0307_before_route": b6.get("status") == "FAIL"
        and b6.get("exit_code") == 1
        and b6.get("global_route_invocations") == 0
        and b6.get("protected_artifacts_preserved") is True
        and not b6.get("authorizes"),
        "decision_pins_b6_failure": decision.get("inputs", {}).get("b6_placement_report", {}).get("sha256")
        == sha(b6_manifest_path),
        "fresh_smoke_pass": smoke.get("status") == "PASS"
        and smoke.get("authorizes") == ["B7_PHYSICAL_AUTHORIZATION"]
        and smoke.get("protected_artifacts_preserved") is True,
        "fresh_smoke_inputs_match": smoke_inputs_match,
        "fresh_smoke_outputs_match": smoke_outputs_match,
        "smoke_reopen_target_checkpoint_all_pass": all(
            smoke.get("checks", {}).get(key) == "PASS"
            for key in ("syntax_and_static_policy", "input_reopen", "target_objects", "checkpoint_write", "independent_checkpoint_reopen")
        ),
        "sealed_cheap_gate_9_of_9": cheap.get("overall_result") == "PASS"
        and len(gates) == 9
        and all(g.get("result") == "PASS" for g in gates),
        "sealed_mapped_assertions_20_of_20": mapped.get("overall_result") == "PASS"
        and len(checks) == 20
        and all(c.get("result") == "PASS" for c in checks),
        "sealed_workload_profiles_6_of_6": workload.get("overall_result") == "PASS"
        and len(profiles) == 6
        and workload.get("failed_profiles") == 0,
        "mapped_netlist_unchanged": sha(b2_net) == sha(b5_net),
        "only_global_placement_phi_changed": b6_global.replace("1.05", "1.01") == b7_global
        and b6_global.count("1.05") == 1
        and b7_global.count("1.01") == 2,
        "detailed_placement_command_unchanged": b6_detail == b7_detail,
        "anchor_specs_unchanged": re.findall(r"\{u_b2_implementation/[^\n]+\}", b6_tcl)
        == re.findall(r"\{u_b2_implementation/[^\n]+\}", b7_tcl),
        "failed_phi_removed_at_source_and_runtime_marker_present": "-max_phi_coef 1.05" not in b7_tcl
        and "min_phi=0.95 max_phi=1.01" in b7_tcl,
        "full_design_diamond_forbidden": "-use_diamond_legalizer" not in b7_tcl,
        "checkpointing_present": "WBQ_B7_RUDY_ODB" in b7_tcl and "WBQ_B7_POST_LEGALIZE_ODB" in b7_tcl,
        "runner_exact_pid_and_signal_contract": all(
            token in runner
            for token in (
                "compute_pid",
                "audit_compute_pid",
                "trap 'on_signal INT' INT",
                "trap 'on_signal TERM' TERM",
                "WBQ_B7_PLACE_MAX_PHI_COEF=1.01",
            )
        ),
        "silence_diagnostics_present": silence_snapshot.is_file() and silence_compare.is_file(),
        "no_prior_b7_placement_attempt": not any(path.exists() for path in placement_attempts),
    }
    passed = all(conditions.values())
    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "variant": "B7",
        "decision": "PASS" if passed else "BLOCKED",
        "conditions": {key: "PASS" if value else "FAIL" for key, value in conditions.items()},
        "evidence_reuse_justification": "B7 changes only GPL max_phi_coef; RTL, mapped netlist, SDC, fences, RUDY controls, anchor locks, detailed placement, and route policy remain unchanged.",
        "inputs": {
            "b7_eco_decision": {"path": str(decision_path), "sha256": sha(decision_path)},
            "b7_smoke_report": {"path": str(smoke_path), "sha256": sha(smoke_path)},
            "b6_placement_report": {"path": str(b6_manifest_path), "sha256": sha(b6_manifest_path)},
            "b5_cheap_gate_manifest": {"path": str(cheap_path), "sha256": sha(cheap_path)},
            "b5_mapped_locality_audit": {"path": str(mapped_path), "sha256": sha(mapped_path)},
            "b5_workload_accuracy": {"path": str(workload_path), "sha256": sha(workload_path)},
            "b2_mapped_netlist": {"path": str(b2_net), "sha256": sha(b2_net)},
            "b5_mapped_netlist": {"path": str(b5_net), "sha256": sha(b5_net)},
            "b6_placement_tcl": {"path": str(b6_tcl_path), "sha256": sha(b6_tcl_path)},
            "b7_placement_tcl": {"path": str(b7_tcl_path), "sha256": sha(b7_tcl_path)},
            "b7_placement_runner": {"path": str(runner_path), "sha256": sha(runner_path)},
            "silence_snapshot_tool": {"path": str(silence_snapshot), "sha256": sha(silence_snapshot)},
            "silence_compare_tool": {"path": str(silence_compare), "sha256": sha(silence_compare)},
        },
        "authorizes": ["B7_PLACEMENT"] if passed else [],
        "next_stage": "B7_PLACEMENT" if passed else None,
    }
    OUTPUT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"B7_PHYSICAL_AUTHORIZATION {payload['decision']}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
