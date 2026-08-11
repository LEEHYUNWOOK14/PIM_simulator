#!/usr/bin/env python3
"""Freeze one provisional hardware-cost revision with source provenance."""
from __future__ import annotations
import argparse, hashlib, json, math, re, subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
CATEGORIES=("bf16_fp16","normalization_rounding","accumulator_reduction","buffer_register","control_routing")

class CaptureError(ValueError): pass

def path(value):
    p=Path(value); return p if p.is_absolute() else ROOT/p

def load(value): return json.loads(path(value).read_text(encoding="utf-8"))

def digest(p: Path):
    h=hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda:f.read(1024*1024),b""): h.update(chunk)
    return h.hexdigest()

def source_record(p: Path, role: str):
    try: locator=p.resolve().relative_to(ROOT.resolve()).as_posix()
    except ValueError: locator=str(p.resolve())
    return {"role":role,"path":locator,"sha256":digest(p),"bytes":p.stat().st_size}

def parse_yosys(p: Path):
    text=p.read_text(encoding="utf-8",errors="replace")
    if "End of script." not in text: raise CaptureError(f"incomplete Yosys evidence: {p}")
    sections=text.split("=== design hierarchy ===")
    cells=re.findall(r"Number of cells:\s+(\d+)",sections[-1])
    paths=re.findall(r"Longest topological path.*?\(length=(\d+)\)",text)
    if not cells or not paths: raise CaptureError(f"missing Yosys cell/path metric: {p}")
    return int(cells[-1]),int(paths[-1])

def git_info():
    def run(*args): return subprocess.run(["git",*args],cwd=ROOT,text=True,capture_output=True,check=True).stdout.strip()
    return run("rev-parse","HEAD"),bool(run("status","--porcelain"))

def number(value,name,allow_none=True):
    if value is None and allow_none:return None
    try: value=float(value)
    except (TypeError,ValueError) as exc: raise CaptureError(f"{name} must be numeric") from exc
    if not math.isfinite(value) or value<0: raise CaptureError(f"{name} must be finite and non-negative")
    return value

