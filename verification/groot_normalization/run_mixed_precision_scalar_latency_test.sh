#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)";cd "$root"
out="${TMPDIR:-/tmp}/mixed_precision_scalar_latency.out"
iverilog -g2012 -Wall -s mixed_precision_scalar_latency_tb -o "$out" \
  rtl/bf16_to_fp32.sv rtl/fp32_to_bf16_rne.sv rtl/fp32_add.sv rtl/fp32_mul.sv \
  rtl/fp32_add_pipe4.sv rtl/fp32_mul_pipe4.sv rtl/bf16_rsqrt_lut256.sv \
  rtl/mixed_precision_scalar_nr2_pipe.sv \
  verification/groot_normalization/mixed_precision_scalar_latency_tb.sv
vvp "$out"
