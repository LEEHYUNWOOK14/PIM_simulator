#!/usr/bin/env python3
"""Compare provisional hardware-cost snapshots and emit paper-ready artifacts."""
from __future__ import annotations
import argparse,csv,json,math
from pathlib import Path
from hardware_cost_evidence_contract import EvidenceContractError, comparison_policy, require_valid_snapshot
ROOT=Path(__file__).resolve().parents[1]
CATEGORIES=("bf16_fp16","normalization_rounding","accumulator_reduction","buffer_register","control_routing")

class CompareError(ValueError): pass
def path(v):
    p=Path(v); return p if p.is_absolute() else ROOT/p
def pct(value,base): return None if value is None or base in (None,0) else (value/base-1)*100
def ratio(value,base): return None if value is None or base in (None,0) else value/base
def fmt(v,d=3): return "N/A" if v is None else f"{v:.{d}f}"
def write_csv(p,rows):
    if not rows:return
    with p.open("w",newline="",encoding="utf-8") as f: w=csv.DictWriter(f,fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)

def precision_cells(snapshot,precision):
    values=[x["generic_cells"] for x in snapshot["observations"] if x.get("precision")==precision]
    return sum(values) if len(values)>1 else values[0] if values else None

def validate_snapshot(s):
    try: require_valid_snapshot(s)
    except EvidenceContractError as exc: raise CompareError(str(exc)) from exc
    if s["parameter_status"].get("final_architecture_parameters_selected") is not False: raise CompareError("final parameter selection is forbidden")
    if set(s["categories"])!=set(CATEGORIES): raise CompareError(f"category set mismatch in {s['revision']['id']}")
    power=sum(s["categories"][x]["total_power_W"] for x in CATEGORIES)
    if abs(power-s["physical_totals"]["total_power_W"])>1e-12: raise CompareError(f"category power mismatch in {s['revision']['id']}")
    block_power=sum(x["total_power_W"] for x in s.get("block_metrics",[]))
    if abs(block_power-s["physical_totals"]["total_power_W"])>1e-12: raise CompareError(f"block power mismatch in {s['revision']['id']}")

def metric_policy(current,reference,axes):
    policies=[comparison_policy(current["calibration"][axis],reference["calibration"][axis]) for axis in axes]
    order={"quantitative":0,"reference_only":1,"unavailable":2,"prohibited":3}
    status=max((p["status"] for p in policies),key=lambda x:order[x])
    return {"status":status,"delta_allowed":all(p["delta_allowed"] for p in policies),"axes":list(axes)}

def guarded_pct(value,base,current,reference,axes):
    if value is None or base is None:
        return None,"unavailable"
    policy=metric_policy(current,reference,axes)
    return (pct(value,base) if policy["delta_allowed"] else None),policy["status"]

def guarded_difference(value,base,current,reference,axes):
    if value is None or base is None:
        return None,"unavailable"
    policy=metric_policy(current,reference,axes)
    return ((value-base) if policy["delta_allowed"] and value is not None and base is not None else None),policy["status"]

