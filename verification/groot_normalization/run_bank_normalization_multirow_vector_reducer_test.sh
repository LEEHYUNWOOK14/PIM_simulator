#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";lr="${HOME}/.local/iverilog/usr"
if command -v iverilog>/dev/null 2>&1;then iv="$(command -v iverilog)";vp="$(command -v vvp)";b="";else iv="${lr}/bin/iverilog";vp="${lr}/bin/vvp";b="$(find "${lr}/lib" -type d -name ivl -print -quit)";fi
cd "${root}"
for depth in 4 8;do
 o="${TMPDIR:-/tmp}/bank_norm_multirow_d${depth}.out";a=(-g2012 -Wall -s bank_normalization_multirow_vector_reducer_tb -Pbank_normalization_multirow_vector_reducer_tb.FIFO_DEPTH="${depth}" -o "${o}");if [[ -n "${b}" ]];then a=(-B "${b}" "${a[@]}");fi
 "${iv}" "${a[@]}" rtl/fp16_add.sv rtl/fp16_mul.sv rtl/bank_normalization_multirow_vector_reducer.sv verification/groot_normalization/bank_normalization_multirow_vector_reducer_tb.sv
 if [[ -n "${b}" ]];then "${vp}" -M "${b}" "${o}";else "${vp}" "${o}";fi
done
