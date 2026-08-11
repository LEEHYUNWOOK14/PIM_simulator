#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
iv="${HOME}/.local/iverilog/usr/bin/iverilog"
vvp="${HOME}/.local/iverilog/usr/bin/vvp"
base="$(find "${HOME}/.local/iverilog/usr/lib" -type d -name ivl -print -quit)"
cd "${repo_root}"
common=(-B "${base}" -g2012)
bank_sources=(rtl/pim_rtl_pkg.sv rtl/pim_command_decoder.sv rtl/fp16_add.sv
  rtl/fp16_mul.sv rtl/pim_vector_alu.sv rtl/pim_crf.sv
  rtl/dram_bank_array_model.sv rtl/bank_pim_core.sv rtl/bank_side_pim_subsystem.sv)

g++ -std=c++17 -I"${repo_root}/lib" \
  verification/rtl_audit/generate_fp16_mul_vectors.cpp -o /tmp/gen_fp16
/tmp/gen_fp16 /tmp/audit_fp16_mul_vectors.txt
"${iv}" "${common[@]}" -s fp16_mul_random_audit_tb -o /tmp/fp16_audit \
  rtl/fp16_mul.sv verification/rtl_audit/fp16_mul_random_audit_tb.sv
"${vvp}" -M "${base}" /tmp/fp16_audit

for tb in bank_operand_validity_repro invalid_crf_deadlock_repro; do
  "${iv}" "${common[@]}" -s "${tb}_tb" -o "/tmp/${tb}" \
    "${bank_sources[@]}" "verification/rtl_audit/${tb}_tb.sv"
  "${vvp}" -M "${base}" "/tmp/${tb}"
done

"${iv}" "${common[@]}" -s dram_read_backpressure_repro_tb -o /tmp/dram_fix \
  rtl/pim_rtl_pkg.sv rtl/dram_bank_array_model.sv \
  verification/rtl_audit/dram_read_backpressure_repro_tb.sv
"${vvp}" -M "${base}" /tmp/dram_fix

"${iv}" "${common[@]}" -s dram_extended_timing_tb -o /tmp/dram_timing_fix \
  rtl/pim_rtl_pkg.sv rtl/dram_bank_array_model.sv \
  verification/rtl_audit/dram_extended_timing_tb.sv
"${vvp}" -M "${base}" /tmp/dram_timing_fix

"${iv}" "${common[@]}" -s crf_jump_repro_tb -o /tmp/jump_fix \
  rtl/pim_crf.sv verification/rtl_audit/crf_jump_repro_tb.sv
"${vvp}" -M "${base}" /tmp/jump_fix

"${iv}" "${common[@]}" -s crf_repeat_semantics_tb -o /tmp/repeat_fix \
  rtl/pim_crf.sv verification/rtl_audit/crf_repeat_semantics_tb.sv
"${vvp}" -M "${base}" /tmp/repeat_fix

"${iv}" "${common[@]}" -s logic_tag_channel_repro_tb -o /tmp/logic_fix \
  rtl/pim_rtl_pkg.sv rtl/fp16_add.sv rtl/fp16_mul.sv rtl/pim_vector_alu.sv \
  rtl/logic_pcu.sv rtl/logic_pcu_scheduler.sv rtl/logic_command_coalescer.sv \
  rtl/logic_epoch_barrier.sv rtl/logic_shared_buffer.sv \
  rtl/logic_operand_context_buffer.sv rtl/fp16_vector_add.sv \
  rtl/cross_channel_reduction_network.sv rtl/logic_die_pim_top.sv \
  verification/rtl_audit/logic_tag_channel_repro_tb.sv
"${vvp}" -M "${base}" /tmp/logic_fix
