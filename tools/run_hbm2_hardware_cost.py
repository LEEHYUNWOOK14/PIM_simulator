#!/usr/bin/env python3
"""Source-traceable HBM2 architectural hardware-cost analysis."""
from __future__ import annotations
import argparse, csv, json, math
from copy import deepcopy
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
def read(path): return json.loads((ROOT/path).read_text(encoding="utf-8"))
def val(x): return float(x["value"])

def validate_config(cfg,sources):
    ids={s["id"] for s in sources["sources"]}; errors=[]
    def walk(x,path=""):
      if isinstance(x,dict):
       if "value" in x:
        for k in ("unit","classification","source_id","confidence"):
         if k not in x: errors.append(f"{path}: missing {k}")
        if x.get("source_id") not in ids: errors.append(f"{path}: unknown source_id {x.get('source_id')}")
        try:
          number=float(x["value"])
          if x.get("unit")=="probability" and not 0<=number<=1: errors.append(f"{path}: probability outside [0,1]")
          if number<0: errors.append(f"{path}: negative physical input")
          if "uncertainty" in x:
            u=x["uncertainty"]
            if not float(u["min"])<=number<=float(u["max"]): errors.append(f"{path}: nominal outside uncertainty range")
        except (TypeError,ValueError,KeyError): errors.append(f"{path}: malformed numeric value/range")
       for k,v in x.items(): walk(v,f"{path}.{k}" if path else k)
      elif isinstance(x,list):
       for i,v in enumerate(x): walk(v,f"{path}[{i}]")
    walk(cfg)
    weights=cfg["integration_weights"]
    if abs(sum(weights.values())-1)>1e-12: errors.append("integration_weights must sum to 1")
    if abs(sum(cfg["package"]["weights"].values())-1)>1e-12: errors.append("package.weights must sum to 1")
    if cfg["baseline"] not in {s["name"] for s in cfg["scenarios"]}: errors.append("baseline scenario missing")
    for i,s in enumerate(cfg["scenarios"]):
      if int(s["stacks"])<1 or int(s["dies"])<1: errors.append(f"scenarios[{i}]: stacks and dies must be positive")
    if errors: raise ValueError("invalid hardware cost config:\n"+"\n".join(errors))

def area_metrics(cfg,arch,s):
    a=cfg["area"]; logic=val(a["logic_die_area_mm2"])+(val(a["pim_logic_area_mm2"]) if s["pim_enabled"] else 0); dram=val(a["dram_die_area_mm2"])
    tsv=int(arch["physical_channels_per_stack"]*arch["layout"]["tsv_groups_per_channel"]*arch["layout"]["tsvs_per_group"]*s["dies"]*s["stacks"])
    koz=tsv*math.pi*(val(a["tsv_koz_diameter_um"])/2)**2/1e6
    cumulative=s["stacks"]*(logic+s["dies"]*dram); footprint=s["stacks"]*max(logic,dram)
    usable=s["stacks"]*max(0,logic-val(a["phy_reserved_area_mm2"])-koz/s["stacks"])
    return {"footprint_area_mm2":footprint,"cumulative_silicon_mm2":cumulative,"logic_area_mm2":logic*s["stacks"],"dram_silicon_mm2":dram*s["dies"]*s["stacks"],"pim_added_area_mm2":val(a["pim_logic_area_mm2"])*s["stacks"] if s["pim_enabled"] else 0,"pim_area_overhead_ratio":val(a["pim_logic_area_mm2"])/val(a["logic_die_area_mm2"]) if s["pim_enabled"] else 0,"tsv_koz_upper_bound_mm2":koz,"usable_logic_area_mm2":usable,"tsv_count_model":tsv}

def package_physical(cfg,arch,s):
    geo=arch["geometry_um"]; layout=arch["layout"]; interfaces=s["dies"]*s["stacks"]
    bumps=layout["microbump_columns"]*layout["microbump_rows"]*interfaces
    tsv=arch["physical_channels_per_stack"]*layout["tsv_groups_per_channel"]*layout["tsvs_per_group"]*s["dies"]*s["stacks"]
    interposer=geo["interposer_width"]["value"]*geo["interposer_height"]["value"]*1e-6*s["stacks"]
    package=geo["package_width"]["value"]*geo["package_height"]["value"]*1e-6*s["stacks"]
    height=(geo["logic_die_thickness"]["value"]+s["dies"]*(geo["dram_die_thickness"]["value"]+geo["die_gap"]["value"]))*1e-3
    routing=s["stacks"]*arch["physical_channels_per_stack"]*arch["channel_width_bits"]*val(cfg["package"]["routing_demand_factor"])
    return {"microbump_count_model":bumps,"signal_tsv_count_model":tsv,"bond_interfaces":interfaces,"interposer_area_mm2":interposer,"package_footprint_mm2":package,"stack_height_without_lid_mm":height,"routing_demand_bit_equivalent":routing}

