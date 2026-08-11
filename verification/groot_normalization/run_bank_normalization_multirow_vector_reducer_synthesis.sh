#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "${root}"
for depth in 4 8 16;do
 log="reports/groot_normalization/results/bank_multirow_vector_reducer_l4_d${depth}_yosys.log"
 bash rtl/yosys_local.sh -Q -q -l "${log}" -p "read_verilog -sv rtl/fp16_add.sv rtl/fp16_mul.sv rtl/bank_normalization_multirow_vector_reducer.sv; chparam -set LANES 4 -set RESULT_FIFO_DEPTH ${depth} bank_normalization_multirow_vector_reducer; hierarchy -check -top bank_normalization_multirow_vector_reducer; synth -top bank_normalization_multirow_vector_reducer; stat; check -assert; flatten; opt; ltp -noff"
done
echo "BANK_NORMALIZATION_MULTIROW_VECTOR_REDUCER_SYNTHESIS PASS lanes=4 depths=4,8,16"
