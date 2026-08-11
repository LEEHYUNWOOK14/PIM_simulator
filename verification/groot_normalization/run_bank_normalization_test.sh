#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "$root"
iv="${HOME}/.local/iverilog/usr/bin/iverilog";vvp="${HOME}/.local/iverilog/usr/bin/vvp"
base="$(find "${HOME}/.local/iverilog/usr/lib" -type d -name ivl -print -quit)"
python3 tools/generate_bank_normalization_vectors.py
"$iv" -B "$base" -g2012 -s bank_normalization_engines_tb -o /tmp/bank_norm.out \
 rtl/fp16_add.sv rtl/fp16_mul.sv rtl/bank_normalization_local_reducer.sv \
 rtl/bank_normalization_apply.sv verification/groot_normalization/bank_normalization_engines_tb.sv
"$vvp" -M "$base" /tmp/bank_norm.out
