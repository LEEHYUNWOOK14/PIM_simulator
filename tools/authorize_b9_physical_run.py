#!/usr/bin/env python3
"""Fail-closed B9 placement authorization after the fresh anchor smoke."""

from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
B2 = ROOT / "reports/groot_normalization/quad_local_b2"
B5 = ROOT / "reports/groot_normalization/quad_local_b5"
B7 = ROOT / "reports/groot_normalization/quad_local_b7"
B8 = ROOT / "reports/groot_normalization/quad_local_b8"
B9 = ROOT / "reports/groot_normalization/quad_local_b9"
OUTPUT = B9 / "b9_physical_authorization.json"


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
        raise FileExistsError(f"refusing to overwrite B9 authorization: {OUTPUT}")
    decision_path = B9 / "b9_eco_decision.json"
    smoke_path = B9 / "physical/b9_smoke_execution_report.json"
    b7_manifest_path = B7 / "physical/b7_placement_execution_report.json"
    b8_manifest_path = B8 / "physical/b8_placement_execution_report.json"
    b8_log_path = B8 / "physical/b8_place.log"
    anchor_inspection_path = B8 / "b9_anchor_candidate_inspection.log"
    cheap_path = B5 / "cheap_gate_manifest.json"
    mapped_path = B5 / "b5_mapped_locality_audit.json"
    workload_path = ROOT / "reports/groot_normalization/results/quad_local_b5_actual_trace/accuracy_summary.json"
    b2_net = B2 / "logic_die_normalization_hbm_quad_local_b2_top_sky130.v"
    b5_net = B5 / "logic_die_normalization_hbm_quad_local_b2_top_sky130.v"
    b8_tcl_path = ROOT / "verification/groot_normalization/wbq_quad_local_b8_drc_place.tcl"
    b9_tcl_path = ROOT / "verification/groot_normalization/wbq_quad_local_b9_anchor_place.tcl"
    runner_path = ROOT / "verification/groot_normalization/run_wbq_quad_local_b9_placement.sh"
    silence_snapshot = ROOT / "tools/capture_openroad_stage_snapshot.py"
    silence_compare = ROOT / "tools/compare_openroad_stage_snapshots.py"

    decision = load(decision_path)
    smoke = load(smoke_path)
    b7 = load(b7_manifest_path)
    b8 = load(b8_manifest_path)
    cheap = load(cheap_path)
    mapped = load(mapped_path)
    workload = load(workload_path)
    b8_log = b8_log_path.read_text(encoding="utf-8", errors="replace")
    anchor_inspection = anchor_inspection_path.read_text(encoding="utf-8", errors="replace")
    b8_tcl = b8_tcl_path.read_text(encoding="utf-8")
    b9_tcl = b9_tcl_path.read_text(encoding="utf-8")
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
    b8_detail = command_block(b8_tcl, "detailed_placement")
    b9_detail = command_block(b9_tcl, "detailed_placement")
    rudy_item = b7.get("checkpoints", {}).get("post_rudy", {})
    rudy_path = Path(rudy_item.get("path", ""))
    placement_attempts = (
        B9 / "physical/b9_place.log",
        B9 / "physical/b9_place_invocation.json",
        B9 / "physical/b9_placement_execution_report.json",
    )
    conditions = {
        "selected_one_variable_anchor_recovery": decision.get("decision") == "SELECT_B9_SEVEN_ADDITIONAL_ANCHORS_ECO"
        and decision.get("selected_eco", {}).get("single_independent_variable") == "locked_anchor_targets"
        and decision.get("selected_eco", {}).get("before") == 2
        and decision.get("selected_eco", {}).get("after") == 9
        and len(decision.get("selected_eco", {}).get("new_anchors", [])) == 7,
        "preauthorization_fail_closed": decision.get("authorizes") == [],
        "b8_sealed_legality_failure_before_route": b8.get("status") == "FAIL"
        and b8.get("failure_class") == "design_legality_failure"
        and b8.get("exit_code") == 1
        and b8.get("global_route_invocations") == 0
        and b8.get("protected_artifacts_preserved") is True
        and not b8.get("authorizes"),
        "b8_same_seven_offenders_at_penalty_100": "NegotiationLegalizer DRC penalty: 100." in b8_log
        and "Overlap check failed (7)" in b8_log
        and "Padding check failed (7)" in b8_log
        and "DPL-0033" in b8_log,
        "decision_pins_b8_failure": decision.get("inputs", {}).get("b8_placement_report", {}).get("sha256")
        == sha(b8_manifest_path),
        "independent_b2_anchor_measurement_pinned": "WBQ_B9_B2_SOURCE_LEGALITY violations={}" in anchor_inspection
        and "WBQ_B9_B2_ANCHOR_CANDIDATES PASS count=7" in anchor_inspection
        and decision.get("inputs", {}).get("b2_anchor_inspection", {}).get("sha256") == sha(anchor_inspection_path),
        "sealed_b7_rudy_checkpoint_matches": rudy_path.is_file()
        and sha(rudy_path) == rudy_item.get("sha256")
        and decision.get("inputs", {}).get("b7_rudy_odb", {}).get("sha256") == rudy_item.get("sha256"),
        "fresh_smoke_pass": smoke.get("status") == "PASS"
        and smoke.get("authorizes") == ["B9_PHYSICAL_AUTHORIZATION"]
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
        "detailed_placement_command_unchanged": b8_detail == b9_detail
        and b9_detail.count("-drc_penalty 100") == 1,
        "only_anchor_target_set_changed": len(re.findall(r"^  \{u_b2_implementation/", b8_tcl, re.MULTILINE)) == 2
        and len(re.findall(r"^  \{u_b2_implementation/", b9_tcl, re.MULTILINE)) == 9
        and all(
            f"{{{item['instance']} {item['origin_dbu'][0]} {item['origin_dbu'][1]} {item['orientation']} added}}" in b9_tcl
            for item in decision.get("selected_eco", {}).get("new_anchors", [])
        ),
        "sealed_global_result_reused_not_recomputed": "read_db $::env(WBQ_B7_RUDY_ODB)" in b9_tcl
        and "global_placement" not in b9_tcl,
        "runtime_marker_and_drc_policy_present": "anchor_targets=9 added_targets=7" in b9_tcl
        and "drc_penalty=100" in b9_tcl and "-drc_penalty 20" not in b9_tcl,
        "full_design_diamond_forbidden": "-use_diamond_legalizer" not in b9_tcl,
        "checkpointing_present": "WBQ_B9_POST_LEGALIZE_ODB" in b9_tcl,
        "runner_exact_pid_and_signal_contract": all(
            token in runner
            for token in (
                "compute_pid",
                "audit_compute_pid",
                "trap 'on_signal INT' INT",
                "trap 'on_signal TERM' TERM",
                "WBQ_B9_PLACE_LOCKED_ANCHOR_TARGETS=9",
                "WBQ_B9_PLACE_DRC_PENALTY=100",
            )
        ),
        "silence_diagnostics_present": silence_snapshot.is_file() and silence_compare.is_file(),
        "no_prior_b9_placement_attempt": not any(path.exists() for path in placement_attempts),
    }
    passed = all(conditions.values())
    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "variant": "B9",
        "decision": "PASS" if passed else "BLOCKED",
        "conditions": {key: "PASS" if value else "FAIL" for key, value in conditions.items()},
        "evidence_reuse_justification": "B9 keeps DRC penalty 100 and changes only the locked anchor set from two to nine using independently legal B2 origins; RTL, netlist, SDC, fences, B7 RUDY, and route policy remain unchanged.",
        "inputs": {
            "b9_eco_decision": {"path": str(decision_path), "sha256": sha(decision_path)},
            "b9_smoke_report": {"path": str(smoke_path), "sha256": sha(smoke_path)},
            "b7_placement_report": {"path": str(b7_manifest_path), "sha256": sha(b7_manifest_path)},
            "b8_placement_report": {"path": str(b8_manifest_path), "sha256": sha(b8_manifest_path)},
            "b8_placement_log": {"path": str(b8_log_path), "sha256": sha(b8_log_path)},
            "b2_anchor_inspection": {"path": str(anchor_inspection_path), "sha256": sha(anchor_inspection_path)},
            "b7_rudy_odb": {"path": str(rudy_path), "sha256": sha(rudy_path)},
            "b5_cheap_gate_manifest": {"path": str(cheap_path), "sha256": sha(cheap_path)},
            "b5_mapped_locality_audit": {"path": str(mapped_path), "sha256": sha(mapped_path)},
            "b5_workload_accuracy": {"path": str(workload_path), "sha256": sha(workload_path)},
            "b2_mapped_netlist": {"path": str(b2_net), "sha256": sha(b2_net)},
            "b5_mapped_netlist": {"path": str(b5_net), "sha256": sha(b5_net)},
            "b8_placement_tcl": {"path": str(b8_tcl_path), "sha256": sha(b8_tcl_path)},
            "b9_placement_tcl": {"path": str(b9_tcl_path), "sha256": sha(b9_tcl_path)},
            "b9_placement_runner": {"path": str(runner_path), "sha256": sha(runner_path)},
            "silence_snapshot_tool": {"path": str(silence_snapshot), "sha256": sha(silence_snapshot)},
            "silence_compare_tool": {"path": str(silence_compare), "sha256": sha(silence_compare)},
        },
        "authorizes": ["B9_PLACEMENT"] if passed else [],
        "next_stage": "B9_PLACEMENT" if passed else None,
    }
    OUTPUT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"B9_PHYSICAL_AUTHORIZATION {payload['decision']}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
