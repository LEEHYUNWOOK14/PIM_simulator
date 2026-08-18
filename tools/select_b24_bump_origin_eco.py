#!/usr/bin/env python3
"""Select B24 Y-origin ECO after B21 improved residual congestion."""
import hashlib,json
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];B21=ROOT/"reports/groot_normalization/quad_local_b21";B24=ROOT/"reports/groot_normalization/quad_local_b24"
def sha(p):
 h=hashlib.sha256()
 with p.open("rb") as f:
  for b in iter(lambda:f.read(8*1024*1024),b""):h.update(b)
 return h.hexdigest()
def main():
 out=B24/"b24_eco_decision.json";md=B24/"b24_eco_decision.md"
 if out.exists() or md.exists():raise SystemExit("refusing overwrite")
 strict=json.loads((B21/"phase6_decision_gate.json").read_text());a=json.loads((B21/"b21_residual_congestion_analysis.json").read_text())
 if not(strict.get("decision")=="BLOCKED_RESIDUAL_CONGESTION" and strict.get("authorizes")==[] and a.get("totals",{}).get("rrr_residual")==455 and a.get("totals",{}).get("overflow_edges")==345):raise SystemExit("B21 evidence mismatch")
 B24.mkdir(parents=True)
 p={"schema_version":1,"generated_at_utc":datetime.now(timezone.utc).isoformat(),"variant":"B24","decision":"SELECT_B24_BUMP_ORIGIN_ECO","status":"SELECTED_PENDING_SMOKE_AND_AUTHORIZATION","failure_classification":{"automatic_recovery_class":"residual_congestion","subtype":"b21_best_valid_point_probe_adjacent_origin","not_a_stall":True},"selected_eco":{"single_independent_variable":"route_bump_pin_y_origin","before":1000.0,"after":1250.0,"reason":"B21 y-origin=1000 is the best valid single-variable point observed (residual 455, overflow edges 345); B22 y-origin=500 regressed to residual 480 and overflow edges 382. Probe adjacent y-origin=1250 while preserving x-origin=1500, pitch=300, columns=25, layers and all contracts."},"unchanged_contract":{"rtl":"byte-identical","mapped_netlist":"byte-identical","placement_variant":"reuse sealed B9 legal placement ODB","sdc":"byte-identical","route_signal_layers":"met1-met5","route_clock_layers":"met2-met5","global_route_invocation_limit":1,"cugr_congestion_iterations":1,"bump_pin_grid_columns":25,"bump_pin_pitch":300.0,"bump_pin_y_origin":1250.0,"skip_large_fanout_nets":20000},"functional_evidence":{"fresh_route_pin_smoke_required":True,"fresh_route_authorization_required":True,"placement_reopen_required":True},"inputs":{"b21_strict_gate":{"path":str(B21/"phase6_decision_gate.json"),"sha256":sha(B21/"phase6_decision_gate.json")},"b21_route_analysis":{"path":str(B21/"b21_residual_congestion_analysis.json"),"sha256":sha(B21/"b21_residual_congestion_analysis.json")}},"authorizes":[],"next_stage":"B24_SMOKE"}
 out.write_text(json.dumps(p,indent=2)+"\n");md.write_text("# B24 bump-origin ECO\n\nB21 is the best valid point; B24 probes Y-origin 1250 with x-origin fixed at 1500.\n");print("B24_ECO_DECISION SELECTED")
if __name__=="__main__":main()
