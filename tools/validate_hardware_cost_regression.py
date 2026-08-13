#!/usr/bin/env python3
"""Independent structural and accounting checks for cost regression outputs."""
import argparse,csv,json,math
from pathlib import Path
from hardware_cost_evidence_contract import validate_snapshot
ROOT=Path(__file__).resolve().parents[1]
CATEGORIES={"bf16_fp16","normalization_rounding","accumulator_reduction","buffer_register","control_routing"}
def path(v):
    p=Path(v); return p if p.is_absolute() else ROOT/p
def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--revisions",default="hardware_cost/regression/revisions"); ap.add_argument("--baseline",required=True); ap.add_argument("--output",default="reports/hardware_cost_regression"); a=ap.parse_args(); checks=[]
    def check(name,condition,detail): checks.append({"name":name,"pass":bool(condition),"detail":detail})
    revisions=[]
    for p in path(a.revisions).glob("*.json"): revisions.append(json.loads(p.read_text(encoding="utf-8")))
    by={s["revision"]["id"]:s for s in revisions}; check("baseline exists",a.baseline in by,sorted(by))
    check("revision ids unique",len(by)==len(revisions),len(revisions)); check("architecture remains provisional",all(s["parameter_status"]["final_architecture_parameters_selected"] is False for s in revisions),[s["revision"]["id"] for s in revisions])
    contract_errors={s.get("revision",{}).get("id",f"index-{i}"):validate_snapshot(s) for i,s in enumerate(revisions)}
    check("Evidence Contract v2 schema and calibration invariants",all(not errors for errors in contract_errors.values()),contract_errors)
    check("all cost categories present",all(set(s["categories"])==CATEGORIES for s in revisions),sorted(CATEGORIES))
    conservation=[]
    for s in revisions:
        total=sum(s["categories"][c]["total_power_W"] for c in CATEGORIES); conservation.append(abs(total-s["physical_totals"]["total_power_W"]))
    check("category power conservation",all(x<=1e-12 for x in conservation),conservation)
    block_conservation=[abs(sum(x["total_power_W"] for x in s["block_metrics"])-s["physical_totals"]["total_power_W"]) for s in revisions]
    check("block power conservation",all(x<=1e-12 for x in block_conservation),block_conservation)
    check("source hashes and claim classes recorded",all(all(len(x["sha256"])==64 and x["bytes"]>0 and x["claim_class"] in {"measured","derived","modeled","assumed"} for x in s["source_files"]) for s in revisions),"sha256, byte count, and claim class")
    check("metric values finite or null",all(all(v is None or (isinstance(v,(int,float)) and math.isfinite(v)) for v in (s["physical_totals"]["mapped_floorplan_area_um2"],s["physical_totals"]["critical_path_ns"],s["physical_totals"]["slack_ns"],s["workload"]["energy_per_op_J"],s["thermal"]["peak_temperature_K"])) for s in revisions),"area/timing/energy/temperature")
    out=path(a.output); required=["paper_revision_table.csv","paper_category_table.csv","paper_delta_table.csv","paper_regression_report.md","paper_revision_overview.png","paper_category_power.png","paper_timing_throughput.png","regression_summary.json"]
    check("paper outputs exist",all((out/x).is_file() and (out/x).stat().st_size>0 for x in required),required)
    with (out/"paper_revision_table.csv").open(newline="",encoding="utf-8") as f: rows=list(csv.DictReader(f))
    check("paper table covers every revision",{r["revision"] for r in rows}==set(by),[r["revision"] for r in rows])
    check("paper table exposes calibration levels",all(all(r.get(x) for x in ("physical_calibration","timing_calibration","power_calibration","thermal_calibration","workload_calibration")) for r in rows),"five adapter axes")
    base_row=next((r for r in rows if r["revision"]==a.baseline),None)
    check("baseline deltas are zero",base_row is not None and all(abs(float(base_row[x]))<=1e-12 for x in ("area_vs_baseline_pct","power_vs_baseline_pct","peak_delta_vs_baseline_K")),base_row)
    report={"status":"PASS" if all(x["pass"] for x in checks) else "FAIL","checks":checks,"scope":"Revision regression plumbing; no final architecture choice or silicon signoff."}
    (out/"validation_report.json").write_text(json.dumps(report,indent=2),encoding="utf-8"); print(json.dumps(report,indent=2)); return 0 if report["status"]=="PASS" else 1
if __name__=="__main__": raise SystemExit(main())
