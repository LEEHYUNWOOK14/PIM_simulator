#!/usr/bin/env python3
"""Seal B9 congestion and select one evidence-based B10 route-pin ECO."""

from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
B9 = ROOT / "reports/groot_normalization/quad_local_b9"
STRICT = B9 / "phase6_decision_gate.json"
ROUTE_ANALYSIS = B9 / "b9_residual_congestion_analysis.json"
ROUTE_LOG = B9 / "physical/b9_global_route.log"
ROUTE_TCL = ROOT / "verification/groot_normalization/wbq_quad_local_b9_global_route.tcl"
PLACEMENT = B9 / "physical/b9_placement_execution_report.json"
B10 = ROOT / "reports/groot_normalization/quad_local_b10"


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    decision_path = B10 / "b10_eco_decision.json"
    markdown_path = B10 / "b10_eco_decision.md"
    if decision_path.exists() or markdown_path.exists():
        raise FileExistsError("refusing to overwrite B10 ECO decision")
    strict = json.loads(STRICT.read_text(encoding="utf-8"))
    analysis = json.loads(ROUTE_ANALYSIS.read_text(encoding="utf-8"))
    route_log = ROUTE_LOG.read_text(encoding="utf-8", errors="replace")
    route_tcl = ROUTE_TCL.read_text(encoding="utf-8")
    totals = analysis.get("totals", {})
    hotspots = analysis.get("hotspots", [])
    central = sum(1 for item in hotspots if item.get("spatial_region") == "central_corridor")
    io_category = sum(1 for item in hotspots if "top-level I/O/other" in item.get("categories", []))
    if not (
        strict.get("decision") == "BLOCKED_RESIDUAL_CONGESTION"
        and strict.get("authorizes") == []
        and strict.get("next_stage") is None
        and totals.get("rrr_residual") == 448
        and totals.get("overflow_edges") == 346
        and central >= 300
        and io_category >= 250
        and "WBQ_B9_SINGLE_GLOBAL_ROUTE PASS" in route_log
        and re.search(r"set columns 25", route_tcl)
        and PLACEMENT.is_file()
    ):
        raise RuntimeError("B9 evidence does not support the B10 route-pin-grid ECO")

    B10.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "variant": "B10",
        "decision": "SELECT_B10_ROUTE_PIN_GRID_COLUMNS_ECO",
        "status": "SELECTED_PENDING_SMOKE_AND_AUTHORIZATION",
        "failure_classification": {
            "automatic_recovery_class": "residual_congestion",
            "subtype": "central_corridor_with_top_level_io_contribution",
            "b9_strict_gate_blocked": True,
            "not_a_stall": True,
            "resource_exhaustion": False,
        },
        "selected_eco": {
            "single_independent_variable": "route_bump_pin_grid_columns",
            "before": 25,
            "after": 29,
            "reason": "B9's direct parser found 448 residual violations and 346 overflow edges; 338 hotspots are in the central corridor and 289 include top-level I/O/other. Spread the fixed 565 bump terms across 29 rather than 25 columns while preserving RTL, netlist, legal placement, SDC, and route iteration policy.",
        },
        "unchanged_contract": {
            "rtl": "byte-identical",
            "mapped_netlist": "byte-identical",
            "placement_variant": "reuse sealed B9 legal placement ODB",
            "sdc": "byte-identical",
            "fence_geometry": "byte-identical",
            "route_signal_layers": "met1-met5",
            "route_clock_layers": "met2-met5",
            "global_route_invocation_limit": 1,
            "cugr_congestion_iterations": 1,
            "skip_large_fanout_nets": 20000,
        },
        "observed_b9_metrics": {
            "rrr_residual": totals.get("rrr_residual"),
            "overflow_edges": totals.get("overflow_edges"),
            "overflow_tracks": totals.get("overflow_tracks"),
            "central_corridor_hotspots": central,
            "top_level_io_hotspots": io_category,
        },
        "functional_evidence": {
            "fresh_route_pin_smoke_required": True,
            "fresh_route_authorization_required": True,
            "placement_reopen_required": True,
        },
        "inputs": {
            "b9_strict_gate": {"path": str(STRICT), "sha256": sha(STRICT)},
            "b9_route_analysis": {"path": str(ROUTE_ANALYSIS), "sha256": sha(ROUTE_ANALYSIS)},
            "b9_route_log": {"path": str(ROUTE_LOG), "sha256": sha(ROUTE_LOG)},
            "b9_route_tcl": {"path": str(ROUTE_TCL), "sha256": sha(ROUTE_TCL)},
            "b9_placement_report": {"path": str(PLACEMENT), "sha256": sha(PLACEMENT)},
        },
        "authorizes": [],
        "next_stage": "B10_SMOKE",
    }
    decision_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    markdown_path.write_text(
        "# B10 route pin-grid ECO\n\n"
        f"Generated: `{payload['generated_at_utc']}`\n\n"
        "B9 completed its single global-route invocation but strict Phase 6 remained blocked with residual 448 and 346 overflow edges. Direct hotspot analysis found 338 central-corridor hotspots, 289 with top-level I/O contribution. B10 changes exactly one route variable: bump-pin grid columns 25 to 29. RTL, netlist, legal placement, SDC, layers, fanout policy, and one-iteration route contract remain unchanged.\n",
        encoding="utf-8",
    )
    print(f"B10_ECO_DECISION SELECTED output={decision_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
