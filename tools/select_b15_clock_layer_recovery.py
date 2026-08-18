#!/usr/bin/env python3
"""Select B15 by restoring the proven clock routing lower bound after B14 abort."""
import hashlib, json
from datetime import datetime, timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; B14=ROOT/"reports/groot_normalization/quad_local_b14"; B15=ROOT/"reports/groot_normalization/quad_local_b15"
def sha(p):
 h=hashlib.sha256()
 with p.open("rb") as f:
  for b in iter(lambda:f.read(8*1024*1024),b""): h.update(b)
 return h.hexdigest()
def main():
 out=B15/"b15_eco_decision.json"; md=B15/"b15_eco_decision.md"
 if out.exists() or md.exists(): raise SystemExit("refusing to overwrite B15 decision")
 m=json.loads((B14/"physical/b14_global_route_execution_report.json").read_text()); log=(B14/"physical/b14_global_route.log").read_text(errors="replace")
 if not (m.get("status")=="FAIL" and m.get("failure_class")=="tool_error" and m.get("exit_code")==134 and "rangeSearchRows" in log and m.get("protected_artifacts_preserved") is True): raise SystemExit("B14 evidence does not support B15")
 B15.mkdir(parents=True)
 p={"schema_version":1,"generated_at_utc":datetime.now(timezone.utc).isoformat(),"variant":"B15","decision":"SELECT_B15_CLOCK_LAYER_RESTORE_ECO","status":"SELECTED_PENDING_SMOKE_AND_AUTHORIZATION","failure_classification":{"automatic_recovery_class":"tool_error","subtype":"clock_met1_gridgraph_assertion","not_a_stall":True},"selected_eco":{"single_independent_variable":"route_clock_layer_bottom","before":"met1","after":"met2","reason":"B13/B14 both aborted in GridGraph::rangeSearchRows before output while using clock met1-met5. Restore the successful B9/B10 clock policy met2-met5; retain B14's columns=17 and signal met1-met5."},"unchanged_contract":{"rtl":"byte-identical","mapped_netlist":"byte-identical","placement_variant":"reuse sealed B9 legal placement ODB","sdc":"byte-identical","route_signal_layers":"met1-met5","route_clock_layers":"met2-met5","global_route_invocation_limit":1,"cugr_congestion_iterations":1,"bump_pin_grid_columns":17,"skip_large_fanout_nets":20000},"functional_evidence":{"fresh_route_pin_smoke_required":True,"fresh_route_authorization_required":True,"placement_reopen_required":True},"inputs":{"b14_execution_manifest":{"path":str(B14/"physical/b14_global_route_execution_report.json"),"sha256":sha(B14/"physical/b14_global_route_execution_report.json")},"b14_route_log":{"path":str(B14/"physical/b14_global_route.log"),"sha256":sha(B14/"physical/b14_global_route.log")}},"authorizes":[],"next_stage":"B15_SMOKE"}
 out.write_text(json.dumps(p,indent=2)+"\n"); md.write_text("# B15 clock-layer recovery ECO\n\nB14 is sealed after the GridGraph assertion. B15 restores clock met2-met5 while keeping signal met1-met5 and columns 17.\n"); print("B15_ECO_DECISION SELECTED")
if __name__=="__main__": main()