def package_metric(cfg,p,base):
    w=cfg["package"]["weights"]
    terms={"interposer":p["interposer_area_mm2"]/base["interposer_area_mm2"],"microbump":p["microbump_count_model"]/base["microbump_count_model"],"tsv":p["signal_tsv_count_model"]/base["signal_tsv_count_model"],"bond":p["bond_interfaces"]/base["bond_interfaces"],"routing":p["routing_demand_bit_equivalent"]/base["routing_demand_bit_equivalent"]}
    return sum(w[k]*terms[k] for k in w),terms

def die_yield(area_mm2,d0,alpha,model):
    x=d0*area_mm2/100.0
    return math.exp(-x) if model=="poisson" else (1+x/alpha)**(-alpha)

def yield_metrics(cfg,area,s):
    y=cfg["yield"]; model=cfg["models"]["die_yield"]; alpha=val(y["clustering_alpha"])
    yl=die_yield(area["logic_area_mm2"]/s["stacks"],val(y["logic_defect_density_per_cm2"]),alpha,model)
    yd=die_yield(val(cfg["area"]["dram_die_area_mm2"]),val(y["dram_defect_density_per_cm2"]),alpha,model)
    bond=val(y["bond_yield_per_interface"]); tsv=val(y["tsv_group_yield"]); assembly=val(y["assembly_yield"])
    per_stack=yl*(yd**s["dies"])*(bond**s["dies"])*tsv*assembly
    system=per_stack**s["stacks"]
    return {"logic_die_yield":yl,"dram_die_yield":yd,"bond_chain_yield":bond**(s["dies"]*s["stacks"]),"tsv_group_yield":tsv**s["stacks"],"assembly_yield":assembly**s["stacks"],"good_system_yield":system,"expected_attempts_per_good_system":1/system,"yield_model":model,"kgd_assumption":"individual die yield retained explicitly; no perfect KGD claim"}

def pp_metrics(cfg,s,thermal):
    p=cfg["power_performance"]; theoretical=s["stacks"]*val(p["bus_width_bits"])/8*val(p["pin_rate_Gbps"])
    achieved=theoretical*val(p["bandwidth_utilization"]); speed=val(p["pim_speedup"]) if s["pim_enabled"] else 1.0
    useful=achieved*speed; power=val(p["baseline_power_W"])*s["stacks"]*(0.5+0.5*s["dies"]/8)*(val(p["pim_power_multiplier"]) if s["pim_enabled"] else 1)
    energy_per_gb=power/useful if useful>0 else math.inf; energy_bit_pj=power/(achieved*8e9)*1e12 if achieved>0 else math.inf
    ambient=300.; ref_peak=float(thermal.get("peak_temperature_K",309.1426)); ref_power=max(float(thermal.get("input_power_W",4)),1e-12); predicted=ambient+(ref_peak-ambient)*(power/ref_power)*(0.65+0.35*s["dies"]/8)
    capacity=s["stacks"]*s["dies"]*val(p["dram_die_capacity_GB"]); capacity_ok=capacity>=val(p["workload_required_capacity_GB"])
    return {"capacity_GB":capacity,"required_capacity_GB":val(p["workload_required_capacity_GB"]),"capacity_feasible":capacity_ok,"theoretical_bandwidth_GBs":theoretical,"achieved_bandwidth_GBs":achieved,"bandwidth_utilization":val(p["bandwidth_utilization"]),"normalized_useful_performance":useful,"estimated_power_W":power,"energy_per_GB_work_J":energy_per_gb,"io_energy_per_transferred_bit_pJ":energy_bit_pj,"pim_speedup_assumption":speed,"predicted_peak_temperature_K":predicted,"thermal_limit_K":val(p["thermal_limit_K"]),"thermal_feasible":predicted<=val(p["thermal_limit_K"]),"power_evidence":"architectural/synthetic unless replaced by activity or measurement"}

