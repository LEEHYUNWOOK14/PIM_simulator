#!/usr/bin/env python3
import csv
from pathlib import Path
from groot_normalization_model import load_parameters,load_profiles
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports'/'groot_normalization'/'results'/'bank_skew_sensitivity.csv'
def main():
 p=load_parameters();profiles=load_profiles();clock=float(p['reference_point']['clock_mhz'])
 base_ms=32.832634;gpu_ms=36.772505
 projected_rows=sum(x.rows*x.invocations for x in profiles)
 rows=[]
 for skew in (0,1,2,4,8,16):
  penalty_ms=projected_rows*skew*1000.0/clock/1e6
  total=base_ms+penalty_ms
  rows.append({'average_max_bank_skew_cycles_per_row':skew,'projected_rows':projected_rows,
    'skew_penalty_ms':round(penalty_ms,6),'hierarchical_projected_ms':round(total,6),
    'gpu_full_projected_ms':gpu_ms,'hierarchical_speedup_vs_gpu':round(gpu_ms/total,6),
    'winner':'hierarchical' if total<gpu_ms else 'gpu_full',
    'evidence_class':'ASSUMED_SKEW_SENSITIVITY_ON_RTL_BARRIER'})
 OUT.parent.mkdir(parents=True,exist_ok=True)
 with OUT.open('w',newline='',encoding='utf-8') as f:w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
 print(f'BANK_SKEW_SENSITIVITY PASS rows={len(rows)} projected_rows={projected_rows} output={OUT}')
if __name__=='__main__':main()
