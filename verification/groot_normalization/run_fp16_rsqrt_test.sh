#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
iv="${HOME}/.local/iverilog/usr/bin/iverilog"
vvp="${HOME}/.local/iverilog/usr/bin/vvp"
base="$(find "${HOME}/.local/iverilog/usr/lib" -type d -name ivl -print -quit)"
cd "${repo_root}"
python3 tools/generate_fp16_rsqrt_rtl_assets.py
"${iv}" -B "${base}" -g2012 -s fp16_rsqrt_lut256_tb -o /tmp/fp16_rsqrt_lut256_tb.out \
  rtl/fp16_rsqrt_lut256.sv verification/groot_normalization/fp16_rsqrt_lut256_tb.sv
"${vvp}" -M "${base}" /tmp/fp16_rsqrt_lut256_tb.out
