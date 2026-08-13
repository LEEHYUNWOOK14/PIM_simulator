#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";lr="${HOME}/.local/iverilog/usr"
if command -v iverilog>/dev/null 2>&1;then iv="$(command -v iverilog)";vp="$(command -v vvp)";b="";else iv="${lr}/bin/iverilog";vp="${lr}/bin/vvp";b="$(find "${lr}/lib" -type d -name ivl -print -quit)";fi
cd "${root}";o="${TMPDIR:-/tmp}/logic_norm_barrier_tree.out";a=(-g2012 -Wall -I. -s logic_normalization_barrier_tree_top_tb -o "${o}");if [[ -n "${b}" ]];then a=(-B "${b}" "${a[@]}");fi
"${iv}" "${a[@]}" rtl/fp16_add.sv rtl/fp16_mul.sv rtl/fp16_rsqrt_lut256.sv rtl/logic_normalization_scalar_engine.sv rtl/logic_normalization_scalar_engine_array.sv rtl/logic_normalization_parallel_tree_top.sv rtl/logic_normalization_bank_barrier.sv rtl/logic_normalization_barrier_tree_top.sv verification/groot_normalization/logic_normalization_barrier_tree_top_tb.sv
if [[ -n "${b}" ]];then "${vp}" -M "${b}" "${o}";else "${vp}" "${o}";fi
