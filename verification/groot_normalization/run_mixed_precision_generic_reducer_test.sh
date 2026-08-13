#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "$root";lr="${HOME}/.local/iverilog/usr";iv="${lr}/bin/iverilog";vp="${lr}/bin/vvp";base="$(find "${lr}/lib" -type d -name ivl -print -quit)"
for lanes in 4 8 16;do out="${TMPDIR:-/tmp}/mixed_precision_generic_reducer_${lanes}.out";"$iv" -B "$base" -g2012 -Wall -s mixed_precision_generic_reducer_tb -P mixed_precision_generic_reducer_tb.LANES="$lanes" -o "$out" rtl/bf16_to_fp32.sv rtl/fp32_mul.sv rtl/fp32_add_pipe4.sv rtl/mixed_precision_bank_reducer_interleaved.sv verification/groot_normalization/mixed_precision_generic_reducer_tb.sv;"$vp" -M "$base" "$out";done