def compare(revisions_path,baseline_id,output_path):
    rp=path(revisions_path); files=sorted(rp.glob("*.json")); snapshots=[]
    for p in files:
        s=json.loads(p.read_text(encoding="utf-8")); validate_snapshot(s); snapshots.append(s)
    if not snapshots: raise CompareError("no revision snapshots")
    snapshots.sort(key=lambda x:(x["revision"]["captured_at"],x["revision"]["id"])); by={x["revision"]["id"]:x for x in snapshots}
    if len(by)!=len(snapshots): raise CompareError("duplicate revision id")
    if baseline_id not in by: raise CompareError(f"baseline not found: {baseline_id}")
    base=by[baseline_id]; out=path(output_path); out.mkdir(parents=True,exist_ok=True)
    rows=[]
    for i,s in enumerate(snapshots):
        p=snapshots[i-1] if i else None; t=s["physical_totals"]; bt=base["physical_totals"]; th=s["thermal"]; bth=base["thermal"]; w=s["workload"]
        area_base,area_base_policy=guarded_pct(t["mapped_floorplan_area_um2"],bt["mapped_floorplan_area_um2"],s,base,("physical",))
        power_base,power_base_policy=guarded_pct(t["total_power_W"],bt["total_power_W"],s,base,("power",))
        peak_base,peak_base_policy=guarded_difference(th["peak_temperature_K"],bth["peak_temperature_K"],s,base,("thermal",))
        energy_base,energy_base_policy=guarded_pct(w["energy_per_op_J"],base["workload"]["energy_per_op_J"],s,base,("power","workload"))
        timing_base,timing_base_policy=guarded_pct(t["critical_path_ns"],bt["critical_path_ns"],s,base,("timing",))
        throughput_base,throughput_base_policy=guarded_pct(w["throughput_ops_s"],base["workload"]["throughput_ops_s"],s,base,("workload",))
        area_prev,area_prev_policy=guarded_pct(t["mapped_floorplan_area_um2"],p["physical_totals"]["mapped_floorplan_area_um2"],s,p,("physical",)) if p else (None,"unavailable")
        power_prev,power_prev_policy=guarded_pct(t["total_power_W"],p["physical_totals"]["total_power_W"],s,p,("power",)) if p else (None,"unavailable")
        peak_prev,peak_prev_policy=guarded_difference(th["peak_temperature_K"],p["thermal"]["peak_temperature_K"],s,p,("thermal",)) if p else (None,"unavailable")
        timing_prev,timing_prev_policy=guarded_pct(t["critical_path_ns"],p["physical_totals"]["critical_path_ns"],s,p,("timing",)) if p else (None,"unavailable")
        throughput_prev,throughput_prev_policy=guarded_pct(w["throughput_ops_s"],p["workload"]["throughput_ops_s"],s,p,("workload",)) if p else (None,"unavailable")
        row={"revision":s["revision"]["id"],"label":s["revision"]["label"],"git_commit":s["revision"]["git_commit"],"dirty":s["revision"]["working_tree_dirty"],
             "parameter_status":"PROVISIONAL","physical_feasibility_status":s["physical_feasibility"]["status"],"rtl_freeze_allowed":s["physical_feasibility"]["rtl_freeze_allowed"],"fp16_generic_cells":precision_cells(s,"FP16"),"bf16_generic_cells":precision_cells(s,"BF16"),
             "mapped_area_um2":t["mapped_floorplan_area_um2"],"technology_mapped_area_um2":t["technology_mapped_area_um2"],"critical_path_ns":t["critical_path_ns"],"slack_ns":t["slack_ns"],
             "dynamic_power_W":t["dynamic_power_W"],"leakage_power_W":t["leakage_power_W"],"total_power_W":t["total_power_W"],
             "energy_per_op_J":w["energy_per_op_J"],"throughput_ops_s":w["throughput_ops_s"],"peak_temperature_K":th["peak_temperature_K"],
             "hotspot_layer":th["hotspot"].get("layer"),"hotspot_x":th["hotspot"].get("x_index"),"hotspot_y":th["hotspot"].get("y_index"),
             "physical_calibration":s["calibration"]["physical"],"timing_calibration":s["calibration"]["timing"],"power_calibration":s["calibration"]["power"],"thermal_calibration":s["calibration"]["thermal"],"workload_calibration":s["calibration"]["workload"],
             "area_vs_baseline_pct":area_base,"area_vs_baseline_policy":area_base_policy,"power_vs_baseline_pct":power_base,"power_vs_baseline_policy":power_base_policy,
             "peak_delta_vs_baseline_K":peak_base,"peak_vs_baseline_policy":peak_base_policy,"energy_vs_baseline_pct":energy_base,"energy_vs_baseline_policy":energy_base_policy,
             "critical_path_vs_baseline_pct":timing_base,"critical_path_vs_baseline_policy":timing_base_policy,"throughput_vs_baseline_pct":throughput_base,"throughput_vs_baseline_policy":throughput_base_policy,
             "area_vs_previous_pct":area_prev,"area_vs_previous_policy":area_prev_policy,"power_vs_previous_pct":power_prev,"power_vs_previous_policy":power_prev_policy,
             "peak_delta_vs_previous_K":peak_prev,"peak_vs_previous_policy":peak_prev_policy,"critical_path_vs_previous_pct":timing_prev,"critical_path_vs_previous_policy":timing_prev_policy,"throughput_vs_previous_pct":throughput_prev,"throughput_vs_previous_policy":throughput_prev_policy}
        rows.append(row)
    cats=[]
    for s in snapshots:
        for c in CATEGORIES:
            x=s["categories"][c]; b=base["categories"][c]
            area_policy=comparison_policy(x["physical_calibration"],b["physical_calibration"])
            power_policy=comparison_policy(x["power_calibration"],b["power_calibration"])
            cats.append({"revision":s["revision"]["id"],"category":c,"mapped_area_um2":x["mapped_area_um2"],"area_vs_baseline_ratio":ratio(x["mapped_area_um2"],b["mapped_area_um2"]) if area_policy["delta_allowed"] else None,
                         "dynamic_power_W":x["dynamic_power_W"],"leakage_power_W":x["leakage_power_W"],"total_power_W":x["total_power_W"],"power_vs_baseline_ratio":ratio(x["total_power_W"],b["total_power_W"]) if power_policy["delta_allowed"] else None,
                         "fp16_generic_cells":sum(o["generic_cells"] for o in x["synthesis_observations"] if o["precision"]=="FP16") or None,
                         "bf16_generic_cells":sum(o["generic_cells"] for o in x["synthesis_observations"] if o["precision"]=="BF16") or None,
                         "physical_calibration":x["physical_calibration"],"power_calibration":x["power_calibration"],"area_comparison_policy":area_policy["status"],"power_comparison_policy":power_policy["status"]})
    delta_keys=("area_vs_baseline_pct","area_vs_baseline_policy","power_vs_baseline_pct","power_vs_baseline_policy","peak_delta_vs_baseline_K","peak_vs_baseline_policy","energy_vs_baseline_pct","energy_vs_baseline_policy","critical_path_vs_baseline_pct","critical_path_vs_baseline_policy","throughput_vs_baseline_pct","throughput_vs_baseline_policy","area_vs_previous_pct","area_vs_previous_policy","power_vs_previous_pct","power_vs_previous_policy","peak_delta_vs_previous_K","peak_vs_previous_policy","critical_path_vs_previous_pct","critical_path_vs_previous_policy","throughput_vs_previous_pct","throughput_vs_previous_policy")
    deltas=[{"revision":r["revision"],**{key:r[key] for key in delta_keys}} for r in rows]
    write_csv(out/"paper_revision_table.csv",rows); write_csv(out/"paper_category_table.csv",cats); write_csv(out/"paper_delta_table.csv",deltas)
    report=["# Hardware-cost revision regression","",f"Baseline: `{baseline_id}`", "","> All revisions are provisional. GR00T-driven final architecture parameters are intentionally not selected.","",
            "## Paper revision table","","|Revision|Physical gate|RTL freeze|Cells|Area (um^2)|Path (ns)|Throughput (op/s)|Power (W)|Energy/op (J)|Peak (K)|Calibrations (A/T/P/W/Th)|Area Δ|Path Δ|Throughput Δ|Power Δ|Peak Δ|",
            "|---|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|---:|---:|---:|---:|"]
    for r in rows: report.append(f"|{r['revision']}|{r['physical_feasibility_status']}|{r['rtl_freeze_allowed']}|{r['fp16_generic_cells'] or r['bf16_generic_cells'] or 'N/A'}|{fmt(r['mapped_area_um2'],1)}|{fmt(r['critical_path_ns'])}|{fmt(r['throughput_ops_s'],1)}|{fmt(r['total_power_W'])}|{fmt(r['energy_per_op_J'],9)}|{fmt(r['peak_temperature_K'])}|{r['physical_calibration']} / {r['timing_calibration']} / {r['power_calibration']} / {r['workload_calibration']} / {r['thermal_calibration']}|{fmt(r['area_vs_baseline_pct'])}% ({r['area_vs_baseline_policy']})|{fmt(r['critical_path_vs_baseline_pct'])}% ({r['critical_path_vs_baseline_policy']})|{fmt(r['throughput_vs_baseline_pct'])}% ({r['throughput_vs_baseline_policy']})|{fmt(r['power_vs_baseline_pct'])}% ({r['power_vs_baseline_policy']})|{fmt(r['peak_delta_vs_baseline_K'])} K ({r['peak_vs_baseline_policy']})|")
    report += ["","## Cost-category table","","|Revision|Category|Mapped area (um^2)|Power (W)|FP16 cells|BF16 cells|Area calibration|Power calibration|","|---|---|---:|---:|---:|---:|---|---|"]
    for r in cats: report.append(f"|{r['revision']}|{r['category']}|{fmt(r['mapped_area_um2'],1)}|{fmt(r['total_power_W'])}|{r['fp16_generic_cells'] or 'N/A'}|{r['bf16_generic_cells'] or 'N/A'}|{r['physical_calibration']}|{r['power_calibration']}|")
    report += ["","## Calibration comparison policy","","- `quantitative`: identical calibration stages; numerical deltas are emitted.","- `reference_only`: adjacent stages; absolute values remain visible but deltas are suppressed.","- `prohibited`: stages differ by two or more levels; deltas are suppressed.","- `unavailable`: at least one required evidence axis is pending or unavailable.","","## Interpretation limits","","- Generic cell count is not silicon area; generic topological path length is not ns.","- Energy/op requires activity-based or stronger power evidence plus workload throughput.","- Synthetic area, power, and temperature establish regression plumbing, not absolute silicon claims.","- A zero with `not_available` calibration means no physical block was mapped for that category; it is not a measured zero-cost claim.","- Categories are exclusive for physical totals. Alternative FP16/BF16 synthesis candidates are reported separately and are never summed into a chosen architecture."]
    (out/"paper_regression_report.md").write_text("\n".join(report)+"\n",encoding="utf-8")
    try:
        import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
        labels=[x["revision"].replace("provisional_","") for x in rows]; xs=range(len(rows))
        fig,axes=plt.subplots(1,3,figsize=(14,4.5)); axes[0].bar([x-.18 for x in xs],[r["fp16_generic_cells"] or 0 for r in rows],.36,label="FP16"); axes[0].bar([x+.18 for x in xs],[r["bf16_generic_cells"] or 0 for r in rows],.36,label="BF16"); axes[0].set_ylabel("Generic cells (proxy)"); axes[0].legend()
        axes[1].bar(xs,[r["total_power_W"] for r in rows]); axes[1].set_ylabel("Mapped power (W)")
        axes[2].bar(xs,[r["peak_temperature_K"] for r in rows]); axes[2].set_ylabel("Peak temperature (K)")
        for ax in axes: ax.set_xticks(list(xs),labels,rotation=20,ha="right"); ax.grid(axis="y",alpha=.2)
        fig.tight_layout(); fig.savefig(out/"paper_revision_overview.png",dpi=180); plt.close(fig)
        fig,ax=plt.subplots(figsize=(10,5)); bottom=[0.0]*len(rows)
        for c in CATEGORIES:
            vals=[s["categories"][c]["total_power_W"] for s in snapshots]; ax.bar(labels,vals,bottom=bottom,label=c); bottom=[a+b for a,b in zip(bottom,vals)]
        ax.set_ylabel("Power (W)"); ax.legend(fontsize=8,ncol=2); ax.tick_params(axis="x",rotation=20); fig.tight_layout(); fig.savefig(out/"paper_category_power.png",dpi=180); plt.close(fig)
        fig,axes=plt.subplots(1,2,figsize=(10,4.5))
        axes[0].bar(labels,[r["critical_path_ns"] or 0 for r in rows]); axes[0].set_ylabel("Critical path (ns)")
        axes[1].bar(labels,[r["throughput_ops_s"] or 0 for r in rows]); axes[1].set_ylabel("Throughput (op/s)")
        for ax in axes: ax.tick_params(axis="x",rotation=20); ax.grid(axis="y",alpha=.2)
        fig.tight_layout(); fig.savefig(out/"paper_timing_throughput.png",dpi=180); plt.close(fig)
    except ImportError: raise CompareError("matplotlib is required for paper plots")
    summary={"status":"PASS","evidence_contract_version":2,"baseline":baseline_id,"revision_count":len(rows),"final_architecture_parameters_selected":False,"outputs":["paper_revision_table.csv","paper_category_table.csv","paper_delta_table.csv","paper_regression_report.md","paper_revision_overview.png","paper_category_power.png","paper_timing_throughput.png"]}
    (out/"regression_summary.json").write_text(json.dumps(summary,indent=2),encoding="utf-8"); print(json.dumps(summary,indent=2)); return summary

def main():
    ap=argparse.ArgumentParser(description=__doc__); ap.add_argument("--revisions",default="hardware_cost/regression/revisions"); ap.add_argument("--baseline",required=True); ap.add_argument("--output",default="reports/hardware_cost_regression"); a=ap.parse_args()
    try: compare(a.revisions,a.baseline,a.output)
    except (CompareError,KeyError,OSError,json.JSONDecodeError) as exc: print(f"ERROR: {exc}"); return 2
    return 0
if __name__=="__main__": raise SystemExit(main())
