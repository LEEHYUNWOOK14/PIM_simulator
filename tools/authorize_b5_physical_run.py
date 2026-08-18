#!/usr/bin/env python3
"""Issue B5 physical authorization after fresh fail-closed cheap gates."""
from __future__ import annotations
import hashlib,json
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
REPORT=ROOT/"reports/groot_normalization/quad_local_b5"
DECISION=REPORT/"b5_eco_decision.json"; CHEAP=REPORT/"cheap_gate_manifest.json"; OUTPUT=REPORT/"b5_physical_authorization.json"
B2_NET=ROOT/"reports/groot_normalization/quad_local_b2/logic_die_normalization_hbm_quad_local_b2_top_sky130.v"
B5_NET=REPORT/"logic_die_normalization_hbm_quad_local_b2_top_sky130.v"
def sha(path):
    h=hashlib.sha256()
    with Path(path).open("rb") as s:
        for c in iter(lambda:s.read(8*1024*1024),b""): h.update(c)
    return h.hexdigest()
def load(path):
    v=json.loads(Path(path).read_text()); return v if isinstance(v,dict) else {}
def main():
    decision=load(DECISION); cheap=load(CHEAP); gates=cheap.get("gates",[]); by={g.get("id"):g for g in gates}
    mapped_path=ROOT/by.get("mapped_locality_reset_audit",{}).get("artifact","missing")
    work_path=ROOT/by.get("actual_workload_accuracy",{}).get("artifact","missing")
    mapped=load(mapped_path) if mapped_path.is_file() else {}; work=load(work_path) if work_path.is_file() else {}
    checks=mapped.get("checks",[]); profiles=work.get("profiles",[])
    conditions={
      "selected_b5_diamond_legalizer_eco":decision.get("decision")=="SELECT_B5_DIAMOND_LEGALIZER_ECO",
      "precheap_fail_closed":decision.get("authorizes")==[],
      "b4_failed_before_route":decision.get("root_cause",{}).get("b4_global_route_invocations")==0,
      "cheap_gate_9_of_9":cheap.get("overall_result")=="PASS" and len(gates)==9 and all(g.get("result")=="PASS" for g in gates),
      "mapped_assertions_20_of_20":mapped.get("overall_result")=="PASS" and len(checks)==20 and sum(c.get("result")=="PASS" for c in checks)==20,
      "workload_profiles_6_of_6":work.get("overall_result")=="PASS" and work.get("passed_profiles")==6 and work.get("failed_profiles")==0 and len(profiles)==6,
      "mapped_netlist_byte_identical_to_b2":B5_NET.is_file() and sha(B5_NET)==sha(B2_NET),
      "global_route_limit_one":decision.get("global_route",{}).get("invocation_limit")==1,
      "cugr_iterations_one":decision.get("global_route",{}).get("cugr_congestion_iterations")==1,
    }
    passed=all(conditions.values())
    payload={"schema_version":1,"generated_at_utc":datetime.now(timezone.utc).isoformat(),"variant":"B5",
      "decision":"PASS" if passed else "BLOCKED_CHEAP_GATE","conditions":{k:"PASS" if v else "FAIL" for k,v in conditions.items()},
      "inputs":{"b5_eco_decision":{"path":str(DECISION),"sha256":sha(DECISION)},"cheap_gate_manifest":{"path":str(CHEAP),"sha256":sha(CHEAP)},
        "mapped_locality_audit":{"path":str(mapped_path),"sha256":sha(mapped_path) if mapped_path.is_file() else None},
        "workload_accuracy":{"path":str(work_path),"sha256":sha(work_path) if work_path.is_file() else None},
        "b2_mapped_netlist":{"path":str(B2_NET),"sha256":sha(B2_NET)},"b5_mapped_netlist":{"path":str(B5_NET),"sha256":sha(B5_NET) if B5_NET.is_file() else None}},
      "authorizes":["B5_PLACEMENT","B5_SINGLE_GLOBAL_ROUTE"] if passed else [],"next_stage":"B5_PLACEMENT" if passed else None}
    if OUTPUT.exists(): raise FileExistsError(OUTPUT)
    OUTPUT.write_text(json.dumps(payload,indent=2)+"\n")
    print(f"B5_PHYSICAL_AUTHORIZATION {payload['decision']}")
    return 0 if passed else 1
if __name__=="__main__": raise SystemExit(main())
