#!/usr/bin/env python3
"""Select B16 columns=23 after B15 columns=17 assertion."""
import hashlib,json
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; B15=ROOT/"reports/groot_normalization/quad_local_b15"; B16=ROOT/"reports/groot_normalization/quad_local_b16"
def sha(p):
 h=hashlib.sha256()
 with p.open("rb") as f:
  for b in iter(lambda:f.read(8*1024*1024),b""):h.update(b)
 return h.hexdigest()
def main():
 out=B16/"b16_eco_decision.json"; md=B16/"b16_eco_decision.md"
 if out.exists() or md.exists():raise SystemExit("refusing overwrite")
 m=json.loads((B15/"physical/b15_global_route_execution_report.json").read_text());log=(B15/"physical/b15_global_route.log").read_text(errors="replace")
 if not(m.get("status")=="FAIL" and m.get("failure_class")=="tool_error" and m.get("exit_code")==134 and "rangeSearchRows" in log and m.get("protected_artifacts_preserved") is True):raise SystemExit("B15 evidence mismatch")
 B16.mkdir(parents=True)
 p={"schema_version":1,"generated_at_utc":datetime.now(timezone.utc).isoformat(),"variant":"B16","decision":"SELECT_B16_BUMP_GRID_COLUMNS_ECO","status":"SELECTED_PENDING_SMOKE_AND_AUTHORIZATION","failure_classification":{"automatic_recovery_class":"tool_error","subtype":"gridgraph_assertion_at_columns_17","not_a_stall":True},"selected_eco":{"single_independent_variable":"route_bump_pin_grid_columns","before":17,"after":23,"reason":"B15 columns=17 deterministically asserted in GridGraph before route output. Use columns=23, within the successful 21-29 range, while retaining signal met1-met5, clock met2-met5, sealed placement, SDC, and one iteration."},"unchanged_contract":{"rtl":"byte-identical","mapped_netlist":"byte-identical","placement_variant":"reuse sealed B9 legal placement ODB","sdc":"byte-identical","route_signal_layers":"met1-met5","route_clock_layers":"met2-met5","global_route_invocation_limit":1,"cugr_congestion_iterations":1,"bump_pin_grid_columns":23,"skip_large_fanout_nets":20000},"functional_evidence":{"fresh_route_pin_smoke_required":True,"fresh_route_authorization_required":True,"placement_reopen_required":True},"inputs":{"b15_execution_manifest":{"path":str(B15/"physical/b15_global_route_execution_report.json"),"sha256":sha(B15/"physical/b15_global_route_execution_report.json")},"b15_route_log":{"path":str(B15/"physical/b15_global_route.log"),"sha256":sha(B15/"physical/b15_global_route.log")}},"authorizes":[],"next_stage":"B16_SMOKE"}
 out.write_text(json.dumps(p,indent=2)+"\n");md.write_text("# B16 bump-grid ECO\n\nB15 is sealed after columns=17 assertion; B16 uses columns=23.\n");print("B16_ECO_DECISION SELECTED")
if __name__=="__main__":main()
