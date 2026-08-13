#!/usr/bin/env python3
import csv,math
from pathlib import Path
from groot_normalization_model import load_parameters,load_profiles,model_profile,cycles_to_ns
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports'/'groot_normalization'/'results'/'logic_partial_port_sweep.csv'
def hierarchy_ms(profiles,ref):
 total=0.0;b=int(ref['banks']);clk=float(ref['clock_mhz'])
 for p in profiles:
  r=model_profile(p,'hierarchical',ref);old=float(r['local_reduce_ns'])
  cycles=p.rows*math.ceil(p.hidden_size/(b*4))+2
  total+=(float(r['latency_ns_per_call'])-old+cycles_to_ns(cycles,clk))*p.invocations
 return total/1e6
def main():
 p=load_parameters();profiles=load_profiles();base=p['reference_point'];rows=[]
 measured_cells=p['rtl_measurements']['logic_normalization_dispatcher']['generic_cells_with_dispatcher'][-1]
 bank_cells=p['rtl_measurements']['bank_multirow_vector_reducer_4lane']['selected_generic_cells_per_bank']*int(base['banks'])
 for ports in (1,2,4,8,16):
  ref=dict(base,logic_pcus=16,logic_partial_input_ports=ports);ms=hierarchy_ms(profiles,ref)
  rows.append({'logic_engines':16,'shared_partial_input_ports':ports,
   'partial_pairs_per_cycle':ports,'hierarchical_4lane_multirow_projected_ms':round(ms,6),
   'speedup_vs_one_port':None,'gpu_full_projected_ms':36.772505,
   'logic_dispatch_area_generic_cells':measured_cells if ports==1 else None,
   'hierarchical_area_generic_cells_proxy':bank_cells+measured_cells if ports==1 else None,
   'area_status':'RTL_MEASURED' if ports==1 else 'UNKNOWN_CROSSBAR_NOT_IMPLEMENTED'})
 for r in rows:r['speedup_vs_one_port']=round(rows[0]['hierarchical_4lane_multirow_projected_ms']/r['hierarchical_4lane_multirow_projected_ms'],6)
 OUT.parent.mkdir(parents=True,exist_ok=True)
 with OUT.open('w',newline='',encoding='utf-8') as f:w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
 print(f'LOGIC_PARTIAL_PORT_SWEEP PASS rows={len(rows)} output={OUT}')
if __name__=='__main__':main()
