#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
iv="${HOME}/.local/iverilog/usr/bin/iverilog"
vvp="${HOME}/.local/iverilog/usr/bin/vvp"
base="$(find "${HOME}/.local/iverilog/usr/lib" -type d -name ivl -print -quit)"
[[ -x "${iv}" && -x "${vvp}" ]] || { echo "local Icarus not found" >&2; exit 1; }
cd "${repo_root}"
common=(-B "${base}" -g2012)
"${iv}" "${common[@]}" -s logic_die_link_arbiter_tb -o /tmp/logic_die_link_arbiter_tb.out \
  rtl/logic_die_link_arbiter.sv rtl/tb/logic_die_link_arbiter_tb.sv
"${vvp}" -M "${base}" /tmp/logic_die_link_arbiter_tb.out
"${iv}" "${common[@]}" -s pim_vector_alu_tb -o /tmp/pim_vector_alu_tb.out \
  rtl/pim_rtl_pkg.sv rtl/fp16_add.sv rtl/fp16_mul.sv rtl/pim_vector_alu.sv \
  rtl/tb/pim_vector_alu_tb.sv
"${vvp}" -M "${base}" /tmp/pim_vector_alu_tb.out
"${iv}" "${common[@]}" -s dram_bank_array_model_tb -o /tmp/dram_bank_array_model_tb.out \
  rtl/pim_rtl_pkg.sv rtl/dram_bank_array_model.sv rtl/tb/dram_bank_array_model_tb.sv
"${vvp}" -M "${base}" /tmp/dram_bank_array_model_tb.out
"${iv}" "${common[@]}" -s bank_side_pim_subsystem_tb -o /tmp/bank_side_pim_subsystem_tb.out \
  rtl/pim_rtl_pkg.sv rtl/pim_command_decoder.sv rtl/fp16_add.sv rtl/fp16_mul.sv \
  rtl/pim_vector_alu.sv rtl/pim_crf.sv rtl/dram_bank_array_model.sv rtl/bank_pim_core.sv \
  rtl/bank_side_pim_subsystem.sv rtl/tb/bank_side_pim_subsystem_tb.sv
"${vvp}" -M "${base}" /tmp/bank_side_pim_subsystem_tb.out
"${iv}" "${common[@]}" -s logic_die_pim_top_tb -o /tmp/logic_die_pim_top_tb.out \
  rtl/pim_rtl_pkg.sv rtl/fp16_add.sv rtl/fp16_mul.sv rtl/pim_vector_alu.sv \
  rtl/logic_pcu.sv rtl/logic_pcu_scheduler.sv rtl/logic_command_coalescer.sv \
  rtl/logic_epoch_barrier.sv rtl/logic_shared_buffer.sv \
  rtl/logic_operand_context_buffer.sv rtl/fp16_vector_add.sv \
  rtl/cross_channel_reduction_network.sv rtl/logic_die_pim_top.sv rtl/tb/logic_die_pim_top_tb.sv
"${vvp}" -M "${base}" /tmp/logic_die_pim_top_tb.out
"${iv}" "${common[@]}" -s logic_control_network_tb -o /tmp/logic_control_network_tb.out \
  rtl/fp16_add.sv rtl/fp16_vector_add.sv rtl/logic_epoch_barrier.sv \
  rtl/logic_shared_buffer.sv rtl/cross_channel_reduction.sv \
  rtl/channel_tsv_interconnect.sv rtl/tb/logic_control_network_tb.sv
"${vvp}" -M "${base}" /tmp/logic_control_network_tb.out
"${iv}" "${common[@]}" -s logic_pcu_scheduler_16_tb -o /tmp/logic_pcu_scheduler_16_tb.out \
  rtl/pim_rtl_pkg.sv rtl/fp16_add.sv rtl/fp16_mul.sv rtl/pim_vector_alu.sv \
  rtl/logic_pcu.sv rtl/logic_pcu_scheduler.sv rtl/tb/logic_pcu_scheduler_16_tb.sv
"${vvp}" -M "${base}" /tmp/logic_pcu_scheduler_16_tb.out
"${iv}" "${common[@]}" -s full_pim_system_top_tb -o /tmp/full_pim_system_top_tb.out \
  rtl/pim_rtl_pkg.sv rtl/pim_command_decoder.sv rtl/fp16_add.sv rtl/fp16_mul.sv \
  rtl/pim_vector_alu.sv rtl/pim_crf.sv rtl/dram_bank_array_model.sv rtl/bank_pim_core.sv \
  rtl/bank_side_pim_subsystem.sv rtl/logic_die_link_arbiter.sv rtl/channel_tsv_interconnect.sv \
  rtl/logic_epoch_barrier.sv rtl/logic_shared_buffer.sv rtl/logic_pcu.sv \
  rtl/logic_pcu_scheduler.sv rtl/logic_command_coalescer.sv \
  rtl/logic_operand_context_buffer.sv rtl/fp16_vector_add.sv \
  rtl/cross_channel_reduction_network.sv rtl/logic_result_router.sv rtl/logic_die_pim_top.sv \
  rtl/fp16_rsqrt_lut256.sv rtl/logic_normalization_scalar_engine.sv \
  rtl/logic_normalization_reduction_engine.sv \
  rtl/full_pim_system_top.sv rtl/tb/full_pim_system_top_tb.sv
"${vvp}" -M "${base}" /tmp/full_pim_system_top_tb.out
"${iv}" "${common[@]}" -s logic_die_random_stress_tb -o /tmp/logic_die_random_stress_tb.out \
  rtl/pim_rtl_pkg.sv rtl/fp16_add.sv rtl/fp16_mul.sv rtl/pim_vector_alu.sv \
  rtl/logic_epoch_barrier.sv rtl/logic_shared_buffer.sv rtl/logic_pcu.sv \
  rtl/logic_pcu_scheduler.sv rtl/logic_command_coalescer.sv \
  rtl/logic_operand_context_buffer.sv rtl/fp16_vector_add.sv \
  rtl/cross_channel_reduction_network.sv rtl/logic_die_pim_top.sv \
  rtl/tb/logic_die_random_stress_tb.sv
"${vvp}" -M "${base}" /tmp/logic_die_random_stress_tb.out