def analyze(cfg,arch,thermal):
    base_s=next(s for s in cfg["scenarios"] if s["name"]==cfg["baseline"]); base_pkg=package_physical(cfg,arch,base_s)
    rows=[]
    for s in cfg["scenarios"]:
      ar=area_metrics(cfg,arch,s); pkg=package_physical(cfg,arch,s); pm,terms=package_metric(cfg,pkg,base_pkg); yi=yield_metrics(cfg,ar,s); pp=pp_metrics(cfg,s,thermal)
      rows.append({"scenario":s["name"],"settings":s,"area":ar,"package":{**pkg,"package_complexity_index":pm,"normalized_terms":terms},"yield":yi,"power_performance":pp})
    base=next(r for r in rows if r["scenario"]==cfg["baseline"]); w=cfg["integration_weights"]
    for r in rows:
      indices={"area":r["area"]["cumulative_silicon_mm2"]/base["area"]["cumulative_silicon_mm2"],"package":r["package"]["package_complexity_index"],"yield":r["yield"]["expected_attempts_per_good_system"]/base["yield"]["expected_attempts_per_good_system"],"energy":r["power_performance"]["energy_per_GB_work_J"]/base["power_performance"]["energy_per_GB_work_J"]}
      combined=math.exp(sum(w[k]*math.log(max(indices[k],1e-15)) for k in w)); perf=r["power_performance"]["normalized_useful_performance"]/base["power_performance"]["normalized_useful_performance"]
      feasible=r["power_performance"]["thermal_feasible"] and r["power_performance"]["capacity_feasible"]
      r["integration"]={"indices":indices,"combined_cost_index":combined,"normalized_performance":perf,"performance_per_cost":perf/combined,"feasible":feasible,"feasibility":{"thermal":r["power_performance"]["thermal_feasible"],"capacity":r["power_performance"]["capacity_feasible"]}}
    # Pareto: minimize all costs and maximize performance.
    for a in rows:
      dominated=not a["integration"]["feasible"]
      for b in rows:
       if a is b: continue
       if not b["integration"]["feasible"]: continue
       ac=a["integration"]; bc=b["integration"]
       costs_ok=all(bc["indices"][k]<=ac["indices"][k]+1e-12 for k in ac["indices"]); perf_ok=bc["normalized_performance"]>=ac["normalized_performance"]-1e-12
       strict=any(bc["indices"][k]<ac["indices"][k]-1e-12 for k in ac["indices"]) or bc["normalized_performance"]>ac["normalized_performance"]+1e-12
       if costs_ok and perf_ok and strict: dominated=True; break
      a["integration"]["pareto_optimal"]=not dominated
    return rows

def sampled_config(cfg,rng):
    x=deepcopy(cfg)
    def walk(v):
      if isinstance(v,dict):
       if "value" in v and "uncertainty" in v:
        u=v["uncertainty"]; v["value"]=float(rng.uniform(u["min"],u["max"]))
       else:
        for q in v.values(): walk(q)
      elif isinstance(v,list):
       for q in v: walk(q)
    walk(x); return x

def uncertainty(cfg,arch,thermal):
    rng=np.random.default_rng(cfg["models"]["random_seed"]); data={s["name"]:[] for s in cfg["scenarios"]}; samples=[]; wins={k:0 for k in data}
    for sample in range(cfg["models"]["monte_carlo_samples"]):
      result=analyze(sampled_config(cfg,rng),arch,thermal); eligible=[r for r in result if r["integration"]["feasible"]]; best=max(eligible,key=lambda r:r["integration"]["performance_per_cost"])["scenario"]; wins[best]+=1
      for r in result:
        score=r["integration"]["performance_per_cost"]; data[r["scenario"]].append(score); samples.append({"sample":sample,"scenario":r["scenario"],"performance_per_cost":score,"combined_cost_index":r["integration"]["combined_cost_index"],"normalized_performance":r["integration"]["normalized_performance"]})
    summary=[{"scenario":k,"p05":float(np.quantile(v,.05)),"p50":float(np.quantile(v,.5)),"p95":float(np.quantile(v,.95)),"best_rank_probability":wins[k]/len(v),"samples":len(v)} for k,v in data.items()]
    return summary,samples

def flatten_rows(rows):
    out=[]
    for r in rows:
      i=r["integration"]; out.append({"scenario":r["scenario"],"area_index":i["indices"]["area"],"package_index":i["indices"]["package"],"yield_cost_index":i["indices"]["yield"],"energy_index":i["indices"]["energy"],"combined_cost_index":i["combined_cost_index"],"normalized_performance":i["normalized_performance"],"performance_per_cost":i["performance_per_cost"],"thermal_feasible":i["feasibility"]["thermal"],"capacity_feasible":i["feasibility"]["capacity"],"overall_feasible":i["feasible"],"pareto_optimal":i["pareto_optimal"]})
    return out

