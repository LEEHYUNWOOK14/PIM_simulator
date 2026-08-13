#!/usr/bin/env python3
import csv,math
from pathlib import Path
from groot_normalization_model import load_parameters,load_profiles,model_profile,cycles_to_ns
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports'/'groot_normalization'/'results'/'parallel_partial_tree_candidate.csv'
def main():
 p=load_parameters();profiles=load_profiles();base=p['reference_point'];banks=int(base['banks']);clk=float(base['clock_mhz'])
 rows=[]
 for engines,cells in ((8,264552),(16,431390)):
  total=0.0
  for prof in profiles:
   ref=dict(base,logic_pcus=engines,logic_partial_input_ports=1)
   r=model_profile(prof,'hierarchical',ref)
   old_local=float(r['local_reduce_ns']);old_logic=sum(float(r[k]) for k in ('global_reduce_ns','finalize_ns','rsqrt_ns'))
   local_cycles=prof.rows*math.ceil(prof.hidden_size/(banks*4))+2
   # BANKS-wide tree emits one row/cycle. >=8 scalar engines hide the 5-cycle
   # scalar latency, so only fill/drain is paid once per invocation.
   logic_cycles=prof.rows+int(math.log2(banks))+5
   per_call=float(r['latency_ns_per_call'])-old_local-old_logic+cycles_to_ns(local_cycles+logic_cycles,clk)
   total+=per_call*prof.invocations
  rows.append({'banks':banks,'scalar_engines':engines,'parallel_partial_pairs_per_cycle':banks,
    'logic_tree_top_generic_cells':cells,'bank_multirow_reducers_generic_cells':43008*banks,
    'hierarchical_generic_cells_proxy':cells+43008*banks,
    'hierarchical_projected_ms':round(total/1e6,6),'gpu_full_projected_ms':36.772505,
    'speedup_vs_gpu_full':round(36.772505/(total/1e6),6),
    'evidence_class':'RTL_TREE_THROUGHPUT_AND_GENERIC_CELLS_MIXED_ANALYTICAL'})
 OUT.parent.mkdir(parents=True,exist_ok=True)
 with OUT.open('w',newline='',encoding='utf-8') as f:w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
 print(f'PARALLEL_PARTIAL_TREE_ANALYSIS PASS rows={len(rows)} output={OUT}')
if __name__=='__main__':main()
