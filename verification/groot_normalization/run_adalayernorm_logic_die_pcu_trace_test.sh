#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)";cd "$root"
if python3 -c 'import numpy' 2>/dev/null;then python3 tools/prepare_adalayernorm_rtl_vectors.py;else "/mnt/c/Program Files/Python313/python.exe" "$(wslpath -w tools/prepare_adalayernorm_rtl_vectors.py)";fi
vectors="reports/groot_normalization/results/adalayernorm_l8_vectors";results="reports/groot_normalization/results/adalayernorm_l8_results";mkdir -p "$results"
out="${TMPDIR:-/tmp}/adalayernorm_logic_die_pcu_l8.out"
src=(rtl/bf16_to_fp32.sv rtl/fp32_to_bf16_rne.sv rtl/fp32_add.sv rtl/fp32_mul.sv rtl/fp32_add_pipe4.sv rtl/fp32_mul_pipe4.sv rtl/bf16_rsqrt_lut256.sv rtl/mixed_precision_bank_reducer_pingpong.sv rtl/mixed_precision_global_reducer16_pipe.sv rtl/mixed_precision_scalar_nr2_pipe.sv rtl/mixed_precision_scalar_engine_array.sv rtl/mixed_precision_bank_apply_pipe.sv rtl/mixed_precision_row_context_table.sv rtl/mixed_precision_multirow_datapath.sv rtl/normalization_bank_scheduler.sv rtl/logic_die_normalization_pcu_top.sv verification/groot_normalization/groot_logic_die_pcu_trace_tb.sv)
iverilog -g2012 -Wall -s groot_logic_die_pcu_trace_tb -P groot_logic_die_pcu_trace_tb.L=8 -o "$out" "${src[@]}"
vvp "$out" +RMS=0 +AFFINE_PER_ROW=1 +PROFILE=adaln_w128 +ROWS=8 +HIDDEN=128 +VECTORS=1 +INVH=3c000000 +EPS=3727c5ac \
  "+X=$vectors/adaln_w128_x.hex" "+GAMMA=$vectors/adaln_w128_gamma.hex" "+BETA=$vectors/adaln_w128_beta.hex" \
  "+MIXED=$vectors/adaln_w128_mixed_expected.hex" "+PYTORCH=$vectors/adaln_w128_reference_expected.hex" \
  "+ACTUAL=$results/adaln_w128_actual.hex"|tee "$results/rtl_runs.log"
