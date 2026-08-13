#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)";cd "$root"
python3 tools/generate_fp32_mixed_precision_vectors.py
lr="${HOME}/.local/iverilog/usr";if command -v iverilog>/dev/null 2>&1;then iv="$(command -v iverilog)";vp="$(command -v vvp)";base="";else iv="${lr}/bin/iverilog";vp="${lr}/bin/vvp";base="$(find "${lr}/lib" -type d -name ivl -print -quit)";fi
out="${TMPDIR:-/tmp}/fp32_mixed_precision_primitives.out";args=(-g2012 -Wall -s fp32_mixed_precision_primitives_tb -o "$out");if [[ -n "$base" ]];then args=(-B "$base" "${args[@]}");fi
"$iv" "${args[@]}" rtl/bf16_to_fp32.sv rtl/fp32_to_bf16_rne.sv rtl/fp32_add.sv rtl/fp32_mul.sv verification/groot_normalization/fp32_mixed_precision_primitives_tb.sv
cmd=("$vp");if [[ -n "$base" ]];then cmd+=( -M "$base" );fi;cmd+=("$out");"${cmd[@]}"
