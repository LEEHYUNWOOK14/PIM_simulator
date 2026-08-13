#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";lr="${HOME}/.local/iverilog/usr"
if command -v iverilog>/dev/null 2>&1;then iv="$(command -v iverilog)";vp="$(command -v vvp)";b="";else iv="${lr}/bin/iverilog";vp="${lr}/bin/vvp";b="$(find "${lr}/lib" -type d -name ivl -print -quit)";fi
cd "${root}";o="${TMPDIR:-/tmp}/normalization_row_context_table.out";a=(-g2012 -Wall -s normalization_row_context_table_tb -o "${o}");if [[ -n "${b}" ]];then a=(-B "${b}" "${a[@]}");fi
"${iv}" "${a[@]}" rtl/normalization_row_context_table.sv verification/groot_normalization/normalization_row_context_table_tb.sv
if [[ -n "${b}" ]];then "${vp}" -M "${b}" "${o}";else "${vp}" "${o}";fi
