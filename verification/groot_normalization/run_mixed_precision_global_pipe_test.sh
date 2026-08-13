#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "$root";lr="${HOME}/.local/iverilog/usr";iv="$lr/bin/iverilog";vp="$lr/bin/vvp";base="$(find "$lr/lib" -type d -name ivl -print -quit)";out="${TMPDIR:-/tmp}/mixed_global_pipe.out"
"$iv" -B "$base" -g2012 -Wall -s mixed_precision_global_pipe_tb -o "$out" rtl/fp32_add_pipe4.sv rtl/mixed_precision_global_reducer16_pipe.sv verification/groot_normalization/mixed_precision_global_pipe_tb.sv
"$vp" -M "$base" "$out"
