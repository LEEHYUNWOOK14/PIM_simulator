#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
results="reports/groot_normalization/results"
mkdir -p "$results"
for top in bf16_add bf16_mul bank_normalization_local_reducer bank_normalization_apply; do
  log="$results/${top}_bf16_yosys.log"
  params=""
  if [[ "$top" == bank_normalization_* ]]; then params="chparam -set DATA_FORMAT 1 $top;"; fi
  bash rtl/yosys_local.sh -Q -q -l "$log" -p \
    "read_verilog -sv rtl/fp16_add.sv rtl/fp16_mul.sv rtl/bf16_add.sv rtl/bf16_mul.sv rtl/bank_normalization_local_reducer.sv rtl/bank_normalization_apply.sv; ${params} hierarchy -check -top $top; synth -top $top; check -assert; stat; flatten; opt; ltp -noff"
done
echo "BF16_NORMALIZATION_SYNTHESIS PASS primitives reducer apply"
