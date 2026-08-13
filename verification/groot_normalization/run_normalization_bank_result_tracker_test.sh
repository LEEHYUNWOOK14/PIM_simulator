#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";lr="${HOME}/.local/iverilog/usr"
if command -v iverilog>/dev/null 2>&1;then iv="$(command -v iverilog)";vp="$(command -v vvp)";b="";else iv="${lr}/bin/iverilog";vp="${lr}/bin/vvp";b="$(find "${lr}/lib" -type d -name ivl -print -quit)";fi
cd "${root}";o="${TMPDIR:-/tmp}/normalization_bank_result_tracker.out";a=(-g2012 -Wall -s normalization_bank_result_tracker_tb -o "${o}");if [[ -n "${b}" ]];then a=(-B "${b}" "${a[@]}");fi
"${iv}" "${a[@]}" rtl/normalization_bank_result_tracker.sv verification/groot_normalization/normalization_bank_result_tracker_tb.sv
if [[ -n "${b}" ]];then "${vp}" -M "${b}" "${o}";else "${vp}" "${o}";fi
