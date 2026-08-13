#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)";cd "$root"
out="${TMPDIR:-/tmp}/mixed_precision_context_full_wrap.out"
iverilog -g2012 -Wall -s mixed_precision_context_full_wrap_tb -o "$out" \
  rtl/mixed_precision_row_context_table.sv \
  verification/groot_normalization/mixed_precision_context_full_wrap_tb.sv
vvp "$out"
