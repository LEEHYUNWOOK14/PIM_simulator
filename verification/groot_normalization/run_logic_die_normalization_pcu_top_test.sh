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
  rtl/logic_die_normalization_pcu_top.sv
  verification/groot_normalization/logic_die_normalization_pcu_top_tb.sv
)
for lanes in 4 8 16; do
  out="${TMPDIR:-/tmp}/logic_die_normalization_pcu_l${lanes}.out"
  iverilog -g2012 -Wall -s logic_die_normalization_pcu_top_tb \
    -P logic_die_normalization_pcu_top_tb.LANES="$lanes" -o "$out" "${src[@]}"
  vvp "$out"
done
for width in 128 2048; do
  out="${TMPDIR:-/tmp}/logic_die_normalization_pcu_rms_l8_w${width}.out"
  iverilog -g2012 -Wall -s logic_die_normalization_pcu_top_tb \
    -P logic_die_normalization_pcu_top_tb.LANES=8 \
    -P logic_die_normalization_pcu_top_tb.RMS_MODE=1 \
    -P logic_die_normalization_pcu_top_tb.WIDTH="$width" -o "$out" "${src[@]}"
  vvp "$out"
done
