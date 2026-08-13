#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "$root";python3 tools/generate_fp32_mixed_precision_vectors.py
lr="${HOME}/.local/iverilog/usr";iv="${lr}/bin/iverilog";vp="${lr}/bin/vvp";base="$(find "${lr}/lib" -type d -name ivl -print -quit)";out="${TMPDIR:-/tmp}/fp32_add_pipe4.out"
"$iv" -B "$base" -g2012 -Wall -s fp32_add_pipe4_tb -o "$out" rtl/fp32_add_pipe4.sv verification/groot_normalization/fp32_add_pipe4_tb.sv
"$vp" -M "$base" "$out"
