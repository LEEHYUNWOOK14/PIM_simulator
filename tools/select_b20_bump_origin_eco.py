#!/usr/bin/env python3
"""Select B20 Y-origin ECO after B19 pitch boundary assertion."""
import hashlib,json
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];B19=ROOT/"reports/groot_normalization/quad_local_b19";B20=ROOT/"reports/groot_normalization/quad_local_b20"
def sha(p):
 h=hashlib.sha256()
 with p.open("rb") as f:
  for b in iter(lambda:f.read(8*1024*1024),b""):h.update(b)
 return h.hexdigest()
def main():
 out=B20/"b20_eco_decision.json";md=B20/"b20_eco_decision.md"
 if out.exists() or md.exists():raise SystemExit("refusing overwrite")
 m=json.loads((B19/"physical/b19_global_route_execution_report.json").read_text());log=(B19/"physical/b19_global_route.log").read_text(errors="replace")
 if not(m.get("status")=="FAIL" and m.get("failure_class")=="tool_error" and m.get("exit_code")==134 and "rangeSearchRows" in log and m.get("protected_artifacts_preserved") is True):raise SystemExit("B19 evidence mismatch")
 B20.mkdir(parents=True)
 p={"schema_version":1,"generated_at_utc":datetime.now(timezone.utc).isoformat(),"variant":"B20","decision":"SELECT_B20_BUMP_Y_ORIGIN_ECO","status":"SELECTED_PENDING_SMOKE_AND_AUTHORIZATION","failure_classification":{"automatic_recovery_class":"tool_error","subtype":"pitch_340_core_boundary_assertion","not_a_stall":True},"selected_eco":{"single_independent_variable":"route_bump_pin_y_origin","before":1500.0,"after":1000.0,"reason":"B19 pitch=340 still asserted near the core upper boundary. Keep pitch=350 and columns=25 but lower only Y-origin to 1000 so the last row is 8480um inside the ~9010um core."},"unchanged_contract":{"rtl":"byte-identical","mapped_netlist":"byte-identical","placement_variant":"reuse sealed B9 legal placement ODB","sdc":"byte-identical","route_signal_layers":"met1-met5","route_clock_layers":"met2-met5","global_route_invocation_limit":1,"cugr_congestion_iterations":1,"bump_pin_grid_columns":25,"bump_pin_pitch":350.0,"bump_pin_y_origin":1000.0,"skip_large_fanout_nets":20000},"functional_evidence":{"fresh_route_pin_smoke_required":True,"fresh_route_authorization_required":True,"placement_reopen_required":True},"inputs":{"b19_execution_manifest":{"path":str(B19/"physical/b19_global_route_execution_report.json"),"sha256":sha(B19/"physical/b19_global_route_execution_report.json")},"b19_route_log":{"path":str(B19/"physical/b19_global_route.log"),"sha256":sha(B19/"physical/b19_global_route.log")}},"authorizes":[],"next_stage":"B20_SMOKE"}
 out.write_text(json.dumps(p,indent=2)+"\n");md.write_text("# B20 bump Y-origin ECO\n\nB19 is sealed after assertion; B20 changes Y-origin 1500 to 1000 only.\n");print("B20_ECO_DECISION SELECTED")
if __name__=="__main__":main()
