#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "$root";lr="${HOME}/.local/iverilog/usr";iv="${lr}/bin/iverilog";vp="${lr}/bin/vvp";base="$(find "${lr}/lib" -type d -name ivl -print -quit)"
src=(rtl/bf16_to_fp32.sv rtl/fp32_to_bf16_rne.sv rtl/fp32_add.sv rtl/fp32_mul.sv rtl/fp32_add_pipe4.sv rtl/fp32_mul_pipe4.sv rtl/mixed_precision_bank_apply4_pipe.sv rtl/mixed_precision_bank_apply_pipe.sv verification/groot_normalization/mixed_precision_generic_apply_tb.sv)
for lanes in 4 8 16;do out="${TMPDIR:-/tmp}/mixed_precision_generic_apply_${lanes}.out";"$iv" -B "$base" -g2012 -Wall -s mixed_precision_generic_apply_tb -P mixed_precision_generic_apply_tb.LANES="$lanes" -o "$out" "${src[@]}";"$vp" -M "$base" "$out";done
