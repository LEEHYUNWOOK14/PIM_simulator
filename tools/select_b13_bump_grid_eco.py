#!/usr/bin/env python3
"""Select B13's single evidence-based bump-grid ECO after B12 is sealed."""
import hashlib, json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
B12 = ROOT / "reports/groot_normalization/quad_local_b12"
B13 = ROOT / "reports/groot_normalization/quad_local_b13"

def sha(p):
    h = hashlib.sha256()
    with p.open("rb") as f:
        for b in iter(lambda: f.read(8*1024*1024), b""): h.update(b)
    return h.hexdigest()

def main():
    out = B13 / "b13_eco_decision.json"
    md = B13 / "b13_eco_decision.md"
    if out.exists() or md.exists(): raise SystemExit("refusing to overwrite B13 decision")
    strict = json.loads((B12 / "phase6_decision_gate.json").read_text())
    analysis = json.loads((B12 / "b12_residual_congestion_analysis.json").read_text())
    log = (B12 / "physical/b12_global_route.log").read_text(errors="replace")
    t = analysis.get("totals", {})
    if not (strict.get("decision") == "BLOCKED_RESIDUAL_CONGESTION" and strict.get("authorizes") == []
            and strict.get("next_stage") is None and t.get("rrr_residual") == 104341
            and t.get("overflow_edges") == 8571 and "GRT-0118" in log):
        raise SystemExit("B12 evidence does not support B13 ECO")
    B13.mkdir(parents=True)
    payload = {
        "schema_version": 1, "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "variant": "B13", "decision": "SELECT_B13_BUMP_GRID_WIDER_ECO",
        "status": "SELECTED_PENDING_SMOKE_AND_AUTHORIZATION",
        "failure_classification": {"automatic_recovery_class": "residual_congestion",
          "subtype": "B12_signal_layer_change_increased_congestion", "not_a_stall": True},
        "selected_eco": {"single_independent_variable": "route_bump_pin_grid_columns",
          "before": 21, "after": 33,
          "reason": "B12 met2-met5 lower-bound ECO produced 104341 residual and 8571 overflow edges. Restore the proven met1-met5 signal policy and change only the bump grid column count to 33 to reduce vertical pin rows while preserving RTL, netlist, legal placement, SDC, and one-iteration policy."},
        "unchanged_contract": {"rtl": "byte-identical", "mapped_netlist": "byte-identical",
          "placement_variant": "reuse sealed B9 legal placement ODB", "sdc": "byte-identical",
          "route_signal_layers": "met1-met5", "route_clock_layers": "met1-met5",
          "global_route_invocation_limit": 1, "cugr_congestion_iterations": 1,
          "bump_pin_grid_columns": 33, "skip_large_fanout_nets": 20000},
        "observed_b12_metrics": {"rrr_residual": t.get("rrr_residual"), "overflow_edges": t.get("overflow_edges"), "overflow_tracks": t.get("overflow_tracks")},
        "functional_evidence": {"fresh_route_pin_smoke_required": True, "fresh_route_authorization_required": True, "placement_reopen_required": True},
        "inputs": {"b12_strict_gate": {"path": str(B12/"phase6_decision_gate.json"), "sha256": sha(B12/"phase6_decision_gate.json")},
          "b12_route_analysis": {"path": str(B12/"b12_residual_congestion_analysis.json"), "sha256": sha(B12/"b12_residual_congestion_analysis.json")},
          "b12_route_log": {"path": str(B12/"physical/b12_global_route.log"), "sha256": sha(B12/"physical/b12_global_route.log")}},
        "authorizes": [], "next_stage": "B13_SMOKE"
    }
    out.write_text(json.dumps(payload, indent=2)+"\n")
    md.write_text("# B13 bump-grid ECO\n\nB12 is sealed BLOCKED. B13 changes exactly one variable: bump grid columns 21 to 33, while restoring the met1-met5 policy.\n")
    print("B13_ECO_DECISION SELECTED")
if __name__ == "__main__": main()
