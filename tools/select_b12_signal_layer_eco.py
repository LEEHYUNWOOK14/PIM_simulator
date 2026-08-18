#!/usr/bin/env python3
"""Seal B9 congestion and select one evidence-based B12 route-pin ECO."""

from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
B11 = ROOT / "reports/groot_normalization/quad_local_b11"
STRICT = B11 / "phase6_decision_gate.json"
ROUTE_ANALYSIS = B11 / "b11_residual_congestion_analysis.json"
ROUTE_LOG = B11 / "physical/b11_global_route.log"
ROUTE_TCL = ROOT / "verification/groot_normalization/wbq_quad_local_b11_global_route.tcl"
PLACEMENT = ROOT / "reports/groot_normalization/quad_local_b9/physical/b9_placement_execution_report.json"
B12 = ROOT / "reports/groot_normalization/quad_local_b12"


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    decision_path = B12 / "b12_eco_decision.json"
    markdown_path = B12 / "b12_eco_decision.md"
    if decision_path.exists() or markdown_path.exists():
        raise FileExistsError("refusing to overwrite B12 ECO decision")
    strict = json.loads(STRICT.read_text(encoding="utf-8"))
    analysis = json.loads(ROUTE_ANALYSIS.read_text(encoding="utf-8"))
    route_log = ROUTE_LOG.read_text(encoding="utf-8", errors="replace")
    route_tcl = ROUTE_TCL.read_text(encoding="utf-8")
    totals = analysis.get("totals", {})
    overflow_layers = analysis.get("aggregates", {}).get("overflow_windows", {}).get("by_layer", {})
    if not (
        strict.get("decision") == "BLOCKED_RESIDUAL_CONGESTION"
        and strict.get("authorizes") == []
        and strict.get("next_stage") is None
        and totals.get("rrr_residual") == 485
        and totals.get("overflow_edges") == 381
        and overflow_layers.get("met1", 0) >= 220
        and "GRT-0118" in route_log
        and re.search(r"set_routing_layers -signal met1-met5", route_tcl)
        and PLACEMENT.is_file()
    ):
        raise RuntimeError("B9 evidence does not support the B12 signal-layer ECO")

    B12.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "variant": "B12",
        "decision": "SELECT_B12_SIGNAL_LAYER_BOTTOM_ECO",
        "status": "SELECTED_PENDING_SMOKE_AND_AUTHORIZATION",
        "failure_classification": {
            "automatic_recovery_class": "residual_congestion",
            "subtype": "met1_overflow_dominant_after_pin_grid_ECOs",
            "b11_strict_gate_blocked": True,
            "not_a_stall": True,
            "resource_exhaustion": False,
        },
        "selected_eco": {
            "single_independent_variable": "route_signal_layer_bottom",
            "before": "met1",
            "after": "met2",
            "reason": "B11's direct parser found 485 residual violations and 381 overflow edges, including 225 met1 overflow windows. Raise only the signal-layer lower bound from met1 to met2 while preserving RTL, netlist, legal placement, SDC, and route iteration policy.",
        },
        "unchanged_contract": {
            "rtl": "byte-identical",
            "mapped_netlist": "byte-identical",
            "placement_variant": "reuse sealed B9 legal placement ODB",
            "sdc": "byte-identical",
            "fence_geometry": "byte-identical",
            "route_signal_layers": "met2-met5",
            "route_clock_layers": "met2-met5",
            "global_route_invocation_limit": 1,
            "cugr_congestion_iterations": 1,
            "skip_large_fanout_nets": 20000,
        },
        "observed_b9_metrics": {
            "rrr_residual": totals.get("rrr_residual"),
            "overflow_edges": totals.get("overflow_edges"),
            "overflow_tracks": totals.get("overflow_tracks"),
            "overflow_by_layer": overflow_layers,
        },
        "functional_evidence": {
            "fresh_route_pin_smoke_required": True,
            "fresh_route_authorization_required": True,
            "placement_reopen_required": True,
        },
        "inputs": {
            "b11_strict_gate": {"path": str(STRICT), "sha256": sha(STRICT)},
            "b11_route_analysis": {"path": str(ROUTE_ANALYSIS), "sha256": sha(ROUTE_ANALYSIS)},
            "b11_route_log": {"path": str(ROUTE_LOG), "sha256": sha(ROUTE_LOG)},
            "b11_route_tcl": {"path": str(ROUTE_TCL), "sha256": sha(ROUTE_TCL)},
            "b9_placement_report": {"path": str(PLACEMENT), "sha256": sha(PLACEMENT)},
        },
        "authorizes": [],
        "next_stage": "B12_SMOKE",
    }
    decision_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    markdown_path.write_text(
        "# B12 route signal-layer ECO\n\n"
        f"Generated: `{payload['generated_at_utc']}`\n\n"
        "B11 completed its single global-route invocation but strict Phase 6 remained blocked with residual 485 and 381 overflow edges; met1 had 225 overflow windows. B12 changes exactly one route variable: signal routing lower bound met1 to met2. RTL, netlist, legal placement, SDC, layers, fanout policy, and one-iteration route contract remain unchanged.\n",
        encoding="utf-8",
    )
    print(f"B12_ECO_DECISION SELECTED output={decision_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
