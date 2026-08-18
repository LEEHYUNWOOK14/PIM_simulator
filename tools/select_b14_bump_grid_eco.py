#!/usr/bin/env python3
"""Select B14 after sealing B13's reproducible OpenROAD assertion failure."""
import hashlib, json
from datetime import datetime, timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; B13=ROOT/"reports/groot_normalization/quad_local_b13"; B14=ROOT/"reports/groot_normalization/quad_local_b14"
def sha(p):
 h=hashlib.sha256();
 with p.open("rb") as f:
  for b in iter(lambda:f.read(8*1024*1024),b""): h.update(b)
 return h.hexdigest()
def main():
 out=B14/"b14_eco_decision.json"; md=B14/"b14_eco_decision.md"
 if out.exists() or md.exists(): raise SystemExit("refusing to overwrite B14 decision")
 m=json.loads((B13/"physical/b13_global_route_execution_report.json").read_text()); log=(B13/"physical/b13_global_route.log").read_text(errors="replace")
 if not (m.get("status")=="FAIL" and m.get("failure_class")=="tool_error" and m.get("exit_code")==134 and "rangeSearchRows" in log and m.get("protected_artifacts_preserved") is True): raise SystemExit("B13 tool-error evidence does not support B14")
 B14.mkdir(parents=True)
 payload={"schema_version":1,"generated_at_utc":datetime.now(timezone.utc).isoformat(),"variant":"B14","decision":"SELECT_B14_BUMP_GRID_WIDER_ECO","status":"SELECTED_PENDING_SMOKE_AND_AUTHORIZATION","failure_classification":{"automatic_recovery_class":"tool_error","subtype":"openroad_gridgraph_range_search_assertion","not_a_stall":True},"selected_eco":{"single_independent_variable":"route_bump_pin_grid_columns","before":33,"after":17,"reason":"B13 columns=33 deterministically triggered OpenROAD GridGraph::rangeSearchRows assertion before route output. Change only the grid column count to 17 and retain met1-met5, sealed placement, SDC, and one-iteration contract."},"unchanged_contract":{"rtl":"byte-identical","mapped_netlist":"byte-identical","placement_variant":"reuse sealed B9 legal placement ODB","sdc":"byte-identical","route_signal_layers":"met1-met5","route_clock_layers":"met1-met5","global_route_invocation_limit":1,"cugr_congestion_iterations":1,"bump_pin_grid_columns":17,"skip_large_fanout_nets":20000},"functional_evidence":{"fresh_route_pin_smoke_required":True,"fresh_route_authorization_required":True,"placement_reopen_required":True},"inputs":{"b13_execution_manifest":{"path":str(B13/"physical/b13_global_route_execution_report.json"),"sha256":sha(B13/"physical/b13_global_route_execution_report.json")},"b13_route_log":{"path":str(B13/"physical/b13_global_route.log"),"sha256":sha(B13/"physical/b13_global_route.log")}},"authorizes":[],"next_stage":"B14_SMOKE"}
 out.write_text(json.dumps(payload,indent=2)+"\n"); md.write_text("# B14 bump-grid ECO\n\nB13 is sealed after its OpenROAD GridGraph assertion. B14 changes columns 33 to 17 only.\n")
 print("B14_ECO_DECISION SELECTED")
if __name__=="__main__": main()
