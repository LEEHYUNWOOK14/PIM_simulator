#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "${root}"
log="reports/groot_normalization/results/logic_normalization_barrier_tree_e8_yosys.log"
bash rtl/yosys_local.sh -Q -q -l "${log}" -p "read_verilog -sv -I. rtl/fp16_add.sv rtl/fp16_mul.sv rtl/fp16_rsqrt_lut256.sv rtl/logic_normalization_scalar_engine.sv rtl/logic_normalization_scalar_engine_array.sv rtl/logic_normalization_parallel_tree_top.sv rtl/logic_normalization_bank_barrier.sv rtl/logic_normalization_barrier_tree_top.sv; chparam -set BANKS 16 -set SCALAR_ENGINES 8 logic_normalization_barrier_tree_top; hierarchy -check -top logic_normalization_barrier_tree_top; synth -top logic_normalization_barrier_tree_top; stat; check -assert"
echo "LOGIC_NORMALIZATION_BARRIER_TREE_SYNTHESIS PASS banks=16 engines=8"
