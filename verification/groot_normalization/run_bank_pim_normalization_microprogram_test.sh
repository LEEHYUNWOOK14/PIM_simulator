#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
local_root="${HOME}/.local/iverilog/usr"

if command -v iverilog >/dev/null 2>&1 && command -v vvp >/dev/null 2>&1; then
  iverilog_bin="$(command -v iverilog)"
  vvp_bin="$(command -v vvp)"
  ivl_base=""
else
  iverilog_bin="${local_root}/bin/iverilog"
  vvp_bin="${local_root}/bin/vvp"
  ivl_base="$(find "${local_root}/lib" -type d -name ivl -print -quit)"
fi

output="${TMPDIR:-/tmp}/bank_pim_normalization_microprogram_tb.out"
args=(-g2012 -Wall -s bank_pim_normalization_microprogram_tb -o "${output}")
if [[ -n "${ivl_base}" ]]; then args=(-B "${ivl_base}" "${args[@]}"); fi

cd "${root}"
"${iverilog_bin}" "${args[@]}" \
  rtl/fp16_add.sv rtl/fp16_mul.sv rtl/pim_vector_alu.sv \
  rtl/pim_command_decoder.sv rtl/bank_pim_core.sv \
  verification/groot_normalization/bank_pim_normalization_microprogram_tb.sv
if [[ -n "${ivl_base}" ]]; then
  "${vvp_bin}" -M "${ivl_base}" "${output}"
else
  "${vvp_bin}" "${output}"
fi
