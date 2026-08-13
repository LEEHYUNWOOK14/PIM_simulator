#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "$root"
py="${GROOT_PYTHON:-}";if [[ -z "$py" && -x /home/chandler/.cache/stob-groot-runtime/bin/python ]];then py=/home/chandler/.cache/stob-groot-runtime/bin/python;elif [[ -z "$py" ]];then py=python3;fi
"$py" tools/evaluate_groot_mixed_precision_stress.py
lr="${HOME}/.local/iverilog/usr";if command -v iverilog>/dev/null 2>&1;then iv="$(command -v iverilog)";vp="$(command -v vvp)";base="";else iv="${lr}/bin/iverilog";vp="${lr}/bin/vvp";base="$(find "${lr}/lib" -type d -name ivl -print -quit)";fi
out="${TMPDIR:-/tmp}/mixed_precision_stress.out";args=(-g2012 -Wall -I. -s groot_mixed_precision_trace_tb -o "$out");if [[ -n "$base" ]];then args=(-B "$base" "${args[@]}");fi
src=(rtl/bf16_to_fp32.sv rtl/fp32_to_bf16_rne.sv rtl/fp32_add.sv rtl/fp32_mul.sv rtl/bf16_rsqrt_lut256.sv rtl/mixed_precision_bank_reducer4.sv rtl/mixed_precision_global_reducer16.sv rtl/mixed_precision_scalar_nr2.sv rtl/mixed_precision_bank_apply4.sv rtl/mixed_precision_normalization_datapath.sv verification/groot_normalization/groot_mixed_precision_trace_tb.sv)
"$iv" "${args[@]}" "${src[@]}";v=reports/groot_normalization/results/mixed_precision_stress_vectors;r=reports/groot_normalization/results/mixed_precision_rtl_results;cmd=("$vp");if [[ -n "$base" ]];then cmd+=( -M "$base" );fi
cmd+=("$out" +PROFILE=mixed_precision_stress +ROWS=9 +HIDDEN=64 +VECTORS=1 +INVH=3c800000 +EPS=3727c5ac "+MEANS=$v/stress_mean_fp32.hex" "+INVS=$v/stress_inv_std_fp32.hex" "+X=$v/stress_x.hex" "+GAMMA=$v/stress_gamma.hex" "+BETA=$v/stress_beta.hex" "+MIXED=$v/stress_mixed_expected.hex" "+PYTORCH=$v/stress_pytorch_expected.hex" "+ACTUAL=$r/mixed_precision_stress_actual.hex");"${cmd[@]}"