def write_csv(path,rows):
    with open(path,"w",newline="",encoding="utf-8") as f: w=csv.DictWriter(f,fieldnames=rows[0]); w.writeheader(); w.writerows(rows)

def write_pipeline_reports(out,cfg,rows,sources):
    titles={"area":"Area","package":"Package","yield":"Yield","power_performance":"Power / Performance"}
    methods={
      "area":["footprint와 누적 실리콘 면적을 분리한다.","PIM 추가 면적과 TSV KOZ 상한을 별도 보고한다.","방법론 근거는 cacti7/mcpat_hpca2009이며 현재 절대 면적은 project_cost_assumption/project_architecture다."],
      "package":["interposer, microbump, TSV, 접합면, routing demand를 독립 proxy로 정규화한다.","공개 교차검증은 samsung_flashbolt_hbm2e/skhynix_hbm2_tsv이며 가중치는 견적식이 아닌 프로젝트 정책이다."],
      "yield":["negative-binomial die yield와 bond/TSV group/assembly yield를 곱한다.","식과 분해 근거는 negative_binomial_yield/xu_3d_yield_review/stacked_memory_yield_2012다.","모든 기본 수율 숫자는 project_cost_assumption이며 제조사 공개 수율이 아니다."],
      "power_performance":["1024 bit × 2.4 Gbps를 307.2 GB/s 공개 상한과 교차검증한다.","방법론은 roofline_berkeley, 제품 사양은 samsung_aquabolt_hbm2에 근거한다.","utilization, PIM speedup, power multiplier는 project_cost_assumption이다."]}
    for key,title in titles.items():
      lines=[f"# {title} 분석 보고서","",f"> {cfg['disclaimer']}","","## 계산 논리"]+[f"- {x}" for x in methods[key]]+["","## 시나리오 결과","","|Scenario|핵심 결과|","|---|---|"]
      for r in rows:
        data=r[key]; compact=", ".join(f"{k}={v:.6g}" if isinstance(v,(int,float)) else f"{k}={v}" for k,v in data.items() if k!="normalized_terms")
        lines.append(f"|{r['scenario']}|{compact}|")
      lines += ["","입력 분류와 범위는 `hardware_cost/config.json`, 출처는 `hardware_cost/sources.json`, 적용 논리는 `hardware_cost/RESEARCH_BASIS.md`에 있다."]
      (out/key/f"{key}_report.md").write_text("\n".join(lines)+"\n",encoding="utf-8")
    lines=["# Source traceability","","|ID|Type|Title / locator|Model use|Limitations|","|---|---|---|---|---|"]
    for s in sources["sources"]:
      locator=s.get("doi") or s.get("url") or s.get("path")
      lines.append(f"|`{s['id']}`|{s['type']}|{s['title']} — {locator}|{'; '.join(s['used_for'])}|{s['limitations']}|")
    (out/"source_traceability.md").write_text("\n".join(lines)+"\n",encoding="utf-8")

