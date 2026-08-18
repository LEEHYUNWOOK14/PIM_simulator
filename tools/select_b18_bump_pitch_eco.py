#!/usr/bin/env python3
"""Select B18 pitch ECO after B17's improved but blocked congestion."""
import hashlib,json
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; B17=ROOT/"reports/groot_normalization/quad_local_b17"; B18=ROOT/"reports/groot_normalization/quad_local_b18"
def sha(p):
 h=hashlib.sha256()
 with p.open("rb") as f:
  for b in iter(lambda:f.read(8*1024*1024),b""):h.update(b)
 return h.hexdigest()
def main():
 out=B18/"b18_eco_decision.json";md=B18/"b18_eco_decision.md"
 if out.exists() or md.exists():raise SystemExit("refusing overwrite")
 strict=json.loads((B17/"phase6_decision_gate.json").read_text());a=json.loads((B17/"b17_residual_congestion_analysis.json").read_text())
 if not(strict.get("decision")=="BLOCKED_RESIDUAL_CONGESTION" and strict.get("authorizes")==[] and a.get("totals",{}).get("rrr_residual")==481 and a.get("totals",{}).get("overflow_edges")==352):raise SystemExit("B17 evidence mismatch")
 B18.mkdir(parents=True)
 p={"schema_version":1,"generated_at_utc":datetime.now(timezone.utc).isoformat(),"variant":"B18","decision":"SELECT_B18_BUMP_PITCH_ECO","status":"SELECTED_PENDING_SMOKE_AND_AUTHORIZATION","failure_classification":{"automatic_recovery_class":"residual_congestion","subtype":"pitch_300_improved_but_not_zero","not_a_stall":True},"selected_eco":{"single_independent_variable":"route_bump_pin_pitch","before":300.0,"after":350.0,"reason":"B17 pitch=300 reduced overflow to 352 and residual to 481. Increase only pitch to 350, retaining columns=25, signal met1-met5, clock met2-met5 and all functional inputs."},"unchanged_contract":{"rtl":"byte-identical","mapped_netlist":"byte-identical","placement_variant":"reuse sealed B9 legal placement ODB","sdc":"byte-identical","route_signal_layers":"met1-met5","route_clock_layers":"met2-met5","global_route_invocation_limit":1,"cugr_congestion_iterations":1,"bump_pin_grid_columns":25,"bump_pin_pitch":350.0,"skip_large_fanout_nets":20000},"functional_evidence":{"fresh_route_pin_smoke_required":True,"fresh_route_authorization_required":True,"placement_reopen_required":True},"inputs":{"b17_strict_gate":{"path":str(B17/"phase6_decision_gate.json"),"sha256":sha(B17/"phase6_decision_gate.json")},"b17_route_analysis":{"path":str(B17/"b17_residual_congestion_analysis.json"),"sha256":sha(B17/"b17_residual_congestion_analysis.json")}},"authorizes":[],"next_stage":"B18_SMOKE"}
 out.write_text(json.dumps(p,indent=2)+"\n");md.write_text("# B18 bump-pitch ECO\n\nB17 is sealed BLOCKED; B18 changes only pitch 300 to 350.\n");print("B18_ECO_DECISION SELECTED")
if __name__=="__main__":main()
