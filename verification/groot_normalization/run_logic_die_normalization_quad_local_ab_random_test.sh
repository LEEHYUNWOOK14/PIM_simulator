#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
out="${TMPDIR:-/tmp}/logic_die_normalization_quad_local_ab_random.out"
src=(
  rtl/bf16_to_fp32.sv rtl/fp32_to_bf16_rne.sv rtl/fp32_add.sv rtl/fp32_mul.sv
  rtl/fp32_add_pipe4.sv rtl/fp32_mul_pipe4.sv rtl/bf16_rsqrt_lut256.sv
  rtl/mixed_precision_bank_reducer_pingpong.sv rtl/mixed_precision_global_reducer16_pipe.sv
  rtl/mixed_precision_scalar_nr2_pipe.sv rtl/mixed_precision_scalar_engine_array.sv
  rtl/mixed_precision_bank_apply_pipe.sv rtl/mixed_precision_row_context_table.sv
  rtl/mixed_precision_multirow_datapath.sv rtl/normalization_bank_scheduler.sv
  rtl/logic_die_normalization_pcu_top.sv
  rtl/normalization_quad_local_bank_scheduler.sv
  rtl/mixed_precision_quad_local_multirow_datapath.sv
  rtl/logic_die_normalization_quad_local_pcu_top.sv
  rtl/normalization_hbm_quad_local_boundary_adapter.sv
  verification/groot_normalization/logic_die_normalization_quad_local_ab_random_tb.sv
)
iverilog -g2012 -Wall -s logic_die_normalization_quad_local_ab_random_tb \
  -P logic_die_normalization_quad_local_ab_random_tb.B2_REGISTERED_QUAD_COMPLETION="${B2_REGISTERED_QUAD_COMPLETION:-0}" \
  -o "$out" "${src[@]}"
vvp "$out"
