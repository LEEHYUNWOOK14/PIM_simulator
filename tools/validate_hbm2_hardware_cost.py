#!/usr/bin/env python3
"""Independent invariants for the HBM2 hardware-cost pipeline."""
import argparse,json,math,sys
from copy import deepcopy
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import run_hbm2_hardware_cost as hc
ROOT=Path(__file__).resolve().parents[1]

def check(name,condition,detail,checks): checks.append({"name":name,"pass":bool(condition),"detail":detail})
def main():
 ap=argparse.ArgumentParser(); ap.add_argument("--output",default="output/hbm2_hardware_cost"); a=ap.parse_args(); checks=[]
 cfg=hc.read("hardware_cost/config.json"); src=hc.read("hardware_cost/sources.json"); hc.validate_config(cfg,src); arch=hc.read(cfg["architecture_path"]); thermal=hc.read(cfg["thermal_summary_path"]); rows=hc.analyze(cfg,arch,thermal); by={r["scenario"]:r for r in rows}
 # Formula-level tests.
 yp=hc.die_yield(100,0.2,3,"poisson"); check("poisson analytic",abs(yp-math.exp(-.2))<1e-14,yp,checks)
 yn=hc.die_yield(100,0.2,3,"negative_binomial"); check("negative-binomial analytic",abs(yn-(1+.2/3)**-3)<1e-14,yn,checks)
 bw=1024/8*2.4; check("Samsung HBM2 bandwidth identity",abs(bw-307.2)<1e-12,f"{bw} GB/s",checks)
 # Structural monotonicity.
 hi=[by[f"hbm2_{n}hi_1stack"] for n in (4,8,12)]
 check("cumulative silicon monotonic",all(hi[i]["area"]["cumulative_silicon_mm2"]<hi[i+1]["area"]["cumulative_silicon_mm2"] for i in range(2)),[r["area"]["cumulative_silicon_mm2"] for r in hi],checks)
 check("bond count monotonic",[r["package"]["bond_interfaces"] for r in hi]==[4,8,12],[r["package"]["bond_interfaces"] for r in hi],checks)
 check("stack yield nonincreasing",all(hi[i]["yield"]["good_system_yield"]>hi[i+1]["yield"]["good_system_yield"] for i in range(2)),[r["yield"]["good_system_yield"] for r in hi],checks)
 check("all yields valid",all(0<r["yield"]["good_system_yield"]<=1 for r in rows),"0 < Y <= 1",checks)
 check("baseline normalized",all(abs(by[cfg["baseline"]]["integration"]["indices"][k]-1)<1e-12 for k in ("area","package","yield","energy","thermal")),by[cfg["baseline"]]["integration"]["indices"],checks)
 check("physical/logical channels separated",arch["physical_channels_per_stack"]==8 and arch["logical_channel_mapping"]["logical_channels"]==64,"8 physical, 64 logical simulator partitions",checks)
 check("capacity gate rejects 4Hi for 8GB workload",not by["hbm2_4hi_1stack"]["integration"]["feasible"] and by["hbm2_8hi_1stack"]["integration"]["feasible"],{"4Hi_GB":by["hbm2_4hi_1stack"]["power_performance"]["capacity_GB"],"required_GB":by["hbm2_4hi_1stack"]["power_performance"]["required_capacity_GB"]},checks)
 check("thermal burden monotonic across 4/8/12Hi",all(hi[i]["thermal"]["thermal_burden_ratio"]<hi[i+1]["thermal"]["thermal_burden_ratio"] for i in range(2)),[r["thermal"]["thermal_burden_ratio"] for r in hi],checks)
 check("thermal metrics physically ordered",all(r["thermal"]["predicted_peak_temperature_K"]>=r["thermal"]["ambient_temperature_K"] and abs(r["thermal"]["thermal_headroom_K"]-(r["thermal"]["temperature_limit_K"]-r["thermal"]["predicted_peak_temperature_K"]))<1e-10 for r in rows),"Tpeak >= Tambient and headroom identity",checks)
 # Full-yield limiting case.
 full=json.loads(json.dumps(cfg))
 for k in ("bond_yield_per_interface","tsv_group_yield","assembly_yield"): full["yield"][k]["value"]=1
 full["yield"]["logic_defect_density_per_cm2"]["value"]=0; full["yield"]["dram_defect_density_per_cm2"]["value"]=0
 fr=hc.analyze(full,arch,thermal); check("perfect inputs yield one",all(abs(r["yield"]["good_system_yield"]-1)<1e-12 for r in fr),[r["yield"]["good_system_yield"] for r in fr],checks)
 # Source contract and README presence.
 used={v["source_id"] for group in (cfg["area"],cfg["yield"],cfg["power_performance"]) for v in group.values() if isinstance(v,dict) and "source_id" in v}; ids={s["id"] for s in src["sources"]}
 check("all parameter sources resolve",used<=ids,sorted(used-ids),checks)
 bad=deepcopy(cfg); bad["yield"]["assembly_yield"]["value"]=1.5
 try: hc.validate_config(bad,src); rejected=False
 except ValueError: rejected=True
 check("invalid probability rejected",rejected,"assembly_yield=1.5",checks)
 readmes=["hardware_cost/README.md","hardware_cost/area/README.md","hardware_cost/package/README.md","hardware_cost/yield/README.md","hardware_cost/power_performance/README.md","hardware_cost/thermal/README.md","hardware_cost/integration/README.md"]
 check("all pipeline READMEs exist",all((ROOT/p).stat().st_size>1000 for p in readmes),readmes,checks)
 out=ROOT/a.output; required=["integrated_metrics.json","design_comparison.csv","pareto_frontier.csv","uncertainty_summary.csv","uncertainty_samples.csv","hardware_cost_report.md","parameter_provenance.json","source_traceability.md","cost_indices.png","uncertainty_performance_per_cost.png","area/area_report.md","package/package_report.md","yield/yield_report.md","power_performance/power_performance_report.md","thermal/thermal_metrics.json","thermal/thermal_report.md"]
 check("required outputs exist",all((out/p).exists() for p in required),required,checks)
 # Monte Carlo is deterministic for the configured seed.
 u1,_=hc.uncertainty(cfg,arch,thermal); u2,_=hc.uncertainty(cfg,arch,thermal); check("seeded uncertainty reproducible",u1==u2,u1,checks)
 check("rank probabilities sum to one",abs(sum(x["best_rank_probability"] for x in u1)-1)<1e-12,[x["best_rank_probability"] for x in u1],checks)
 report={"status":"PASS" if all(c["pass"] for c in checks) else "FAIL","checks":checks,"scope":"Architectural model verification; not validation against proprietary HBM2 manufacturing data."}
 vd=out/"validation"; vd.mkdir(parents=True,exist_ok=True); (vd/"validation_report.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
 lines=["# Hardware cost validation","",f"Status: **{report['status']}**","", "|Check|Pass|Detail|","|---|---|---|"]+[f"|{c['name']}|{c['pass']}|`{str(c['detail'])[:300]}`|" for c in checks]
 (vd/"validation_report.md").write_text("\n".join(lines)+"\n",encoding="utf-8"); print(json.dumps(report,indent=2)); return 0 if report["status"]=="PASS" else 1
if __name__=="__main__": raise SystemExit(main())
