#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "$root"
lr="${HOME}/.local/iverilog/usr";if command -v iverilog>/dev/null 2>&1;then iv="$(command -v iverilog)";vp="$(command -v vvp)";base="";else iv="${lr}/bin/iverilog";vp="${lr}/bin/vvp";base="$(find "${lr}/lib" -type d -name ivl -print -quit)";fi
out="${TMPDIR:-/tmp}/mixed_precision_protocol.out";args=(-g2012 -Wall -I. -s mixed_precision_protocol_tb -o "$out");if [[ -n "$base" ]];then args=(-B "$base" "${args[@]}");fi
src=(rtl/bf16_to_fp32.sv rtl/fp32_to_bf16_rne.sv rtl/fp32_add.sv rtl/fp32_mul.sv rtl/bf16_rsqrt_lut256.sv rtl/mixed_precision_bank_reducer4.sv rtl/mixed_precision_global_reducer16.sv rtl/mixed_precision_scalar_nr2.sv rtl/mixed_precision_bank_apply4.sv rtl/mixed_precision_normalization_datapath.sv verification/groot_normalization/mixed_precision_protocol_tb.sv)
"$iv" "${args[@]}" "${src[@]}";cmd=("$vp");if [[ -n "$base" ]];then cmd+=( -M "$base" );fi;cmd+=("$out");"${cmd[@]}"
