#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workspace="${repo_root}/b0_baseline_experiment"
result_dir="${workspace}/results/functional"
mkdir -p "${result_dir}"
cd "${repo_root}"

iverilog_bin="$(command -v iverilog)"
vvp_bin="$(command -v vvp)"
compile_log="${result_dir}/b0_compile.log"
run_log="${result_dir}/b0_run.log"

sources=(
  rtl/pim_command_decoder.sv rtl/fp16_add.sv rtl/fp16_mul.sv
  rtl/fp16_vector_add.sv rtl/pim_vector_alu.sv rtl/pim_crf.sv
  rtl/dram_bank_array_model.sv rtl/bank_pim_core.sv rtl/bank_side_pim_subsystem.sv
  rtl/logic_die_link_arbiter.sv rtl/channel_tsv_interconnect.sv
  rtl/logic_epoch_barrier.sv rtl/logic_shared_buffer.sv rtl/logic_pcu.sv
  rtl/logic_pcu_scheduler.sv rtl/logic_command_coalescer.sv
  rtl/logic_operand_context_buffer.sv rtl/cross_channel_reduction_network.sv
  rtl/logic_result_router.sv rtl/logic_die_pim_top.sv rtl/fp16_rsqrt_lut256.sv
  rtl/logic_normalization_scalar_engine.sv rtl/logic_normalization_reduction_engine.sv
  rtl/full_pim_system_top.sv b0_baseline_experiment/tb/b0_full_pim_system_tb.sv
)

"${iverilog_bin}" -g2012 -s b0_full_pim_system_tb -o "${result_dir}/b0_full_pim_system_tb.out" "${sources[@]}" >"${compile_log}" 2>&1
"${vvp_bin}" "${result_dir}/b0_full_pim_system_tb.out" >"${run_log}" 2>&1
grep -q "B0_FULL_PIM_SYSTEM_TB PASS" "${run_log}"

cat >"${result_dir}/b0_functional_results.csv" <<EOF
test,status,configuration,checks,log,vcd
b0_full_pim_system_tb,PASS,1ch_2bank_1pcu_dw32_logic0_norm0,"bank_add;route0_direct;route1_bypass;logic_idle;normalization_idle;protocol_error_zero",b0_run.log,b0_activity.vcd
EOF
printf 'B0-G3 PASS log=%s vcd=%s\n' "${run_log}" "${result_dir}/b0_activity.vcd"
