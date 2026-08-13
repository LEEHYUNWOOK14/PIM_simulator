#!/usr/bin/env python3
"""Recompare placements with measured C11 cycles and mapped block timing."""
from __future__ import annotations
import csv, importlib.util, json, math, re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/"reports/groot_normalization/results/actual_groot"
OUT=ROOT/"reports/groot_normalization/results/mixed_precision_c11_architecture_comparison"
STA=ROOT/"reports/groot_normalization/results/mixed_precision_sky130"

def load_base():
  path=ROOT/"tools/compare_actual_groot_architectures.py";spec=importlib.util.spec_from_file_location("base_arch",path)
  module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module

def arrival(top:str)->float:
  text=(STA/f"{top}_sta.log").read_text(encoding="utf-8",errors="replace")
  values=[float(v) for v in re.findall(r"^\s*([0-9.]+)\s+data arrival time$",text,re.M)]
  if not values:raise RuntimeError(f"missing STA arrival for {top}")
  return max(values)

def write_csv(path,rows):
  with path.open("w",newline="",encoding="utf-8")as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)

def main():
  base=load_base();rows=base.workload_rows();gpu=json.loads(base.GPU.read_text(encoding="utf-8"));OUT.mkdir(parents=True,exist_ok=True)
  blocks={name:arrival(name) for name in ("mixed_precision_bank_reducer4_interleaved","mixed_precision_global_reducer16_pipe","mixed_precision_scalar_nr2_pipe","mixed_precision_bank_apply4_pipe")}
  period=max(blocks.values());clock_mhz=1000.0/period
  for row in rows:
    row["c11_cycles_per_row"]=111+2*int(row["vectors_per_bank"])
    row["c11_cycles_per_call"]=int(row["rows"])*row["c11_cycles_per_row"]+1
  calls=sum(int(r["invocations"]) for r in rows);total_cycles=sum(r["c11_cycles_per_call"]*int(r["invocations"]) for r in rows)
  tensor_total=sum(int(r["tensor_bytes_per_call"])*int(r["invocations"]) for r in rows)
  affine_total=sum(int(r["affine_bytes_per_call"])*int(r["invocations"]) for r in rows)
  stat_total=sum((int(r["partial_stat_bytes_per_call"])+int(r["scalar_broadcast_bytes_per_call"]))*int(r["invocations"]) for r in rows)
  gpu_bytes=2*tensor_total+affine_total;pim_bytes=3*tensor_total+affine_total
  ondie_ns=sum((2*50+base.transfer_ns(int(r["partial_stat_bytes_per_call"])+int(r["scalar_broadcast_bytes_per_call"]),128))*int(r["invocations"]) for r in rows)
  offload_ns=sum((2*2500+5000+base.transfer_ns(int(r["partial_stat_bytes_per_call"])+int(r["scalar_broadcast_bytes_per_call"]),8))*int(r["invocations"]) for r in rows)
  logic=base.aggregate(rows,gpu,clock_mhz)[2]
  core_us=total_cycles/clock_mhz
  comparison=[
    {"architecture":"GPU","latency_us":float(gpu["total_projected_serial_latency_us"]),"traffic_total_bytes":gpu_bytes,"speedup_vs_gpu":1.0,"accuracy":"PYTORCH_GOLDEN","evidence":"MEASURED_CUDA_EVENTS"},
    {"architecture":"Bank-only PIM","latency_us":core_us+offload_ns/1000,"traffic_total_bytes":pim_bytes+stat_total,"speedup_vs_gpu":0.0,"accuracy":"C11_BANK_ARITHMETIC_VALIDATED;SCALAR_OFFLOAD_MODELED","evidence":"C11_MEASURED_CYCLES_STA_PLUS_ASSUMED_OFFLOAD"},
    {"architecture":"Logic-only PIM","latency_us":logic["latency_us"],"traffic_total_bytes":logic["traffic_total_bytes"],"speedup_vs_gpu":0.0,"accuracy":"UNVERIFIED","evidence":"LEGACY_MODELED_VECTOR_THROUGHPUT"},
    {"architecture":"Hierarchical PIM C11","latency_us":core_us+ondie_ns/1000,"traffic_total_bytes":pim_bytes+stat_total,"speedup_vs_gpu":0.0,"accuracy":"FULL_RTL_6_OF_6_PASS_1909248_ELEMENTS_37_PYTORCH_BIT_MISMATCHES","evidence":"ACTUAL_C11_TRACE_CYCLES_PLUS_SKY130_BLOCK_STA"},
  ]
  for r in comparison:r["speedup_vs_gpu"]=comparison[0]["latency_us"]/r["latency_us"]
  fixed_us=ondie_ns/1000;available_us=comparison[0]["latency_us"]-fixed_us;break_even_mhz=total_cycles/available_us if available_us>0 else math.inf
  decision="GO" if comparison[3]["speedup_vs_gpu"]>1 and "6_OF_6" in comparison[3]["accuracy"] else "NO-GO"
  throughput=[]
  # Projection only: overlap independent rows and reserve one scalar engine for
  # each interleaved service slot.  60 cycles is a conservative measured-FSM
  # service approximation; startup keeps the measured 111-cycle fixed tail.
  scalar_service=60
  for lanes in (4,8,16):
    for engines in (1,2,4,8,16):
      for mhz in (clock_mhz,50.0,100.0):
        projected_cycles=0
        for row in rows:
          vectors=math.ceil(int(row["hidden_size"])/(16*lanes))
          row_ii=max(vectors,math.ceil(scalar_service/engines))
          per_call=111+max(0,int(row["rows"])-1)*row_ii+2*vectors
          projected_cycles+=per_call*int(row["invocations"])
        latency_us=projected_cycles/mhz+fixed_us
        throughput.append({"lanes_per_bank":lanes,"scalar_engines":engines,"clock_mhz":mhz,"projected_cycles":projected_cycles,"latency_us":latency_us,"speedup_vs_gpu":comparison[0]["latency_us"]/latency_us,"status":"UNIMPLEMENTED_MULTIROW_PROJECTION"})
  write_csv(OUT/"architecture_comparison.csv",comparison);write_csv(OUT/"c11_workload_cycles.csv",rows)
  write_csv(OUT/"multirow_parallelism_dse.csv",throughput)
  payload={"decision":decision,"reason":"Production replay/write-back remains gated on measured end-to-end advantage.","c11_clock_mhz":clock_mhz,"c11_period_ns":period,"block_arrival_ns":blocks,"total_weighted_calls":calls,"total_c11_cycles":total_cycles,"core_latency_us":core_us,"ondie_link_latency_us":fixed_us,"break_even_clock_mhz":break_even_mhz,"comparison":comparison,"cycle_model":"rows*(111+2*vectors_per_bank)+1; fitted exactly to 1536/2048 actual RTL traces","traffic_definition":"logical payload bytes; hierarchical includes reduction read, replay/apply read, output write, affine, partial/scalar traffic"}
  payload["multirow_projection"]={"scalar_service_cycles":scalar_service,"model":"per_call=111+(rows-1)*max(vectors_per_bank,ceil(scalar_service/engines))+2*vectors_per_bank","best_candidates":sorted(throughput,key=lambda x:x["latency_us"])[:8]}
  (OUT/"comparison.json").write_text(json.dumps(payload,indent=2),encoding="utf-8")
  print(f"C11_ARCHITECTURE_COMPARISON PASS decision={decision} clock_mhz={clock_mhz:.3f} hierarchical_us={comparison[3]['latency_us']:.3f} gpu_us={comparison[0]['latency_us']:.3f} break_even_mhz={break_even_mhz:.3f}")
  return 0
if __name__=="__main__":raise SystemExit(main())
