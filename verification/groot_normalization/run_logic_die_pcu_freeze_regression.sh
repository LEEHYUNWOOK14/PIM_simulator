#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)";cd "$root"
report_dir="reports/groot_normalization/rtl_freeze"
mkdir -p "$report_dir"
log="$report_dir/freeze_regression.log"
:>"$log"
run(){ echo "[RUN] $*"|tee -a "$log"; "$@" 2>&1|tee -a "$log"; }

run bash verification/groot_normalization/run_normalization_bank_scheduler_test.sh
run bash verification/groot_normalization/run_mixed_precision_context_full_wrap_test.sh
run bash verification/groot_normalization/run_mixed_precision_scalar_latency_test.sh
run bash verification/groot_normalization/run_mixed_precision_scalar_array_test.sh
run bash verification/groot_normalization/run_mixed_precision_multirow_test.sh
run bash verification/groot_normalization/run_logic_die_normalization_pcu_top_test.sh
run bash verification/groot_normalization/run_rmsnorm_logic_die_pcu_trace_test.sh 2
run bash verification/groot_normalization/run_adalayernorm_logic_die_pcu_trace_test.sh
run bash verification/groot_normalization/run_groot_logic_die_pcu_trace_test.sh 4 action_dit_norm_out 4 8 16
run bash verification/groot_normalization/run_groot_logic_die_pcu_trace_test.sh 8 action_dit_norm_out 4 8 16
run python3 -m unittest verification/groot_normalization/test_logic_die_pcu_system.py
run python3 tools/analyze_logic_die_pcu_system.py --out reports/groot_normalization/results/logic_die_pcu_system_scheduler

src=(rtl/bf16_to_fp32.sv rtl/fp32_to_bf16_rne.sv rtl/fp32_add.sv rtl/fp32_mul.sv
  rtl/fp32_add_pipe4.sv rtl/fp32_mul_pipe4.sv rtl/bf16_rsqrt_lut256.sv
  rtl/mixed_precision_bank_reducer_pingpong.sv rtl/mixed_precision_global_reducer16_pipe.sv
  rtl/mixed_precision_scalar_nr2_pipe.sv rtl/mixed_precision_scalar_engine_array.sv
  rtl/mixed_precision_bank_apply_pipe.sv rtl/mixed_precision_row_context_table.sv
  rtl/mixed_precision_multirow_datapath.sv rtl/normalization_bank_scheduler.sv
  rtl/logic_die_normalization_pcu_top.sv)
run verilator --lint-only -Wall -Wno-fatal --top-module logic_die_normalization_pcu_top "${src[@]}"
echo "[RUN] yosys generic structural synthesis"|tee -a "$log"
yosys -p "read_verilog -sv ${src[*]}; hierarchy -top logic_die_normalization_pcu_top; proc; opt; check; stat" \
  2>&1|tee "$report_dir/yosys_generic_synthesis.log"|tee -a "$log"
echo "LOGIC_DIE_PCU_FREEZE_REGRESSION PASS"|tee -a "$log"
run python3 verification/groot_normalization/audit_logic_die_pcu_freeze.py
