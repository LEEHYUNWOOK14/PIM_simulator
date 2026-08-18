#!/usr/bin/env python3
"""Select B21 pitch=300/Y-origin=1000 after B20 pitch assertion."""
import hashlib,json
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];B20=ROOT/"reports/groot_normalization/quad_local_b20";B21=ROOT/"reports/groot_normalization/quad_local_b21"
def sha(p):
 h=hashlib.sha256()
 with p.open("rb") as f:
  for b in iter(lambda:f.read(8*1024*1024),b""):h.update(b)
 return h.hexdigest()
def main():
 out=B21/"b21_eco_decision.json";md=B21/"b21_eco_decision.md"
 if out.exists() or md.exists():raise SystemExit("refusing overwrite")
 m=json.loads((B20/"physical/b20_global_route_execution_report.json").read_text());log=(B20/"physical/b20_global_route.log").read_text(errors="replace")
 if not(m.get("status")=="FAIL" and m.get("failure_class")=="tool_error" and m.get("exit_code")==134 and "rangeSearchRows" in log and m.get("protected_artifacts_preserved") is True):raise SystemExit("B20 evidence mismatch")
 B21.mkdir(parents=True)
 p={"schema_version":1,"generated_at_utc":datetime.now(timezone.utc).isoformat(),"variant":"B21","decision":"SELECT_B21_BUMP_ORIGIN_ECO","status":"SELECTED_PENDING_SMOKE_AND_AUTHORIZATION","failure_classification":{"automatic_recovery_class":"tool_error","subtype":"pitch_350_assertion_even_with_origin_shift","not_a_stall":True},"selected_eco":{"single_independent_variable":"route_bump_pin_y_origin","before":1500.0,"after":1000.0,"reason":"B20 pitch=350 asserted despite origin shift. Restore proven pitch=300 and change only Y-origin to 1000, retaining columns=25 and layers."},"unchanged_contract":{"rtl":"byte-identical","mapped_netlist":"byte-identical","placement_variant":"reuse sealed B9 legal placement ODB","sdc":"byte-identical","route_signal_layers":"met1-met5","route_clock_layers":"met2-met5","global_route_invocation_limit":1,"cugr_congestion_iterations":1,"bump_pin_grid_columns":25,"bump_pin_pitch":300.0,"bump_pin_y_origin":1000.0,"skip_large_fanout_nets":20000},"functional_evidence":{"fresh_route_pin_smoke_required":True,"fresh_route_authorization_required":True,"placement_reopen_required":True},"inputs":{"b20_execution_manifest":{"path":str(B20/"physical/b20_global_route_execution_report.json"),"sha256":sha(B20/"physical/b20_global_route_execution_report.json")},"b20_route_log":{"path":str(B20/"physical/b20_global_route.log"),"sha256":sha(B20/"physical/b20_global_route.log")}},"authorizes":[],"next_stage":"B21_SMOKE"}
 out.write_text(json.dumps(p,indent=2)+"\n");md.write_text("# B21 bump-origin ECO\n\nB20 is sealed; B21 restores pitch=300 and uses Y-origin=1000.\n");print("B21_ECO_DECISION SELECTED")
if __name__=="__main__":main()
