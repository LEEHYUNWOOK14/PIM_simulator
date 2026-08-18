#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
out="${TMPDIR:-/tmp}/mixed_precision_quad_reduction_bitexact.out"
iverilog -g2012 -Wall -s mixed_precision_quad_reduction_bitexact_tb -o "$out" \
  rtl/fp32_add_pipe4.sv \
  rtl/mixed_precision_global_reducer16_pipe.sv \
  rtl/mixed_precision_quad_local_multirow_datapath.sv \
  verification/groot_normalization/mixed_precision_quad_reduction_bitexact_tb.sv
vvp "$out"
