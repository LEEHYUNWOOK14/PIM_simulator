#!/usr/bin/env python3
"""Authorize B6 using sealed B5 functional evidence and a new physical policy."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
B2 = ROOT / "reports/groot_normalization/quad_local_b2"
B5 = ROOT / "reports/groot_normalization/quad_local_b5"
B6 = ROOT / "reports/groot_normalization/quad_local_b6"
OUTPUT = B6 / "b6_physical_authorization.json"


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    return value if isinstance(value, dict) else {}


def main() -> int:
    decision_path = B6 / "b6_eco_decision.json"
    b5_manifest_path = B5 / "physical/b5_placement_execution_report.json"
    cheap_path = B5 / "cheap_gate_manifest.json"
    mapped_path = B5 / "b5_mapped_locality_audit.json"
    workload_path = ROOT / "reports/groot_normalization/results/quad_local_b5_actual_trace/accuracy_summary.json"
    b2_net = B2 / "logic_die_normalization_hbm_quad_local_b2_top_sky130.v"
    b5_net = B5 / "logic_die_normalization_hbm_quad_local_b2_top_sky130.v"
    tcl_path = ROOT / "verification/groot_normalization/wbq_quad_local_b6_targeted_place.tcl"

    decision = load(decision_path)
    b5_manifest = load(b5_manifest_path)
    cheap = load(cheap_path)
    mapped = load(mapped_path)
    workload = load(workload_path)
    tcl = tcl_path.read_text(encoding="utf-8")
    gates = cheap.get("gates", [])
    checks = mapped.get("checks", [])
    profiles = workload.get("profiles", [])
    anchors = decision.get("selected_eco", {}).get("anchors", [])
    conditions = {
        "selected_targeted_anchor_lock": decision.get("decision") == "SELECT_B6_TARGETED_ANCHOR_LOCK_ECO",
        "preauthorization_fail_closed": decision.get("authorizes") == [],
        "b5_failed_before_route": b5_manifest.get("status") == "FAIL" and b5_manifest.get("global_route_invocations") == 0,
        "b5_protected_artifacts_preserved": b5_manifest.get("protected_artifacts_preserved") is True,
        "sealed_cheap_gate_9_of_9": cheap.get("overall_result") == "PASS" and len(gates) == 9 and all(g.get("result") == "PASS" for g in gates),
        "sealed_mapped_assertions_20_of_20": mapped.get("overall_result") == "PASS" and len(checks) == 20 and all(c.get("result") == "PASS" for c in checks),
        "sealed_workload_profiles_6_of_6": workload.get("overall_result") == "PASS" and len(profiles) == 6 and workload.get("failed_profiles") == 0,
        "mapped_netlist_unchanged": sha(b2_net) == sha(b5_net),
        "exact_two_anchor_targets": len(anchors) == 2 and all(anchor.get("instance", "") in tcl for anchor in anchors),
        "full_design_diamond_forbidden": "-use_diamond_legalizer" not in tcl,
        "targeted_anchor_lock_present": "setOrigin" in tcl and "setOrient" in tcl and "setPlacementStatus LOCKED" in tcl,
        "failed_unplace_path_removed": "setPlacementStatus UNPLACED" not in tcl and "-incremental" not in tcl,
        "checkpointing_present": "WBQ_B6_RUDY_ODB" in tcl and "WBQ_B6_POST_LEGALIZE_ODB" in tcl,
        "single_route_policy": decision.get("global_route", {}).get("invocation_limit") == 1 and decision.get("global_route", {}).get("cugr_congestion_iterations") == 1,
    }
    passed = all(conditions.values())
    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "variant": "B6",
        "decision": "PASS" if passed else "BLOCKED",
        "conditions": {key: "PASS" if value else "FAIL" for key, value in conditions.items()},
        "evidence_reuse_justification": "B6 changes only detailed-placement recovery commands; RTL, mapped netlist, SDC, fence geometry, and RUDY policy are byte/command identical to the sealed B5 inputs.",
        "inputs": {
            "b6_eco_decision": {"path": str(decision_path), "sha256": sha(decision_path)},
            "b5_placement_report": {"path": str(b5_manifest_path), "sha256": sha(b5_manifest_path)},
            "b5_cheap_gate_manifest": {"path": str(cheap_path), "sha256": sha(cheap_path)},
            "b5_mapped_locality_audit": {"path": str(mapped_path), "sha256": sha(mapped_path)},
            "b5_workload_accuracy": {"path": str(workload_path), "sha256": sha(workload_path)},
            "b2_mapped_netlist": {"path": str(b2_net), "sha256": sha(b2_net)},
            "b5_mapped_netlist": {"path": str(b5_net), "sha256": sha(b5_net)},
            "b6_placement_tcl": {"path": str(tcl_path), "sha256": sha(tcl_path)},
        },
        "authorizes": ["B6_PLACEMENT", "B6_SINGLE_GLOBAL_ROUTE"] if passed else [],
        "next_stage": "B6_PLACEMENT" if passed else None,
    }
    if OUTPUT.exists():
        raise FileExistsError(OUTPUT)
    OUTPUT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"B6_PHYSICAL_AUTHORIZATION {payload['decision']}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
