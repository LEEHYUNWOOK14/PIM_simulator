#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
iv="${HOME}/.local/iverilog/usr/bin/iverilog"
vvp="${HOME}/.local/iverilog/usr/bin/vvp"
base="$(find "${HOME}/.local/iverilog/usr/lib" -type d -name ivl -print -quit)"
out="${TMPDIR:-/tmp}/normalization_interface_contract.out"
"$iv" -B "$base" -g2012 -s normalization_interface_contract_tb -o "$out" \
  rtl/fp16_add.sv rtl/fp16_mul.sv rtl/bank_normalization_apply.sv \
  verification/groot_normalization/normalization_interface_contract_tb.sv
"$vvp" -M "$base" "$out"