def capture(manifest_path,output_path):
    manifest=load(manifest_path)
    if manifest.get("schema_version")!=1: raise CaptureError("manifest schema_version must be 1")
    status=manifest.get("parameter_status",{})
    if status.get("final_architecture_parameters_selected") is not False:
        raise CaptureError("final architecture parameter selection must remain false")
    rules=load("hardware_cost/regression/category_rules.json"); valid=set(rules["categories"])
    mapped_path=path(manifest["mapped_power_json"]); thermal_path=path(manifest["thermal_summary_json"]); workload_path=path(manifest["gr00t_workload_json"])
    mapped=json.loads(mapped_path.read_text(encoding="utf-8")); thermal=json.loads(thermal_path.read_text(encoding="utf-8")); workload=json.loads(workload_path.read_text(encoding="utf-8"))
    if mapped.get("status")!="PASS" or mapped.get("unmapped_blocks"): raise CaptureError("mapped power must PASS with zero unmapped blocks")
    if thermal.get("status")!="PASS": raise CaptureError("thermal summary must PASS")
    if workload.get("final_architecture_parameters_selected") is not False: raise CaptureError("GR00T payload may not finalize architecture")
    commit,dirty=git_info(); sources=[source_record(path(manifest_path),"manifest"),source_record(mapped_path,"mapped_power"),source_record(thermal_path,"thermal"),source_record(workload_path,"gr00t_contract")]
    observations=[]
    for item in manifest.get("synthesis_observations",[]):
        if item["category"] not in valid: raise CaptureError(f"invalid category: {item['category']}")
        upstream={}
        if item.get("metrics_file"):
            p=path(item["metrics_file"]); frozen=json.loads(p.read_text(encoding="utf-8")); matches=[x for x in frozen["observations"] if x["name"]==item["name"]]
            if len(matches)!=1: raise CaptureError(f"frozen observation not found uniquely: {item['name']}")
            evidence=matches[0]; cells=int(evidence["generic_cells"]); topo=int(evidence["generic_topological_path_length"])
            upstream={"source_log":evidence.get("source_log"),"source_log_sha256":evidence.get("source_log_sha256")}
        else:
            p=path(item["yosys_log"]); cells,topo=parse_yosys(p)
        sources.append(source_record(p,f"yosys:{item['name']}"))
        mapped_area=number(item.get("technology_mapped_area_um2"),f"{item['name']} technology area")
        critical=number(item.get("critical_path_ns"),f"{item['name']} critical path")
        slack=item.get("slack_ns")
        if slack is not None:
            try: slack=float(slack)
            except (TypeError,ValueError) as exc: raise CaptureError(f"{item['name']} slack must be numeric") from exc
            if not math.isfinite(slack): raise CaptureError(f"{item['name']} slack must be finite")
        calibration=item.get("calibration") or ("technology_mapped" if any(x is not None for x in (mapped_area,critical,slack)) else "synthesis_generic")
        observations.append({"name":item["name"],"precision":item["precision"],"category":item["category"],
            "generic_cells":cells,"generic_topological_path_length":topo,"technology_mapped_area_um2":mapped_area,
            "critical_path_ns":critical,"slack_ns":slack,"calibration":calibration,"evidence":sources[-1]["path"],
            "upstream_evidence":upstream,"warning":"Generic cells/path are not technology-mapped area or timing."})
    overrides=manifest.get("block_category_overrides",{}); category={k:{"mapped_area_um2":0.0,"dynamic_power_W":0.0,"leakage_power_W":0.0,"total_power_W":0.0,"blocks":[],"synthesis_observations":[]} for k in CATEGORIES}
    for obs in observations: category[obs["category"]]["synthesis_observations"].append({k:obs[k] for k in ("name","precision","generic_cells","generic_topological_path_length","calibration")})
    block_metrics=[]
    for block in mapped["blocks"]:
        cat=overrides.get(block["instance"])
        if cat not in valid: raise CaptureError(f"block lacks valid exclusive category: {block['instance']}")
        row=category[cat]; row["mapped_area_um2"]+=number(block["mapped_area_um2"],"mapped area",False); row["dynamic_power_W"]+=number(block["dynamic_power_W"],"dynamic power",False); row["leakage_power_W"]+=number(block["leakage_power_W"],"leakage power",False); row["total_power_W"]+=number(block["total_power_W"],"total power",False); row["blocks"].append(block["instance"])
        block_metrics.append({"instance":block["instance"],"module":block["module"],"category":cat,"target":block["target"],
            "mapped_area_um2":block["mapped_area_um2"],"dynamic_power_W":block["dynamic_power_W"],"leakage_power_W":block["leakage_power_W"],
            "total_power_W":block["total_power_W"],"power_density_W_mm2":block["power_density_W_mm2"],"calibration":"synthetic"})
    for row in category.values():
        row["power_density_W_mm2"]=row["total_power_W"]/(row["mapped_area_um2"]*1e-6) if row["mapped_area_um2"] else None
        row["physical_data_available"]=bool(row["blocks"])
        row["physical_calibration"]="synthetic" if row["blocks"] else "not_available"
    metrics=workload.get("metrics",{}); throughput=number(metrics.get("throughput_ops_s"),"throughput")
    total_power=float(mapped["checks"]["mapped_power_W"]); energy_op=total_power/throughput if throughput else None
    primary_name=manifest.get("primary_observation"); primary=next((x for x in observations if x["name"]==primary_name),None)
    if primary_name and primary is None: raise CaptureError(f"primary_observation not found: {primary_name}")
    workload_result={"status":workload["status"],"name":workload.get("workload",{}).get("name"),"precision":workload.get("workload",{}).get("precision"),
        "operation_count":metrics.get("operation_count"),"latency_cycles":metrics.get("latency_cycles"),"clock_period_ns":metrics.get("clock_period_ns"),
        "throughput_ops_s":throughput,"energy_per_op_J":energy_op,"calibration":"pending" if workload["status"]=="pending" else "workload_model",
        "note":"Energy/op remains null until throughput or equivalent completed-work timing is supplied." if energy_op is None else "Derived as total mapped power / throughput."}
    result={"schema_version":1,"revision":{"id":manifest["revision_id"],"label":manifest["label"],"git_commit":commit,"working_tree_dirty":dirty,"captured_at":manifest["captured_at"]},
        "parameter_status":status,"calibration":{"synthesis":"synthesis_generic","physical":"synthetic","power":"synthetic","thermal":"synthetic_architectural","timing":"not_available","workload":"pending" if workload["status"]=="pending" else "workload_model"},
        "observations":observations,"block_metrics":block_metrics,
        "physical_totals":{"primary_observation":primary_name,"generic_cells":primary["generic_cells"] if primary else None,"technology_mapped_area_um2":primary["technology_mapped_area_um2"] if primary else None,"mapped_floorplan_area_um2":sum(x["mapped_area_um2"] for x in category.values()),
            "dynamic_power_W":sum(x["dynamic_power_W"] for x in category.values()),"leakage_power_W":sum(x["leakage_power_W"] for x in category.values()),"total_power_W":sum(x["total_power_W"] for x in category.values()),
            "critical_path_ns":primary["critical_path_ns"] if primary else None,"slack_ns":primary["slack_ns"] if primary else None,"note":"Alternative synthesis observations are not summed. primary_observation selects only the revision-under-test and does not finalize system architecture."},
        "thermal":{"peak_temperature_K":number(thermal["peak_temperature_K"],"peak temperature",False),"peak_delta_K":number(thermal["peak_delta_K"],"peak delta",False),"hotspot":thermal["hotspot"],"calibration":"synthetic_architectural"},
        "workload":workload_result,"categories":category,"source_files":sources,"notes":manifest.get("notes",[])}
    if abs(result["physical_totals"]["total_power_W"]-float(mapped["checks"]["mapped_power_W"]))>1e-12: raise CaptureError("category power does not conserve mapped power")
    out=path(output_path); out.parent.mkdir(parents=True,exist_ok=True); out.write_text(json.dumps(result,indent=2),encoding="utf-8"); print(f"HARDWARE_COST_SNAPSHOT PASS revision={manifest['revision_id']} output={out}"); return result

def main():
    ap=argparse.ArgumentParser(description=__doc__); ap.add_argument("--manifest",required=True); ap.add_argument("--output",required=True); a=ap.parse_args()
    try: capture(a.manifest,a.output)
    except (CaptureError,KeyError,OSError,json.JSONDecodeError,subprocess.CalledProcessError) as exc: print(f"ERROR: {exc}"); return 2
    return 0
if __name__=="__main__": raise SystemExit(main())
