#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
out="${TMPDIR:-/tmp}/normalization_writeback_quad_slice_tb.out"
iverilog -g2012 -s normalization_writeback_quad_slice_tb -o "$out" \
  rtl/normalization_writeback_quad_slice.sv \
  verification/groot_normalization/normalization_writeback_quad_slice_tb.sv
vvp "$out"
