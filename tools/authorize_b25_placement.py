#!/usr/bin/env python3
import hashlib,json
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
REPORT=ROOT/'reports/groot_normalization/quad_local_b25'
OUT=REPORT/'b25_placement_authorization.json'
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return h.hexdigest()
def main():
 if OUT.exists():raise SystemExit('refusing overwrite')
 result=Path('/home/forstobpim/OpenROAD-flow-scripts/flow/results/sky130hd/normalization_hbm_quad_local_b25/base')
 paths={'decision':REPORT/'b25_eco_decision.json','cheap_gate':REPORT/'cheap_gate_manifest.json','mapped_netlist':REPORT/'logic_die_normalization_hbm_quad_local_b2_top_sky130.v','mapped_audit':REPORT/'b25_mapped_locality_audit.json','floorplan_odb':result/'2_floorplan.odb','floorplan_sdc':result/'2_1_floorplan.sdc','config':ROOT/'flow/designs/sky130hd/normalization_hbm_quad_local_b25/config.mk','runner':ROOT/'verification/groot_normalization/run_wbq_quad_local_b25_placement.sh','placement_audit_tcl':ROOT/'verification/groot_normalization/audit_wbq_quad_local_placement.tcl'}
 cheap=json.loads(paths['cheap_gate'].read_text()); audit=json.loads(paths['mapped_audit'].read_text())
 prior=[REPORT/'physical/b25_place_invocation.json',REPORT/'physical/b25_placement_execution_report.json',result/'3_place.odb',result/'3_place.sdc']
 checks={'cheap_gate_pass':cheap.get('overall_result')=='PASS' and 'B25_PLACEMENT' in cheap.get('authorizes',[]),'mapped_audit_pass':audit.get('overall_result')=='PASS','all_inputs_exist':all(p.is_file() and p.stat().st_size for p in paths.values()),'no_prior_attempt':not any(p.exists() for p in prior)}
 passed=all(checks.values())
 d={'schema_version':1,'generated_at_utc':datetime.now(timezone.utc).isoformat(),'variant':'B25','stage':'placement_authorization','decision':'PASS' if passed else 'BLOCKED','conditions':{k:'PASS' if v else 'FAIL' for k,v in checks.items()},'inputs':{k:{'path':str(p),'sha256':sha(p) if p.is_file() else None} for k,p in paths.items()},'authorizes':['B25_PLACEMENT'] if passed else [],'next_stage':'B25_PLACEMENT' if passed else None}
 OUT.write_text(json.dumps(d,indent=2)+'\n');print('B25_PLACEMENT_AUTHORIZATION '+d['decision']);raise SystemExit(0 if passed else 1)
if __name__=='__main__':main()