def write_plots(out,flat,unc):
    import matplotlib; matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    names=[r["scenario"].replace("hbm2_","") for r in flat]; x=np.arange(len(names)); width=.18
    fig,ax=plt.subplots(figsize=(11,5))
    for j,key in enumerate(("area_index","package_index","yield_cost_index","energy_index")): ax.bar(x+(j-1.5)*width,[r[key] for r in flat],width,label=key)
    ax.set_xticks(x,names,rotation=20); ax.set_ylabel("Normalized cost index (8Hi 1-stack = 1)"); ax.legend(ncol=2); fig.tight_layout(); fig.savefig(out/"cost_indices.png",dpi=170); plt.close(fig)
    fig,ax=plt.subplots(figsize=(10,5)); med=np.array([r["p50"] for r in unc]); low=med-np.array([r["p05"] for r in unc]); high=np.array([r["p95"] for r in unc])-med
    ax.errorbar(x,med,yerr=np.vstack([low,high]),fmt="o",capsize=5); ax.axhline(1,color="gray",ls="--"); ax.set_xticks(x,names,rotation=20); ax.set_ylabel("Performance / cost (P5, P50, P95)"); fig.tight_layout(); fig.savefig(out/"uncertainty_performance_per_cost.png",dpi=170); plt.close(fig)

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--config",default="hardware_cost/config.json"); ap.add_argument("--output",default="output/hbm2_hardware_cost"); a=ap.parse_args()
    cfg=read(a.config); sources=read("hardware_cost/sources.json"); validate_config(cfg,sources); arch=read(cfg["architecture_path"]); thermal=read(cfg["thermal_summary_path"])
    rows=analyze(cfg,arch,thermal); unc,unc_samples=uncertainty(cfg,arch,thermal); out=ROOT/a.output; out.mkdir(parents=True,exist_ok=True)
    (out/"integrated_metrics.json").write_text(json.dumps({"disclaimer":cfg["disclaimer"],"baseline":cfg["baseline"],"results":rows,"uncertainty":unc},indent=2),encoding="utf-8")
    flat=flatten_rows(rows); write_csv(out/"design_comparison.csv",flat); write_csv(out/"pareto_frontier.csv",[r for r in flat if r["pareto_optimal"]]); write_csv(out/"uncertainty_summary.csv",unc); write_csv(out/"uncertainty_samples.csv",unc_samples)
    write_plots(out,flat,unc)
    for key in ("area","package","yield","power_performance"):
      d=out/key; d.mkdir(exist_ok=True); (d/f"{key}_metrics.json").write_text(json.dumps({r["scenario"]:r[key] for r in rows},indent=2),encoding="utf-8")
    write_pipeline_reports(out,cfg,rows,sources)
    found=set()
    def find_sources(x):
      if isinstance(x,dict):
       if "source_id" in x: found.add(x["source_id"])
       for v in x.values(): find_sources(v)
      elif isinstance(x,list):
       for v in x: find_sources(v)
    find_sources(cfg)
    provenance={"config":a.config,"sources":"hardware_cost/sources.json","source_ids_used":sorted(found),"method_source_ids":["cacti7","mcpat_hpca2009","negative_binomial_yield","xu_3d_yield_review","stacked_memory_yield_2012","roofline_berkeley"],"model_equations":{"die_yield":"hardware_cost/yield/README.md","integration":"hardware_cost/integration/README.md"},"warning":"Method sources do not validate illustrative numeric defaults. See hardware_cost/RESEARCH_BASIS.md."}
    (out/"parameter_provenance.json").write_text(json.dumps(provenance,indent=2),encoding="utf-8")
    lines=["# HBM2 PIM 하드웨어 비용 분석 보고서","",f"> {cfg['disclaimer']}","","## 설계 비교","","|설계|Area|Package|Yield cost|Energy|통합 cost|성능|성능/비용|열|용량|종합 feasible|Pareto|","|---|---:|---:|---:|---:|---:|---:|---:|---|---|---|---|"]
    for r in flat: lines.append(f"|{r['scenario']}|{r['area_index']:.3f}|{r['package_index']:.3f}|{r['yield_cost_index']:.3f}|{r['energy_index']:.3f}|{r['combined_cost_index']:.3f}|{r['normalized_performance']:.3f}|{r['performance_per_cost']:.3f}|{r['thermal_feasible']}|{r['capacity_feasible']}|{r['overall_feasible']}|{r['pareto_optimal']}|")
    lines += ["","## 해석 근거와 한계","","- Area는 누적 실리콘 면적, PIM 추가 면적 및 TSV KOZ 상한을 분리한다. 방법 근거: `cacti7`, `mcpat_hpca2009`.","- Package는 interposer, microbump, TSV, 접합면, routing proxy를 사용한다. 공개 규모 교차검증: `samsung_flashbolt_hbm2e`, `skhynix_hbm2_tsv`.","- Yield는 negative-binomial die yield와 die/bond/TSV/assembly 분해를 사용한다. 식/구조 근거: `negative_binomial_yield`, `xu_3d_yield_review`, `stacked_memory_yield_2012`.","- Power/performance는 1024-bit × 2.4 Gbps = 307.2 GB/s/stack을 상한 검증점으로 사용한다: `samsung_aquabolt_hbm2`. 실제 utilization, PIM speedup, power는 추정 범위다.","- 통합값은 동일 가중 기하평균이라는 프로젝트 정책이며 제조사 가격식이 아니다. 개별 물리량과 Pareto 결과를 우선 해석한다.","","전체 서지정보와 각 주장의 적용 범위는 `hardware_cost/sources.json`을 참조한다."]
    (out/"hardware_cost_report.md").write_text("\n".join(lines)+"\n",encoding="utf-8"); print(json.dumps({"status":"PASS","output":str(out),"scenarios":flat,"uncertainty":unc},indent=2))

if __name__=="__main__": main()
