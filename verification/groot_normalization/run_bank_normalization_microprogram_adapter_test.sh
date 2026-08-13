#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";lr="${HOME}/.local/iverilog/usr"
if command -v iverilog>/dev/null 2>&1;then iv="$(command -v iverilog)";vp="$(command -v vvp)";b="";else iv="${lr}/bin/iverilog";vp="${lr}/bin/vvp";b="$(find "${lr}/lib" -type d -name ivl -print -quit)";fi
cd "${root}";o="${TMPDIR:-/tmp}/bank_norm_adapter.out";a=(-g2012 -Wall -I. -s bank_normalization_microprogram_adapter_tb -o "${o}");if [[ -n "${b}" ]];then a=(-B "${b}" "${a[@]}");fi
"${iv}" "${a[@]}" rtl/fp16_add.sv rtl/fp16_mul.sv rtl/pim_command_decoder.sv rtl/pim_vector_alu.sv rtl/bank_pim_core.sv rtl/bank_normalization_microprogram_adapter.sv verification/groot_normalization/bank_normalization_microprogram_adapter_tb.sv
if [[ -n "${b}" ]];then "${vp}" -M "${b}" "${o}";else "${vp}" "${o}";fi
