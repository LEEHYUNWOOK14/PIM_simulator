#!/usr/bin/env python3
"""Requirement-by-requirement audit for the frozen normalization PCU RTL."""
from __future__ import annotations
import csv,json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
REPORT=ROOT/"reports/groot_normalization/rtl_freeze"
RESULT=ROOT/"reports/groot_normalization/results"

def csv_rows(path):
    with path.open(encoding="utf-8") as stream:return list(csv.DictReader(stream))

def main():
    status=json.loads((REPORT/"freeze_status.json").read_text(encoding="utf-8"))
    assert status["status"]=="PASS_RTL_FROZEN"
    assert status["configuration"]=={
      "bank_policy":"split_rw","read_arbitration":"round_robin","lanes":8,
      "scalar_engines":4,"contexts":8,"local_reduction_contexts":2,
      "apply_fifo_depth":16,"traffic_counter_width":32}
    assert status["required_work_remaining_in_scope"]==[]

    log=(REPORT/"freeze_regression.log").read_text(encoding="utf-8",errors="replace")
    required=(
      "LOGIC_DIE_PCU_FREEZE_REGRESSION PASS",
      "NORMALIZATION_BANK_SCHEDULER_TB PASS shared=0 random_bp_cycles=128",
      "MIXED_PRECISION_CONTEXT_FULL_WRAP_TB PASS",
      "reset_mid_transaction=1",
      "RMSNORM_VECTORS PASS cases=2",
      "ADALAYERNORM_VECTORS PASS",
      "lanes=4 engines=4 local_reduce_contexts=2 top_contexts=8 fifo=16",
      "lanes=8 engines=4 local_reduce_contexts=2 top_contexts=8 fifo=16",
      "Ran 5 tests",
      "recommended_lanes=8",
    )
    missing=[item for item in required if item not in log]
    assert not missing,f"freeze log missing evidence: {missing}"
    assert "Warning-UNOPTFLAT" not in log
    synth=(REPORT/"yosys_generic_synthesis.log").read_text(encoding="utf-8",errors="replace")
    assert "Found and reported 0 problems." in synth

    rms=csv_rows(RESULT/"rmsnorm_l8_vectors/numerical_accuracy.csv")
    ada=csv_rows(RESULT/"adalayernorm_l8_vectors/accuracy.csv")
    assert {int(row["hidden_size"]) for row in rms}=={128,2048}
    assert all(int(row["bit_mismatches"])==0 and float(row["max_abs"])==0 for row in rms+ada)

    decision=json.loads((RESULT/"logic_die_pcu_system_scheduler/system_decision.json").read_text(encoding="utf-8"))
    choice=decision["candidate_decision"]
    assert choice["recommended_knee_lanes"]==8
    assert choice["minimum_bank_supply_fraction"]==0.5
    assert choice["freeze_status"]=="FROZEN_8_LANES_SPLIT_RW_CONTEXTS8_FIFO16"

    top=(ROOT/"rtl/logic_die_normalization_pcu_top.sv").read_text(encoding="utf-8")
    scheduler=(ROOT/"rtl/normalization_bank_scheduler.sv").read_text(encoding="utf-8")
    assert "u_bank_scheduler" in top and "SHARED_RW_PORT = 1'b0" in top
    assert "reduction_grant = !read_rr_q" in scheduler
    assert (REPORT/"01_final_rtl_freeze_report.md").exists()
    print("LOGIC_DIE_PCU_FREEZE_AUDIT PASS requirements=12 configuration=8lane_split_rw_c8_fifo16")
    return 0
if __name__=="__main__":raise SystemExit(main())
