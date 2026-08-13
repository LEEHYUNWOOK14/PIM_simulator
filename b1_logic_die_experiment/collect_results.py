#!/usr/bin/env python3
"""Freeze the B1 experiment results into machine-readable tables and a manifest."""

from __future__ import annotations

import csv
import hashlib
import json
from datetime import datetime, timezone, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXP = ROOT / "b1_logic_die_experiment"
METRICS, LOGS = EXP / "metrics", EXP / "logs"
RESULTS = EXP / "orfs/results/sky130hd/b1_logic_die_baseline/base"
PLAN = ROOT / "reports/baseline_b1_logic_die_experiment_plan.html"

def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def write_csv(name: str, rows: list[dict]) -> None:
    with (METRICS / name).open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader(); writer.writerows(rows)

METRICS.mkdir(exist_ok=True); LOGS.mkdir(exist_ok=True)
(LOGS / "b1_detailed_route_failure_summary.txt").write_text("""B1 detailed-route terminal summary
stage: 5_2_route
exit_code: 1
elapsed_seconds: 379
last_progress: optimization iteration 0, 40 percent
violations_at_last_progress: 13497
last_logged_openroad_memory_mb: 4459.74
termination: Linux OOM killer terminated openroad
oom_total_vm_kb: 27717548
oom_anon_rss_kb: 21195172
oom_page_tables_kb: 53972
result_5_2_route_odb: absent
final_drc_antenna_gds: not produced

Kernel OOM values were captured immediately after the failed standalone run.
The original progress log is orfs_do-5_2_route.log.
""", encoding="utf-8")

timing_rows = [
    {"stage":"pre_layout","area_um2":702769.011199,"wns_ns":-48.76,"tns_ns":-115135.01,"clock_period_ns":10.0,"timing_met":"no"},
    {"stage":"post_place","area_um2":895637,"wns_ns":-44.00,"tns_ns":-144902.47,"clock_period_ns":10.0,"timing_met":"no"},
    {"stage":"post_cts","area_um2":948024,"wns_ns":-44.42,"tns_ns":-146424.12,"clock_period_ns":10.0,"timing_met":"no"},
    {"stage":"global_route","area_um2":948024,"wns_ns":-47.21,"tns_ns":-160819.12,"clock_period_ns":10.0,"timing_met":"no"},
]
write_csv("b1_synthesis_timing.csv", timing_rows)
physical_rows = [
    {"metric":"mapped_cells","value":56097,"unit":"cells","stage":"synthesis"},
    {"metric":"mapped_area","value":702769.011199,"unit":"um2","stage":"synthesis"},
    {"metric":"sequential_area","value":418575.1968,"unit":"um2","stage":"synthesis"},
    {"metric":"die_width","value":1534.545,"unit":"um","stage":"floorplan"},
    {"metric":"die_height","value":1534.545,"unit":"um","stage":"floorplan"},
    {"metric":"die_area","value":round(1534.545**2,6),"unit":"um2","stage":"floorplan"},
    {"metric":"core_area","value":2338758.054,"unit":"um2","stage":"floorplan"},
    {"metric":"final_place_utilization","value":38,"unit":"percent","stage":"place"},
    {"metric":"legalized_hpwl","value":4212992.9,"unit":"um","stage":"place"},
    {"metric":"cts_sinks","value":14058,"unit":"sinks","stage":"cts"},
    {"metric":"cts_buffers","value":1603,"unit":"buffers","stage":"cts"},
    {"metric":"cts_max_level","value":7,"unit":"levels","stage":"cts"},
    {"metric":"global_route_wirelength","value":6853970,"unit":"um","stage":"global_route"},
    {"metric":"global_route_vias","value":658010,"unit":"vias","stage":"global_route"},
    {"metric":"global_route_guides","value":712675,"unit":"guides","stage":"global_route"},
    {"metric":"global_route_resource_usage","value":47.46,"unit":"percent","stage":"global_route"},
    {"metric":"detailed_route_progress","value":40,"unit":"percent","stage":"detailed_route"},
    {"metric":"detailed_route_last_violations","value":13497,"unit":"violations","stage":"detailed_route"},
]
write_csv("b1_physical_metrics.csv", physical_rows)

latency_cycles, clock_ns, power_w = 41, 10.0, 0.742
latency_ns, logic_power_w = latency_cycles*clock_ns, 0.059789229999991075
power_rows = [
    {"metric":"work_latency","value":latency_cycles,"unit":"cycles","evidence":"direct RTL VCD/testbench"},
    {"metric":"target_clock","value":clock_ns,"unit":"ns","evidence":"constraint"},
    {"metric":"target_clock_latency","value":latency_ns,"unit":"ns/work","evidence":"derived; timing not closed"},
    {"metric":"target_clock_throughput","value":1e3/latency_ns,"unit":"Mwork/s","evidence":"derived; timing not closed"},
    {"metric":"mapped_total_power","value":power_w,"unit":"W","evidence":"VCD-derived aggregate input activity propagated"},
    {"metric":"logic_die_leaf_subset_power","value":logic_power_w,"unit":"W","evidence":"leaf subset; excludes shared/top clock"},
    {"metric":"target_clock_energy","value":power_w*latency_ns,"unit":"nJ/work","evidence":"estimated; timing not closed"},
    {"metric":"logic_die_leaf_subset_energy","value":logic_power_w*latency_ns,"unit":"nJ/work","evidence":"estimated subset; timing not closed"},
    {"metric":"direct_mapped_vcd_annotation","value":0,"unit":"pins","evidence":"direct annotation attempt"},
]
write_csv("b1_power_performance.csv", power_rows)
gate_rows = [
    {"gate":"G0","status":"PASS_WITH_DEFECT","result":"계획 구성·툴·제약 고정; 계획 축소 구성의 RTL 계약 충돌 발견"},
    {"gate":"G1","status":"PASS","result":"Logic-die hierarchy present; normalization hierarchy absent"},
    {"gate":"G2","status":"PASS","result":"generic synthesis 101095 cells"},
    {"gate":"G3","status":"FAIL_EXACT_CONFIG","result":"계획 구성은 assertion 실패; 수정된 유효 최소 구성과 회귀·formal은 통과"},
    {"gate":"G4","status":"PASS_REPORT_FAIL_TIMING","result":"Sky130 mapping 56097 cells, unmapped 0; WNS -48.76 ns"},
    {"gate":"G5","status":"PASS","result":"floorplan/place/legalization 완료"},
    {"gate":"G6","status":"PARTIAL","result":"CTS와 post-CTS STA 완료; 별도 skew query는 자원 한계로 미완료"},
    {"gate":"G7","status":"FAIL_RESOURCE","result":"global route 완료; detailed route 40%에서 OOM, DRC/antenna/GDS 없음"},
    {"gate":"G8","status":"PARTIAL_ESTIMATE","result":"공통 work trace 확보; 직접 mapped VCD annotation 0, 파생 activity 전력만 제공"},
    {"gate":"G9","status":"NOT_APPROVED","result":"정확 구성 기능 실패·timing 미달·route 미완료·동일 조건 B0 부재"},
]
write_csv("b1_gate_results.csv", gate_rows)

