#!/usr/bin/env python3
"""Select B19 pitch=340 after B18 core-boundary assertion."""
import hashlib,json
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];B18=ROOT/"reports/groot_normalization/quad_local_b18";B19=ROOT/"reports/groot_normalization/quad_local_b19"
def sha(p):
 h=hashlib.sha256()
 with p.open("rb") as f:
  for b in iter(lambda:f.read(8*1024*1024),b""):h.update(b)
 return h.hexdigest()
def main():
 out=B19/"b19_eco_decision.json";md=B19/"b19_eco_decision.md"
 if out.exists() or md.exists():raise SystemExit("refusing overwrite")
 m=json.loads((B18/"physical/b18_global_route_execution_report.json").read_text());log=(B18/"physical/b18_global_route.log").read_text(errors="replace")
 if not(m.get("status")=="FAIL" and m.get("failure_class")=="tool_error" and m.get("exit_code")==134 and "rangeSearchRows" in log and m.get("protected_artifacts_preserved") is True):raise SystemExit("B18 evidence mismatch")
 B19.mkdir(parents=True)
 p={"schema_version":1,"generated_at_utc":datetime.now(timezone.utc).isoformat(),"variant":"B19","decision":"SELECT_B19_BUMP_PITCH_ECO","status":"SELECTED_PENDING_SMOKE_AND_AUTHORIZATION","failure_classification":{"automatic_recovery_class":"tool_error","subtype":"pitch_350_core_boundary_assertion","not_a_stall":True},"selected_eco":{"single_independent_variable":"route_bump_pin_pitch","before":350.0,"after":340.0,"reason":"B18 pitch=350 placed the final row outside the ~9010um core and asserted in GridGraph. Use pitch=340 (last row 8980um, inside core) while retaining columns=25 and all routing layers/contracts."},"unchanged_contract":{"rtl":"byte-identical","mapped_netlist":"byte-identical","placement_variant":"reuse sealed B9 legal placement ODB","sdc":"byte-identical","route_signal_layers":"met1-met5","route_clock_layers":"met2-met5","global_route_invocation_limit":1,"cugr_congestion_iterations":1,"bump_pin_grid_columns":25,"bump_pin_pitch":340.0,"skip_large_fanout_nets":20000},"functional_evidence":{"fresh_route_pin_smoke_required":True,"fresh_route_authorization_required":True,"placement_reopen_required":True},"inputs":{"b18_execution_manifest":{"path":str(B18/"physical/b18_global_route_execution_report.json"),"sha256":sha(B18/"physical/b18_global_route_execution_report.json")},"b18_route_log":{"path":str(B18/"physical/b18_global_route.log"),"sha256":sha(B18/"physical/b18_global_route.log")}},"authorizes":[],"next_stage":"B19_SMOKE"}
 out.write_text(json.dumps(p,indent=2)+"\n");md.write_text("# B19 bump-pitch ECO\n\nB18 is sealed after pitch=350 core-boundary assertion; B19 uses pitch=340.\n");print("B19_ECO_DECISION SELECTED")
if __name__=="__main__":main()
