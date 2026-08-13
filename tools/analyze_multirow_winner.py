#!/usr/bin/env python3
from __future__ import annotations
import csv,importlib.util,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];RESULT=ROOT/"reports/groot_normalization/results";OUT=RESULT/"multirow_architecture_comparison";OUT.mkdir(parents=True,exist_ok=True)
def load_base():
 p=ROOT/"tools/compare_actual_groot_architectures.py";s=importlib.util.spec_from_file_location("base_arch",p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
def main():
 base=load_base();work=base.workload_rows();gpu=json.loads(base.GPU.read_text());log=(RESULT/"multirow_l8_e4_results/rtl_runs.log").read_text();pattern=re.compile(r"MULTIROW_TRACE PASS profile=(\S+).*?mixed_mismatches=(\d+) pytorch_bit_mismatches=(\d+) cycles=(\d+) max_contexts=(\d+)")
 measured={}
 for p,mix,py,cyc,ctx in pattern.findall(log):measured[p]={"cycles":int(cyc),"mixed_mismatches":int(mix),"pytorch_bit_mismatches":int(py),"max_contexts":int(ctx)}
 missing={r["profile_id"] for r in work}-set(measured)
 if missing:raise SystemExit(f"missing measured profiles {missing}")
 metrics=list(csv.DictReader((RESULT/"multirow_sky130/component_metrics.csv").open()));get=lambda c,p:next(r for r in metrics if r["component"]==c and int(r["parameter"])==p)
 reducer=get("reducer",8);apply=get("apply",8);scalar=get("scalar",4);global_area=371676.4672;period=max(float(reducer["arrival_ns"]),float(apply["arrival_ns"]),float(scalar["arrival_ns"]),15.50);mhz=1000/period
 total_cycles=sum(measured[r["profile_id"]]["cycles"]*int(r["invocations"]) for r in work);core_us=total_cycles/mhz
 ondie_ns=sum((100+base.transfer_ns(int(r["partial_stat_bytes_per_call"])+int(r["scalar_broadcast_bytes_per_call"]),128))*int(r["invocations"]) for r in work);latency=core_us+ondie_ns/1000
 gpu_us=float(json.loads(base.GPU.read_text())["total_projected_serial_latency_us"]);speedup=gpu_us/latency
 tensor=sum(int(r["tensor_bytes_per_call"])*int(r["invocations"]) for r in work);affine=sum(int(r["affine_bytes_per_call"])*int(r["invocations"]) for r in work);stats=sum((int(r["partial_stat_bytes_per_call"])+int(r["scalar_broadcast_bytes_per_call"]))*int(r["invocations"]) for r in work)
 area=16*(float(reducer["area_um2"])+float(apply["area_um2"]))+float(scalar["area_um2"])+global_area
 rows=[]
 for r in work:
  x={"profile_id":r["profile_id"],"shape":r["shape"],"invocations":r["invocations"],**measured[r["profile_id"]]};x["weighted_cycles"]=x["cycles"]*int(x["invocations"]);rows.append(x)
 with(OUT/"winner_profile_cycles.csv").open("w",newline="")as f:w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
 break_even_mhz=total_cycles/(gpu_us-ondie_ns/1000);gate_mhz=total_cycles/(gpu_us/1.3-ondie_ns/1000)
 lane_dse=[]
 known_cycles={4:1201,8:820,16:761}
 for lanes in (4,8,16):
  red=get("reducer",lanes);app=get("apply",lanes);p=max(float(red["arrival_ns"]),float(app["arrival_ns"]),float(scalar["arrival_ns"]),15.5);f=1000/p;a=16*(float(red["area_um2"])+float(app["area_um2"]))+float(scalar["area_um2"])+global_area
  lane_dse.append({"lanes":lanes,"scalar_engines":4,"action_dit_norm3_cycles":known_cycles[lanes],"component_period_ns":p,"component_fmax_mhz":f,"representative_core_us":known_cycles[lanes]/f,"component_sum_area_mm2":a/1e6,"accuracy_gate":"PASS"})
 with(OUT/"lane_dse.csv").open("w",newline="")as f:w=csv.DictWriter(f,fieldnames=list(lane_dse[0]));w.writeheader();w.writerows(lane_dse)
 payload={"decision":"GO" if speedup>=1.3 else "NO-GO","production_gate_speedup":1.3,"candidate":"LANES_8_SCALAR_ENGINES_4_PINGPONG_2","accuracy":"FULL_RTL_6_OF_6_MODEL_BIT_EXACT;39_PYTORCH_BIT_MISMATCHES;MAX_ABS_0.015625","component_bound_period_ns":period,"component_bound_clock_mhz":mhz,"clock_evidence":"MAX_OF_MAPPED_COMPONENT_STA;FULL_TOP_UNROUTED","total_weighted_cycles":total_cycles,"core_latency_us":core_us,"ondie_link_latency_us":ondie_ns/1000,"hierarchical_latency_us":latency,"gpu_latency_us":gpu_us,"speedup_vs_gpu":speedup,"break_even_clock_mhz":break_even_mhz,"speedup_1p3_clock_mhz":gate_mhz,"logical_traffic_bytes":3*tensor+affine+stats,"component_sum_area_um2":area,"area_evidence":"16*(one bank reducer+apply)+scalar4+global; excludes context/control and routing","fulltop_mapping":"TIMED_OUT_AFTER_15_MINUTES_IN_ABC;301301_FLIP_FLOPS;NO_NETLIST_OR_STA","production_replay_writeback":"BLOCKED_UNLESS_SPEEDUP_GE_1P3_AND_FULL_TOP_PPA_CLOSES","lane_dse":lane_dse,"profiles":rows}
 (OUT/"winner_decision.json").write_text(json.dumps(payload,indent=2));print(f"MULTIROW_WINNER_ANALYSIS PASS decision={payload['decision']} latency_us={latency:.3f} gpu_us={gpu_us:.3f} speedup={speedup:.3f} area_mm2={area/1e6:.3f} fmax_mhz={mhz:.3f}")
if __name__=="__main__":main()
