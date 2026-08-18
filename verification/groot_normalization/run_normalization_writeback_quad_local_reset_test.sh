#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
out="${TMPDIR:-/tmp}/normalization_writeback_quad_local_reset.out"
iverilog -g2012 -Wall -s normalization_writeback_quad_local_reset_tb -o "$out" \
  rtl/normalization_hbm_quad_local_boundary_adapter.sv \
  rtl/normalization_writeback_quad_slice.sv \
  verification/groot_normalization/normalization_writeback_quad_local_reset_tb.sv
vvp "$out"
