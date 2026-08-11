#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
local_root="${HOME}/.local/iverilog/usr"
if command -v iverilog >/dev/null 2>&1; then
  iverilog_bin="$(command -v iverilog)"; vvp_bin="$(command -v vvp)"; ivl_base=""
else
  iverilog_bin="${local_root}/bin/iverilog"; vvp_bin="${local_root}/bin/vvp"
  ivl_base="$(find "${local_root}/lib" -type d -name ivl -print -quit)"
fi
out="${TMPDIR:-/tmp}/bank_normalization_vector_reducer_tb.out"
args=(-g2012 -Wall -s bank_normalization_vector_reducer_tb -o "${out}")
if [[ -n "${ivl_base}" ]]; then args=(-B "${ivl_base}" "${args[@]}"); fi
cd "${root}"
"${iverilog_bin}" "${args[@]}" rtl/fp16_add.sv rtl/fp16_mul.sv \
  rtl/bank_normalization_vector_reducer.sv \
  verification/groot_normalization/bank_normalization_vector_reducer_tb.sv
if [[ -n "${ivl_base}" ]]; then "${vvp_bin}" -M "${ivl_base}" "${out}"; else "${vvp_bin}" "${out}"; fi
