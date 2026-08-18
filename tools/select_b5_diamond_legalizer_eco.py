#!/usr/bin/env python3
"""Seal B4 placement failure and select the minimal B5 legalizer ECO."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
B4 = ROOT / "reports/groot_normalization/quad_local_b4"
B5 = ROOT / "reports/groot_normalization/quad_local_b5"


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    manifest_path = B4 / "physical/b4_placement_execution_report.json"
    log_path = B4 / "physical/b4_place.log"
    decision_path = B4 / "b4_eco_decision.json"
    manifest = json.loads(manifest_path.read_text())
    log = log_path.read_text(errors="replace")
    if manifest.get("status") != "FAIL" or manifest.get("global_route_invocations") != 0:
        raise RuntimeError("B4 is not a sealed pre-route placement failure")
    if manifest.get("authorizes") != [] or manifest.get("next_stage") is not None:
        raise RuntimeError("B4 placement failure is not fail-closed")
    if manifest.get("protected_artifacts_preserved") is not True:
        raise RuntimeError("B4 did not preserve protected artifacts")
    required = [
        "load_slew427175 (sky130_fd_sc_hd__buf_12) overlaps TAP_TAPCELL_ROW_916_299625",
        "wire440835 (sky130_fd_sc_hd__buf_16) overlaps TAP_TAPCELL_ROW_573_187675",
        "NegotiationLegalizer did not fully converge. Violations remain: 4",
    ]
    if not all(token in log for token in required):
        raise RuntimeError("B4 exact legalization failure evidence is incomplete")
    B5.mkdir(parents=True, exist_ok=True)
    output = B5 / "b5_eco_decision.json"
    markdown = B5 / "b5_eco_decision.md"
    if output.exists() or markdown.exists():
        raise FileExistsError("refusing to overwrite B5 decision")
    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "variant": "B5",
        "decision": "SELECT_B5_DIAMOND_LEGALIZER_ECO",
        "status": "SELECTED_PENDING_CHEAP_GATES",
        "change_scope": "B5-only detailed-placement algorithm; RTL, mapped netlist, fences, RUDY policy, and route policy unchanged",
        "root_cause": {
            "stage": "B4 detailed placement legality",
            "negotiation_remaining_illegal_cells": 4,
            "actual_overlap_count": 2,
            "overlaps": [
                {"cell": "u_b2_implementation/u_pcu/u_quad_datapath/load_slew427175", "master": "sky130_fd_sc_hd__buf_12", "tapcell": "TAP_TAPCELL_ROW_916_299625"},
                {"cell": "u_b2_implementation/u_quad_local_adapter/wire440835", "master": "sky130_fd_sc_hd__buf_16", "tapcell": "TAP_TAPCELL_ROW_573_187675"},
            ],
            "b4_global_route_invocations": 0,
        },
        "selected_eco": {
            "rtl_or_constraint_change": "none",
            "placement_change": "repeat the isolated RUDY respread in B5, then use OpenROAD detailed_placement -use_diamond_legalizer",
            "exact_target": "the two tapcell overlap sites left by negotiation legalization",
            "central_corridor_effect": "preserve B4's measured RUDY respread; only legalization policy changes",
            "risk": {"function": "none expected", "timing": "moderate HPWL displacement", "area": "none", "physical": "diamond legalization may still fail or perturb congestion"},
            "mapped_assertion_and_workload_effect": "no functional change; rerun cheap 9/9, mapped 20/20, workload 6/6",
            "rollback": "discard isolated B5 artifacts; B4 remains sealed and B2 remains immutable",
            "expected_improvement_basis": "OpenROAD provides a separate region-aware diamond legalizer; B4 negotiation recovery itself recovered 30/34 cells using diamond search but failed on the final four after negotiation state was established.",
        },
        "global_route": {"invocation_limit": 1, "cugr_congestion_iterations": 1},
        "inputs": {
            "b4_eco_decision": {"path": str(decision_path), "sha256": sha(decision_path)},
            "b4_placement_report": {"path": str(manifest_path), "sha256": sha(manifest_path)},
            "b4_placement_log": {"path": str(log_path), "sha256": sha(log_path)},
        },
        "authorizes": [],
        "next_stage": "B5_IMPLEMENTATION_AND_CHEAP_GATES",
    }
    output.write_text(json.dumps(payload, indent=2) + "\n")
    markdown.write_text("\n".join([
        "# B5 minimum legalization ECO", "", f"Generated: `{payload['generated_at_utc']}`", "",
        "## Decision", "", "`SELECT_B5_DIAMOND_LEGALIZER_ECO`", "",
        "B4 is sealed before routing: negotiation legalization left four illegal cells and two actual tapcell overlaps. B5 preserves the same RUDY respread and changes only detailed placement to the region-aware diamond legalizer.", "",
        "Targets: `load_slew427175` vs `TAP_TAPCELL_ROW_916_299625`, and `wire440835` vs `TAP_TAPCELL_ROW_573_187675`.", "",
        "Current `authorizes=[]`; fresh cheap gates are required.", "",
    ]))
    print(f"B5_ECO_DECISION SELECTED output={output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
