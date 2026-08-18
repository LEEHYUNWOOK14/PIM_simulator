#!/usr/bin/env python3
"""Seal the pathological B5 diamond run and select a two-cell B6 anchor ECO."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
B5 = ROOT / "reports/groot_normalization/quad_local_b5"
B6 = ROOT / "reports/groot_normalization/quad_local_b6"


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    manifest_path = B5 / "physical/b5_placement_execution_report.json"
    log_path = B5 / "physical/b5_place.log"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    log = log_path.read_text(encoding="utf-8", errors="replace")
    if manifest.get("status") != "FAIL" or manifest.get("global_route_invocations") != 0:
        raise RuntimeError("B5 is not a sealed pre-route placement failure")
    if manifest.get("protected_artifacts_preserved") is not True:
        raise RuntimeError("B5 protected artifacts were not preserved")
    required = [
        "WBQ_B5_RUDY_GLOBAL_PLACEMENT PASS",
        "[INFO DPL-1101] Legalizing using diamond search.",
        "Command terminated by signal 15",
        "WBQ_B5_PLACE_EXIT_CODE=143",
    ]
    if not all(token in log for token in required):
        raise RuntimeError("B5 runtime diagnosis evidence is incomplete")

    B6.mkdir(parents=True, exist_ok=True)
    output = B6 / "b6_eco_decision.json"
    markdown = B6 / "b6_eco_decision.md"
    if output.exists() or markdown.exists():
        raise FileExistsError("refusing to overwrite B6 decision")

    grouped_cells = 3_676_196
    swaps_per_pass = grouped_cells * 100
    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "variant": "B6",
        "decision": "SELECT_B6_TARGETED_ANCHOR_LOCK_ECO",
        "status": "SELECTED_PENDING_AUTHORIZATION",
        "change_scope": "physical recovery only; RTL, mapped netlist, constraints, fences, RUDY policy, and route policy unchanged",
        "root_cause": {
            "stage": "B5 diamond detailed placement",
            "confirmed_active_stack": [
                "dpl::Opendp::anneal(dpl::Group*)",
                "dpl::Opendp::placeGroups()",
                "dpl::Opendp::diamondDPL()",
            ],
            "grouped_cells": grouped_cells,
            "anneal_attempts_per_pass": swaps_per_pass,
            "maximum_anneal_passes": 3,
            "maximum_anneal_attempts": swaps_per_pass * 3,
            "effective_parallelism": "one active legalizer thread; worker pools idle",
            "observed_wall_seconds": 41_243,
            "observed_result": "no placement ODB or SDC produced",
        },
        "selected_eco": {
            "algorithm": "lock the two B4 offenders at their sealed, legal B2 anchors before RUDY and use the negotiation legalizer",
            "anchors": [
                {
                    "instance": "u_b2_implementation/u_pcu/u_quad_datapath/load_slew427175",
                    "origin_dbu": [6_347_540, 2_535_040],
                    "orientation": "MX",
                },
                {
                    "instance": "u_b2_implementation/u_quad_local_adapter/wire440835",
                    "origin_dbu": [4_686_940, 1_468_800],
                    "orientation": "R180",
                },
            ],
            "reason": "B4 proved that all remaining violations are these two movable buffers colliding with fixed tapcells; preserving each buffer's legal B2 anchor prevents that failure mode while allowing surrounding cells to legalize normally",
            "diamond_full_design": "forbidden",
            "primary_max_displacement_um": [1000, 1000],
            "primary_site_window": 100,
            "primary_row_window": 20,
            "checkpoint_policy": "persist post-RUDY and post-legalization ODBs in the isolated B6 artifact root",
        },
        "functional_evidence": {
            "policy": "reuse sealed B5 cheap 9/9 because B6 changes no RTL, mapped netlist, SDC, or fence geometry",
            "fresh_physical_authorization_required": True,
        },
        "global_route": {"invocation_limit": 1, "cugr_congestion_iterations": 1},
        "inputs": {
            "b5_placement_report": {"path": str(manifest_path), "sha256": sha(manifest_path)},
            "b5_placement_log": {"path": str(log_path), "sha256": sha(log_path)},
        },
        "authorizes": [],
        "next_stage": "B6_PHYSICAL_AUTHORIZATION",
    }
    output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    markdown.write_text(
        "\n".join(
            [
                "# B6 targeted anchor-lock ECO",
                "",
                f"Generated: `{payload['generated_at_utc']}`",
                "",
                "## Root cause",
                "",
                "The live B5 stack was inside `dpl::Opendp::anneal()`. OpenROAD's legacy diamond path performs 100 random swaps per grouped cell; 3,676,196 grouped cells therefore request 367,619,600 attempts per pass on one active thread (up to three passes).",
                "",
                "## Recovery",
                "",
                "B6 forbids full-design diamond legalization. Before the deterministic RUDY respread it locks only the two known tap-overlap buffers at their sealed, legal B2 origins and orientations. RUDY and the bounded negotiation legalizer then place all surrounding movable cells around those anchors. Post-RUDY and post-legalization checkpoints are retained.",
                "",
                "B5 ended before routing and all protected A/B/B2 artifacts remain unchanged.",
                "",
            ]
        ),
        encoding="utf-8",
    )
    print(f"B6_ECO_DECISION SELECTED output={output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