hash_targets = [PLAN, EXP/"configuration.txt", EXP/"constraint.sdc", EXP/"orfs_config.mk", EXP/"b1_hierarchical_tb.sv"]
hash_targets += [ROOT/item.strip() for item in (EXP/"sources.list").read_text(encoding="utf-8").splitlines() if item.strip()]
hash_targets += [EXP/"artifacts/B1_generic.v", EXP/"artifacts/b1_hierarchical.vcd", RESULTS/"1_2_yosys.v", RESULTS/"1_synth.odb", RESULTS/"3_place.odb", RESULTS/"4_cts.odb", RESULTS/"5_1_grt.odb", RESULTS/"route.guide", LOGS/"b1_detailed_route_failure_summary.txt"]
hash_rows=[]
for path in hash_targets:
    if path.exists():
        try: label=path.relative_to(ROOT).as_posix()
        except ValueError: label=str(path)
        hash_rows.append({"path":label,"bytes":path.stat().st_size,"sha256":sha256(path)})
write_csv("hash_manifest.csv", hash_rows)

manifest = {
 "experiment":"B1 hierarchical logic-die baseline", "generated_at":datetime.now(timezone(timedelta(hours=9))).isoformat(timespec="seconds"),
 "overall_disposition":"NOT_APPROVED", "reason":"Exact planned configuration is functionally invalid; 10 ns timing is not met; detailed route did not complete.",
 "plan":{"path":PLAN.relative_to(ROOT).as_posix(),"sha256":sha256(PLAN)},
 "configuration":{"top":"full_pim_system_top","features":{"ENABLE_LOGIC_DIE_PCU":1,"ENABLE_NORMALIZATION_ENGINE":0},
  "exact_plan_scale":{"CHANNELS":1,"BANKS":1,"PIM_BLOCKS":1,"PCUS":1,"ROWS":1,"COLS":1,"DATA_WIDTH":16,"CRF_DEPTH":2,"WEIGHT_BUFFER_BYTES":16},
  "functional_valid_scale":{"CHANNELS":1,"BANKS":2,"PIM_BLOCKS":1,"PCUS":1,"ROWS":1,"COLS":1,"DATA_WIDTH":32,"CRF_DEPTH":2,"WEIGHT_BUFFER_BYTES":16},
  "technology":"sky130hd","corner":"sky130_fd_sc_hd__tt_025C_1v80","clock_period_ns":10.0,"clock_uncertainty_ns":0.2},
 "tools":{"OpenROAD":"26Q3-1080-gab6fd26351","Yosys":"0.68+48 (ff5817c34-dirty)","simulator":"Icarus Verilog/vvp"},
 "functional":{"exact_plan":"EXPECTED_ASSERTION_FAILURE","contract_failures":["DATA_WIDTH must be divisible by 32","each PIM block requires an even/odd bank pair"],"valid_minimal_e2e":"PASS","cycles":latency_cycles,"work_id":"B1_HIERARCHICAL_41_CYCLE_TRACE","rtl_regressions":"PASS","router_formal":"PASS"},
 "synthesis":{"generic_cells":101095,"mapped_cells":56097,"mapped_area_um2":702769.011199,"unmapped_cells":0},
 "physical":{"timing":timing_rows,"detailed_route":{"status":"OOM","progress_percent":40,"last_violations":13497,"final_odb":False,"gds":False}},
 "power_performance":{"evidence_level":"ESTIMATED_VCD_DERIVED_INPUT_ACTIVITY_PROPAGATED","total_power_w":power_w,"latency_cycles":latency_cycles,"target_clock_throughput_mwork_s":1e3/latency_ns,"energy_nj_work":power_w*latency_ns,"timing_closed":False},
 "comparison":{"generic_B0_cells":14945,"generic_B1_cells":101095,"cell_delta":86150,"cell_delta_percent":576.45,"physical_comparison_approved":False,"reason":"Available B0 physical run uses BANKS=2/DATA_WIDTH=32 while exact-plan B1 uses BANKS=1/DATA_WIDTH=16."},
 "gates":gate_rows,"hash_manifest":"metrics/hash_manifest.csv"}
(EXP/"b1_baseline_manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print(f"wrote {len(hash_rows)} hashes, {len(gate_rows)} gates")
