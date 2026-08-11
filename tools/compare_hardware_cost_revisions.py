#!/usr/bin/env python3
"""Compare provisional hardware-cost snapshots and emit paper-ready artifacts."""
from __future__ import annotations
import argparse,csv,json,math
from pathlib import Path
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
    if s.get("schema_version")!=1: raise CompareError("snapshot schema_version must be 1")
    if s["parameter_status"].get("final_architecture_parameters_selected") is not False: raise CompareError("final parameter selection is forbidden")
    if set(s["categories"])!=set(CATEGORIES): raise CompareError(f"category set mismatch in {s['revision']['id']}")
    power=sum(s["categories"][x]["total_power_W"] for x in CATEGORIES)
    if abs(power-s["physical_totals"]["total_power_W"])>1e-12: raise CompareError(f"category power mismatch in {s['revision']['id']}")
    block_power=sum(x["total_power_W"] for x in s.get("block_metrics",[]))
    if abs(block_power-s["physical_totals"]["total_power_W"])>1e-12: raise CompareError(f"block power mismatch in {s['revision']['id']}")

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
        row={"revision":s["revision"]["id"],"label":s["revision"]["label"],"git_commit":s["revision"]["git_commit"],"dirty":s["revision"]["working_tree_dirty"],
             "parameter_status":"PROVISIONAL","fp16_generic_cells":precision_cells(s,"FP16"),"bf16_generic_cells":precision_cells(s,"BF16"),
             "mapped_area_um2":t["mapped_floorplan_area_um2"],"technology_mapped_area_um2":t["technology_mapped_area_um2"],"critical_path_ns":t["critical_path_ns"],"slack_ns":t["slack_ns"],
             "dynamic_power_W":t["dynamic_power_W"],"leakage_power_W":t["leakage_power_W"],"total_power_W":t["total_power_W"],
             "energy_per_op_J":w["energy_per_op_J"],"throughput_ops_s":w["throughput_ops_s"],"peak_temperature_K":th["peak_temperature_K"],
             "hotspot_layer":th["hotspot"].get("layer"),"hotspot_x":th["hotspot"].get("x_index"),"hotspot_y":th["hotspot"].get("y_index"),
             "area_vs_baseline_pct":pct(t["mapped_floorplan_area_um2"],bt["mapped_floorplan_area_um2"]),"power_vs_baseline_pct":pct(t["total_power_W"],bt["total_power_W"]),
             "peak_delta_vs_baseline_K":th["peak_temperature_K"]-bth["peak_temperature_K"],"energy_vs_baseline_pct":pct(w["energy_per_op_J"],base["workload"]["energy_per_op_J"]),
             "area_vs_previous_pct":pct(t["mapped_floorplan_area_um2"],p["physical_totals"]["mapped_floorplan_area_um2"]) if p else None,
             "power_vs_previous_pct":pct(t["total_power_W"],p["physical_totals"]["total_power_W"]) if p else None,
             "peak_delta_vs_previous_K":th["peak_temperature_K"]-p["thermal"]["peak_temperature_K"] if p else None}
        rows.append(row)
    cats=[]
    for s in snapshots:
        for c in CATEGORIES:
            x=s["categories"][c]; b=base["categories"][c]
            cats.append({"revision":s["revision"]["id"],"category":c,"mapped_area_um2":x["mapped_area_um2"],"area_vs_baseline_ratio":ratio(x["mapped_area_um2"],b["mapped_area_um2"]),
                         "dynamic_power_W":x["dynamic_power_W"],"leakage_power_W":x["leakage_power_W"],"total_power_W":x["total_power_W"],"power_vs_baseline_ratio":ratio(x["total_power_W"],b["total_power_W"]),
                         "fp16_generic_cells":sum(o["generic_cells"] for o in x["synthesis_observations"] if o["precision"]=="FP16") or None,
                         "bf16_generic_cells":sum(o["generic_cells"] for o in x["synthesis_observations"] if o["precision"]=="BF16") or None,
                         "calibration":x["physical_calibration"]})
    deltas=[{"revision":r["revision"],"area_vs_baseline_pct":r["area_vs_baseline_pct"],"power_vs_baseline_pct":r["power_vs_baseline_pct"],"peak_delta_vs_baseline_K":r["peak_delta_vs_baseline_K"],"energy_vs_baseline_pct":r["energy_vs_baseline_pct"],"area_vs_previous_pct":r["area_vs_previous_pct"],"power_vs_previous_pct":r["power_vs_previous_pct"],"peak_delta_vs_previous_K":r["peak_delta_vs_previous_K"]} for r in rows]
    write_csv(out/"paper_revision_table.csv",rows); write_csv(out/"paper_category_table.csv",cats); write_csv(out/"paper_delta_table.csv",deltas)
    report=["# Hardware-cost revision regression","",f"Baseline: `{baseline_id}`", "","> All revisions are provisional. GR00T-driven final architecture parameters are intentionally not selected.","",
            "## Paper revision table","","|Revision|FP16 cells|BF16 cells|Area (um^2)|Power (W)|Energy/op (J)|Peak (K)|Hotspot|Area Δ base|Power Δ base|Peak Δ base|Area Δ prev|Power Δ prev|Peak Δ prev|",
            "|---|---:|---:|---:|---:|---:|---:|---|---:|---:|---:|---:|---:|---:|"]
    for r in rows: report.append(f"|{r['revision']}|{r['fp16_generic_cells'] or 'N/A'}|{r['bf16_generic_cells'] or 'N/A'}|{fmt(r['mapped_area_um2'],1)}|{fmt(r['total_power_W'])}|{fmt(r['energy_per_op_J'],9)}|{fmt(r['peak_temperature_K'])}|{r['hotspot_layer']} ({r['hotspot_x']},{r['hotspot_y']})|{fmt(r['area_vs_baseline_pct'])}%|{fmt(r['power_vs_baseline_pct'])}%|{fmt(r['peak_delta_vs_baseline_K'])} K|{fmt(r['area_vs_previous_pct'])}%|{fmt(r['power_vs_previous_pct'])}%|{fmt(r['peak_delta_vs_previous_K'])} K|")
    report += ["","## Cost-category table","","|Revision|Category|Mapped area (um^2)|Power (W)|FP16 cells|BF16 cells|Calibration|","|---|---|---:|---:|---:|---:|---|"]
    for r in cats: report.append(f"|{r['revision']}|{r['category']}|{fmt(r['mapped_area_um2'],1)}|{fmt(r['total_power_W'])}|{r['fp16_generic_cells'] or 'N/A'}|{r['bf16_generic_cells'] or 'N/A'}|{r['calibration']}|")
    report += ["","## Interpretation limits","","- Generic cell count is not silicon area; generic topological path length is not ns.","- `N/A` energy/op is expected until a completed GR00T workload supplies throughput or equivalent completed-work timing.","- Synthetic area, power, and temperature establish regression plumbing, not absolute silicon claims.","- A zero with `not_available` calibration means no physical block was mapped for that category; it is not a measured zero-cost claim.","- Categories are exclusive for physical totals. Alternative FP16/BF16 synthesis candidates are reported separately and are never summed into a chosen architecture."]
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
    except ImportError: raise CompareError("matplotlib is required for paper plots")
    summary={"status":"PASS","baseline":baseline_id,"revision_count":len(rows),"final_architecture_parameters_selected":False,"outputs":["paper_revision_table.csv","paper_category_table.csv","paper_delta_table.csv","paper_regression_report.md","paper_revision_overview.png","paper_category_power.png"]}
    (out/"regression_summary.json").write_text(json.dumps(summary,indent=2),encoding="utf-8"); print(json.dumps(summary,indent=2)); return summary

def main():
    ap=argparse.ArgumentParser(description=__doc__); ap.add_argument("--revisions",default="hardware_cost/regression/revisions"); ap.add_argument("--baseline",required=True); ap.add_argument("--output",default="reports/hardware_cost_regression"); a=ap.parse_args()
    try: compare(a.revisions,a.baseline,a.output)
    except (CompareError,KeyError,OSError,json.JSONDecodeError) as exc: print(f"ERROR: {exc}"); return 2
    return 0
if __name__=="__main__": raise SystemExit(main())
