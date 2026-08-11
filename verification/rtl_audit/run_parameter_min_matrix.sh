#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
iv="${HOME}/.local/iverilog/usr/bin/iverilog"
base="$(find "${HOME}/.local/iverilog/usr/lib" -type d -name ivl -print -quit)"
cd "${repo_root}"
sources=(rtl/pim_rtl_pkg.sv rtl/pim_command_decoder.sv rtl/fp16_add.sv
  rtl/fp16_mul.sv rtl/fp16_vector_add.sv rtl/pim_vector_alu.sv rtl/pim_crf.sv
  rtl/dram_bank_array_model.sv rtl/bank_pim_core.sv rtl/bank_side_pim_subsystem.sv
  rtl/logic_die_link_arbiter.sv rtl/channel_tsv_interconnect.sv
  rtl/logic_epoch_barrier.sv rtl/logic_shared_buffer.sv rtl/logic_pcu.sv
  rtl/logic_pcu_scheduler.sv rtl/logic_command_coalescer.sv
  rtl/logic_operand_context_buffer.sv rtl/cross_channel_reduction_network.sv
  rtl/logic_result_router.sv rtl/logic_die_pim_top.sv rtl/fp16_rsqrt_lut256.sv
  rtl/logic_normalization_scalar_engine.sv rtl/logic_normalization_reduction_engine.sv
  rtl/full_pim_system_top.sv)
log=/tmp/aud011_parameter_matrix.log
: >"${log}"
"${iv}" -B "${base}" -g2012 -s full_pim_system_top -o /tmp/full_min.out \
  -Pfull_pim_system_top.CHANNELS=1 -Pfull_pim_system_top.BANKS=1 \
  -Pfull_pim_system_top.PIM_BLOCKS=1 -Pfull_pim_system_top.PCUS=1 \
  -Pfull_pim_system_top.ROWS=1 -Pfull_pim_system_top.COLS=1 \
  -Pfull_pim_system_top.CRF_DEPTH=2 -Pfull_pim_system_top.DATA_WIDTH=32 \
  "${sources[@]}" 2>"${log}"
"${iv}" -B "${base}" -g2012 -s logic_die_link_arbiter -o /tmp/arb_min.out \
  -Plogic_die_link_arbiter.INPUTS=1 rtl/logic_die_link_arbiter.sv 2>>"${log}"
"${iv}" -B "${base}" -g2012 -s logic_command_coalescer -o /tmp/coal_min.out \
  -Plogic_command_coalescer.CHANNELS=1 -Plogic_command_coalescer.ENTRIES=1 \
  rtl/logic_command_coalescer.sv 2>>"${log}"
if grep -Eqi 'expects [0-9]+ bits|padding|zero.width|part select.*out of order' "${log}"; then
  cat "${log}" >&2
  exit 1
fi
cat "${log}"
echo "AUDIT_FIX PASS: parameter=1 elaboration matrix has no width mismatch"
