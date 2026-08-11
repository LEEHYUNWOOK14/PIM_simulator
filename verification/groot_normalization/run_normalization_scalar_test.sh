#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
iv="${HOME}/.local/iverilog/usr/bin/iverilog"
vvp="${HOME}/.local/iverilog/usr/bin/vvp"
base="$(find "${HOME}/.local/iverilog/usr/lib" -type d -name ivl -print -quit)"
cd "${repo_root}"
python3 tools/generate_fp16_rsqrt_rtl_assets.py
python3 tools/generate_normalization_scalar_vectors.py
"${iv}" -B "${base}" -g2012 -s logic_normalization_scalar_engine_tb \
  -o /tmp/logic_normalization_scalar_engine_tb.out \
  rtl/fp16_add.sv rtl/fp16_mul.sv rtl/fp16_rsqrt_lut256.sv \
  rtl/logic_normalization_scalar_engine.sv \
  verification/groot_normalization/logic_normalization_scalar_engine_tb.sv
"${vvp}" -M "${base}" /tmp/logic_normalization_scalar_engine_tb.out
