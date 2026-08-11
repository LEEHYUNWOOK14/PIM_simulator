#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "$root"
iv="${HOME}/.local/iverilog/usr/bin/iverilog";vvp="${HOME}/.local/iverilog/usr/bin/vvp";base="$(find "${HOME}/.local/iverilog/usr/lib" -type d -name ivl -print -quit)"
python3 tools/generate_fp16_rsqrt_rtl_assets.py
"$iv" -B "$base" -g2012 -s hierarchical_normalization_datapath_tb -o /tmp/hier_norm.out \
 rtl/fp16_add.sv rtl/fp16_mul.sv rtl/fp16_rsqrt_lut256.sv \
 rtl/bank_normalization_local_reducer.sv rtl/bank_normalization_apply.sv \
 rtl/logic_normalization_scalar_engine.sv rtl/logic_normalization_reduction_engine.sv \
 rtl/hierarchical_normalization_datapath.sv verification/groot_normalization/hierarchical_normalization_datapath_tb.sv
"$vvp" -M "$base" /tmp/hier_norm.out
