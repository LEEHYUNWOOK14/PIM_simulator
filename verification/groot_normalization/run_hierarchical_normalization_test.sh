#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "$root"
iv="${HOME}/.local/iverilog/usr/bin/iverilog";vvp="${HOME}/.local/iverilog/usr/bin/vvp";base="$(find "${HOME}/.local/iverilog/usr/lib" -type d -name ivl -print -quit)"
python3 tools/generate_fp16_rsqrt_rtl_assets.py
python3 tools/generate_bf16_rsqrt_rtl_assets.py
for format in 0 1;do
 out="/tmp/hier_norm_f${format}.out"
 "$iv" -B "$base" -g2012 -s hierarchical_normalization_datapath_tb \
  -Phierarchical_normalization_datapath_tb.DATA_FORMAT="${format}" -o "$out" \
  rtl/fp16_add.sv rtl/fp16_mul.sv rtl/bf16_add.sv rtl/bf16_mul.sv \
  rtl/fp16_rsqrt_lut256.sv rtl/bf16_rsqrt_lut256.sv \
  rtl/bank_normalization_local_reducer.sv rtl/bank_normalization_apply.sv \
  rtl/logic_normalization_scalar_engine.sv rtl/logic_normalization_reduction_engine.sv \
  rtl/hierarchical_normalization_datapath.sv verification/groot_normalization/hierarchical_normalization_datapath_tb.sv
 "$vvp" -M "$base" "$out"
done
