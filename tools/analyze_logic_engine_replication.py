#!/usr/bin/env python3
import csv, math
from pathlib import Path
from groot_normalization_model import load_parameters,load_profiles,model_profile,cycles_to_ns

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports'/'groot_normalization'/'results'/'logic_engine_replication_tradeoff.csv'

def hierarchy_ms(profiles,ref):
    total=0.0;banks=int(ref['banks']);clock=float(ref['clock_mhz']);lanes=4;levels=2
    for p in profiles:
        r=model_profile(p,'hierarchical',ref)
        old=float(r['local_reduce_ns'])
        cycles=p.rows*math.ceil(p.hidden_size/(banks*lanes))+levels
        total+=(float(r['latency_ns_per_call'])-old+cycles_to_ns(cycles,clock))*p.invocations
    return total/1e6

def main():
    p=load_parameters();profiles=load_profiles();base=p['reference_point'];a=p['rtl_measurements']['logic_normalization_engine_array']
    bank_cells=p['rtl_measurements']['bank_multirow_vector_reducer_4lane']['selected_generic_cells_per_bank']*int(base['banks'])
    rows=[]
    for engines,cells in zip(a['engines'],a['generic_cells']):
        ref=dict(base,logic_pcus=engines)
        logic_ms=sum(float(model_profile(x,'logic_only',ref)['projected_latency_ns']) for x in profiles)/1e6
        hier_ms=hierarchy_ms(profiles,ref)
        rows.append({'logic_engines':engines,'logic_engine_array_generic_cells':cells,
          'hierarchical_generic_cells_proxy':bank_cells+cells,
          'paired_partials_per_cycle':engines,
          'steady_state_rows_per_cycle_proxy':round(engines/(int(base['banks'])+5),9),
          'logic_only_projected_ms':round(logic_ms,6),
          'hierarchical_4lane_multirow_projected_ms':round(hier_ms,6),
          'gpu_full_projected_ms':36.772505,
          'evidence_class':'RTL_REPLICATION_MEASURED_LATENCY_MIXED_ANALYTICAL'})
    OUT.parent.mkdir(parents=True,exist_ok=True)
    with OUT.open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
    assert all(rows[i]['logic_engine_array_generic_cells']*2==rows[i+1]['logic_engine_array_generic_cells'] for i in range(4))
    print(f'LOGIC_ENGINE_REPLICATION_TRADEOFF PASS rows={len(rows)} output={OUT}')
if __name__=='__main__':main()
