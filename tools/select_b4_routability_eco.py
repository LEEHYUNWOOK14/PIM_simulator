#!/usr/bin/env python3
"""Seal the B3 failure and select the fail-closed B4 placement ECO."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
B2 = ROOT / "reports/groot_normalization/quad_local_b2"
B3 = ROOT / "reports/groot_normalization/quad_local_b3"
B4 = ROOT / "reports/groot_normalization/quad_local_b4"


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    b2_analysis_path = B2 / "b2_residual_congestion_analysis.json"
    b3_analysis_path = B3 / "b3_residual_congestion_analysis.json"
    b3_gate_path = B3 / "phase6_decision_gate.json"
    b3_log_path = B3 / "physical/b3_global_route.log"
    b2 = load(b2_analysis_path)
    b3 = load(b3_analysis_path)
    gate = load(b3_gate_path)
    b2_totals = b2["totals"]
    b3_totals = b3["totals"]
    if b2_totals["rrr_residual"] != 46 or b2_totals["overflow_edges"] != 39:
        raise RuntimeError("unexpected sealed B2 congestion metrics")
    if b3_totals["rrr_residual"] != 5641 or b3_totals["overflow_edges"] != 2988:
        raise RuntimeError("unexpected B3 direct-parser metrics")
    if gate.get("decision") != "BLOCKED_RESIDUAL_CONGESTION" or gate.get("authorizes") != []:
        raise RuntimeError("B3 strict gate is not sealed fail-closed")
    log = b3_log_path.read_text(encoding="utf-8", errors="replace")
    if "Iterative RRR finished with congestion remaining (5641)" not in log:
        raise RuntimeError("B3 RRR failure token is missing")

    B4.mkdir(parents=True, exist_ok=True)
    output = B4 / "b4_eco_decision.json"
    markdown = B4 / "b4_eco_decision.md"
    if output.exists() or markdown.exists():
        raise FileExistsError("refusing to overwrite an existing B4 ECO decision")

    candidates = [
        {
            "id": "B4_RUDY_ROUTABILITY_RESPREAD",
            "selected": True,
            "rtl_or_constraint_change": (
                "B4-only placement policy: read the immutable B2 placed ODB, run one "
                "RUDY-based routability-driven global respread from existing coordinates, "
                "then legalize into a new B4 checkpoint. RTL/netlist/fence geometry are unchanged."
            ),
            "exact_target": {
                "net_families": [
                    "quad completion/context tag",
                    "scalar engine/scalar return",
                    "adapter/payload-store",
                    "Q1 bank3 reduction",
                ],
                "central_completion_bbox_um": [4878.3, 4595.4, 4995.6, 4698.9],
                "central_scalar_bbox_um": [4367.7, 4215.9, 4761.0, 4485.0],
                "q1_overflow_two_bbox_um": [7445.1, 1414.5, 7452.0, 1421.4],
            },
            "expected_central_corridor_effect": (
                "RUDY inflation acts on the measured local demand peaks before legalization, "
                "spreading entry points and pin demand without changing logical cones."
            ),
            "risk": {
                "function": "none expected; mapped netlist is byte-compared against B2",
                "timing": "moderate; HPWL can increase and must be reported after routing/CTS",
                "area": "none at netlist level; placement footprint and four fences are unchanged",
                "physical": "moderate; global respread can fail convergence or legalization",
            },
            "mapped_assertion_and_workload_effect": (
                "No functional change; nevertheless rerun cheap 9/9, mapped 20/20, workload 6/6, "
                "and comparator/locality assertions before placement."
            ),
            "rollback": "Discard only the isolated B4 directory; B2/B3 and their ODBs remain byte-identical.",
            "cheap_gates": [
                "cheap gate 9/9",
                "mapped assertion 20/20",
                "workload 6/6",
                "central writeback comparator internal sink pins == 0",
                "four-fence read-only capacity audit",
            ],
            "expected_improvement_basis": (
                "B2 already reduced the problem to 39 low-magnitude overflow edges, 31 in the central "
                "corridor. B3 proved that extra RRR without placement change thrashes (46 to 5641). "
                "Routability-driven placement is the smallest standard physical intervention that "
                "directly changes demand at all measured hotspots before the one allowed route."
            ),
        },
        {
            "id": "B4_MORE_RRR",
            "selected": False,
            "rejection": "B3 empirical evidence shows ten RRR iterations increased residual 46 to 5641.",
        },
        {
            "id": "B4_FUNCTIONAL_RTL_REDESIGN",
            "selected": False,
            "rejection": (
                "The comparator cone did not recur and mapped/workload contracts pass; a functional "
                "redesign is broader and riskier than a placement-only routability ECO."
            ),
        },
    ]
    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "variant": "B4",
        "decision": "SELECT_B4_RUDY_ROUTABILITY_RESPREAD_ECO",
        "status": "SELECTED_PENDING_CHEAP_GATES",
        "change_scope": "B4-only physical placement policy and isolated artifacts; B2/B3 remain immutable",
        "placement": {
            "input": "sealed B2 placed ODB/SDC",
            "skip_initial_place": True,
            "routability_driven": True,
            "routability_estimator": "RUDY (no global-route invocation during placement)",
            "density": 0.49,
            "fence_geometry_change": False,
        },
        "global_route": {
            "invocation_limit": 1,
            "cugr_congestion_iterations": 1,
            "reason": "Return to B2's stable single-RRR policy; B4's independent variable is placement.",
        },
        "b2_baseline": {
            "rrr_residual": b2_totals["rrr_residual"],
            "overflow_edges": b2_totals["overflow_edges"],
            "overflow_tracks": b2_totals["overflow_tracks"],
            "windows": b2_totals["windows"],
        },
        "b3_failure": {
            "rrr_residual": b3_totals["rrr_residual"],
            "overflow_edges": b3_totals["overflow_edges"],
            "overflow_tracks": b3_totals["overflow_tracks"],
            "windows": b3_totals["windows"],
            "strict_gate": gate["decision"],
            "authorizes": gate["authorizes"],
        },
        "candidates": candidates,
        "inputs": {
            "b2_direct_analysis": {"path": str(b2_analysis_path), "sha256": sha256(b2_analysis_path)},
            "b3_direct_analysis": {"path": str(b3_analysis_path), "sha256": sha256(b3_analysis_path)},
            "b3_strict_gate": {"path": str(b3_gate_path), "sha256": sha256(b3_gate_path)},
            "b3_route_log": {"path": str(b3_log_path), "sha256": sha256(b3_log_path)},
        },
        "authorizes": [],
        "next_stage": "B4_IMPLEMENTATION_AND_CHEAP_GATES",
    }
    output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    markdown.write_text(
        "\n".join(
            [
                "# B4 minimum physical ECO decision",
                "",
                f"Generated: `{payload['generated_at_utc']}`",
                "",
                "## Decision",
                "",
                "`SELECT_B4_RUDY_ROUTABILITY_RESPREAD_ECO`",
                "",
                "B3 is sealed at residual 5,641 / 2,988 overflow edges after exactly one global-route invocation. "
                "Extra RRR is therefore rejected. B4 keeps the B2 netlist and fences and changes only placement: "
                "a RUDY-based routability respread from the immutable B2 placed checkpoint, followed by legalization.",
                "",
                "## Exact targets",
                "",
                "- Central completion/context cluster: `(4878.3,4595.4)-(4995.6,4698.9)`",
                "- Central scalar-return cluster: `(4367.7,4215.9)-(4761.0,4485.0)`",
                "- Q1 bank3 reduction overflow=2: `(7445.1,1414.5)-(7452.0,1421.4)`",
                "",
                "## Gates",
                "",
                "B4 placement remains unauthorized until fresh cheap 9/9, mapped 20/20, workload 6/6, "
                "and comparator/locality checks all pass. B4 global route is limited to one invocation with one RRR iteration.",
                "",
                "Current `authorizes=[]`.",
                "",
            ]
        ),
        encoding="utf-8",
    )
    print(f"B4_ECO_DECISION SELECTED output={output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
