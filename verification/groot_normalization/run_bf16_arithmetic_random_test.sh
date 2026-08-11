#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
python3 tools/generate_bf16_arithmetic_vectors.py
iv="${HOME}/.local/iverilog/usr/bin/iverilog"
vvp="${HOME}/.local/iverilog/usr/bin/vvp"
base="$(find "${HOME}/.local/iverilog/usr/lib" -type d -name ivl -print -quit)"
out="${TMPDIR:-/tmp}/bf16_arithmetic_random.out"
"$iv" -B "$base" -g2012 -s bf16_arithmetic_random_tb -o "$out" \
  rtl/bf16_add.sv rtl/bf16_mul.sv \
  verification/groot_normalization/bf16_arithmetic_random_tb.sv
"$vvp" -M "$base" "$out"
