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
  rtl/normalization_quad_local_bank_scheduler.sv
  rtl/mixed_precision_quad_local_multirow_datapath.sv
  rtl/logic_die_normalization_quad_local_pcu_top.sv
  rtl/normalization_hbm_quad_local_boundary_adapter.sv
  rtl/normalization_writeback_quad_slice.sv
  rtl/logic_die_normalization_hbm_top.sv
  rtl/logic_die_normalization_hbm_quad_local_ab_top.sv
  rtl/logic_die_normalization_hbm_quad_local_b2_top.sv
  rtl/dram_bank_array_model.sv
  verification/groot_normalization/normalization_hbm_boundary_integration_tb.sv
)
for variant in ${VARIANTS:-0 1}; do
  for mode in ${RMS_MODES:-0 1}; do
    for width in ${WIDTHS:-128 2048}; do
      out="${TMPDIR:-/tmp}/normalization_hbm_boundary_v${variant}_m${mode}_w${width}.out"
      iverilog -g2012 -Wall -s normalization_hbm_boundary_integration_tb \
        -P normalization_hbm_boundary_integration_tb.WIDTH="$width" \
        -P normalization_hbm_boundary_integration_tb.RMS_MODE="$mode" \
        -P normalization_hbm_boundary_integration_tb.QUAD_LOCAL_AB="$variant" \
        -P normalization_hbm_boundary_integration_tb.B2_REGISTERED_QUAD_COMPLETION="${B2_REGISTERED_QUAD_COMPLETION:-0}" \
        -o "$out" "${src[@]}"
      vvp "$out"
    done
  done
done

# Elaborate the integrated B top itself so its external contract and all
# internal port connections are checked even though the functional regression
# above drives the boundary components directly for richer counter assertions.
if [[ "${B2_REGISTERED_QUAD_COMPLETION:-0}" == 1 ]]; then
  integrated_top=logic_die_normalization_hbm_quad_local_b2_top
else
  integrated_top=logic_die_normalization_hbm_quad_local_ab_top
fi
iverilog -g2012 -Wall -s "$integrated_top" \
  -o "${TMPDIR:-/tmp}/${integrated_top}.out" \
  "${src[@]}"
echo "NORMALIZATION_HBM_QUAD_LOCAL_AB_TOP ELABORATION PASS top=$integrated_top"
