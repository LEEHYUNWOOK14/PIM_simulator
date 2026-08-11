#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${root}"
bank_values=("$@")
if [[ ${#bank_values[@]} -eq 0 ]]; then
  bank_values=(1 2 4 8 16)
fi
for banks in "${bank_values[@]}"; do
  log="reports/groot_normalization/results/shared_pair_reducer_b${banks}_yosys.log"
  bash rtl/yosys_local.sh -Q -q -l "${log}" -p \
    "read_verilog -sv rtl/fp16_add.sv rtl/fp16_vector_add.sv rtl/bank_local_reduction_buffer.sv rtl/bank_local_fp16_reduction.sv; chparam -set BANKS ${banks} -set ENTRIES_PER_BANK 2 -set LANES 2 bank_local_fp16_reduction; hierarchy -check -top bank_local_fp16_reduction; synth -top bank_local_fp16_reduction; stat; check -assert"
done
echo "SHARED_PAIR_REDUCER_SYNTHESIS PASS banks=${bank_values[*]} lanes=2"
