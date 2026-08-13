#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
src=(
  rtl/bf16_to_fp32.sv rtl/fp32_to_bf16_rne.sv rtl/fp32_add.sv rtl/fp32_mul.sv
  rtl/fp32_add_pipe4.sv rtl/fp32_mul_pipe4.sv rtl/bf16_rsqrt_lut256.sv
  rtl/mixed_precision_bank_reducer_pingpong.sv rtl/mixed_precision_global_reducer16_pipe.sv
  rtl/mixed_precision_scalar_nr2_pipe.sv rtl/mixed_precision_scalar_engine_array.sv
  rtl/mixed_precision_bank_apply_pipe.sv rtl/mixed_precision_row_context_table.sv
  rtl/mixed_precision_multirow_datapath.sv rtl/normalization_bank_scheduler.sv
  rtl/logic_die_normalization_pcu_top.sv rtl/normalization_hbm_boundary_adapter.sv
  rtl/normalization_writeback_quad_slice.sv
  rtl/dram_bank_array_model.sv
  verification/groot_normalization/normalization_hbm_boundary_integration_tb.sv
)
for mode in 0 1; do
  for width in 128 2048; do
    out="${TMPDIR:-/tmp}/normalization_hbm_boundary_m${mode}_w${width}.out"
    iverilog -g2012 -Wall -s normalization_hbm_boundary_integration_tb \
      -P normalization_hbm_boundary_integration_tb.WIDTH="$width" \
      -P normalization_hbm_boundary_integration_tb.RMS_MODE="$mode" \
      -o "$out" "${src[@]}"
    vvp "$out"
  done
done
