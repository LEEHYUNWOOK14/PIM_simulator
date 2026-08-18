#!/usr/bin/env python3
"""Select B17's single bump pitch ECO after B16 congestion is sealed."""
import hashlib,json
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; B16=ROOT/"reports/groot_normalization/quad_local_b16"; B17=ROOT/"reports/groot_normalization/quad_local_b17"
def sha(p):
 h=hashlib.sha256()
 with p.open("rb") as f:
  for b in iter(lambda:f.read(8*1024*1024),b""): h.update(b)
 return h.hexdigest()
def main():
 out=B17/"b17_eco_decision.json"; md=B17/"b17_eco_decision.md"
 if out.exists() or md.exists(): raise SystemExit("refusing overwrite")
 strict=json.loads((B16/"phase6_decision_gate.json").read_text()); a=json.loads((B16/"b16_residual_congestion_analysis.json").read_text())
 if not(strict.get("decision")=="BLOCKED_RESIDUAL_CONGESTION" and strict.get("authorizes")==[] and a.get("totals",{}).get("rrr_residual")==492 and a.get("totals",{}).get("overflow_edges")==386): raise SystemExit("B16 evidence mismatch")
 B17.mkdir(parents=True)
 p={"schema_version":1,"generated_at_utc":datetime.now(timezone.utc).isoformat(),"variant":"B17","decision":"SELECT_B17_BUMP_PITCH_ECO","status":"SELECTED_PENDING_SMOKE_AND_AUTHORIZATION","failure_classification":{"automatic_recovery_class":"residual_congestion","subtype":"bump_grid_density_after_columns_23","not_a_stall":True},"selected_eco":{"single_independent_variable":"route_bump_pin_pitch","before":250.0,"after":300.0,"reason":"B16 columns=23 retained residual 492 and 386 overflow edges, while B9-B11 show grid density is dominant. Keep the proven columns=25 and expand only pitch 250 to 300 to spread bump landings."},"unchanged_contract":{"rtl":"byte-identical","mapped_netlist":"byte-identical","placement_variant":"reuse sealed B9 legal placement ODB","sdc":"byte-identical","route_signal_layers":"met1-met5","route_clock_layers":"met2-met5","global_route_invocation_limit":1,"cugr_congestion_iterations":1,"bump_pin_grid_columns":25,"bump_pin_pitch":300.0,"skip_large_fanout_nets":20000},"functional_evidence":{"fresh_route_pin_smoke_required":True,"fresh_route_authorization_required":True,"placement_reopen_required":True},"inputs":{"b16_strict_gate":{"path":str(B16/"phase6_decision_gate.json"),"sha256":sha(B16/"phase6_decision_gate.json")},"b16_route_analysis":{"path":str(B16/"b16_residual_congestion_analysis.json"),"sha256":sha(B16/"b16_residual_congestion_analysis.json")}},"authorizes":[],"next_stage":"B17_SMOKE"}
 out.write_text(json.dumps(p,indent=2)+"\n");md.write_text("# B17 bump-pitch ECO\n\nB16 is sealed BLOCKED. B17 changes only pitch 250 to 300 with columns 25.\n");print("B17_ECO_DECISION SELECTED")
if __name__=="__main__":main()
