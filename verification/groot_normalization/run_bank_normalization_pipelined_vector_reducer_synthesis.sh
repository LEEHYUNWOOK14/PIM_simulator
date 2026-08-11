#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)";cd "${root}"
for format in 0 1;do
 for lanes in 2 4 8 16;do
  suffix="";if [[ "${format}" == 1 ]];then suffix="_bf16";fi
  log="reports/groot_normalization/results/bank_pipelined_vector_reducer_l${lanes}${suffix}_yosys.log"
  bash rtl/yosys_local.sh -Q -q -l "${log}" -p "read_verilog -sv rtl/fp16_add.sv rtl/fp16_mul.sv rtl/bf16_add.sv rtl/bf16_mul.sv rtl/bank_normalization_pipelined_vector_reducer.sv; chparam -set DATA_FORMAT ${format} -set LANES ${lanes} bank_normalization_pipelined_vector_reducer; hierarchy -check -top bank_normalization_pipelined_vector_reducer; synth -top bank_normalization_pipelined_vector_reducer; stat; check -assert; flatten; opt; ltp -noff"
 done
done
echo "BANK_NORMALIZATION_PIPELINED_VECTOR_REDUCER_SYNTHESIS PASS formats=FP16,BF16 lanes=2,4,8,16"
