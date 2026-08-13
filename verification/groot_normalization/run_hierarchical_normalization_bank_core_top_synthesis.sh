#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "${root}"
for banks in 4 16;do
  log="reports/groot_normalization/results/hierarchical_normalization_bank_core_b${banks}_l4_e8_yosys.log"
  src="rtl/fp16_add.sv rtl/fp16_mul.sv rtl/fp16_rsqrt_lut256.sv rtl/pim_command_decoder.sv rtl/pim_vector_alu.sv rtl/bank_pim_core.sv rtl/bank_normalization_multirow_vector_reducer.sv rtl/logic_normalization_scalar_engine.sv rtl/logic_normalization_scalar_engine_array.sv rtl/logic_normalization_parallel_tree_top.sv rtl/logic_normalization_bank_barrier.sv rtl/logic_normalization_barrier_tree_top.sv rtl/hierarchical_normalization_streaming_top.sv rtl/normalization_row_context_table.sv rtl/normalization_scalar_broadcast.sv rtl/hierarchical_normalization_scalar_return_top.sv rtl/bank_normalization_microprogram_adapter.sv rtl/hierarchical_normalization_bank_issue_top.sv rtl/normalization_bank_result_tracker.sv rtl/hierarchical_normalization_bank_core_top.sv"
  bash rtl/yosys_local.sh -Q -q -l "${log}" -p "read_verilog -sv -I. ${src}; chparam -set BANKS ${banks} -set LANES 4 -set SCALAR_ENGINES 8 -set CONTEXT_ENTRIES 16 hierarchical_normalization_bank_core_top; hierarchy -check -top hierarchical_normalization_bank_core_top; rename -top hierarchical_normalization_bank_core_synth_top; synth -top hierarchical_normalization_bank_core_synth_top; stat; check -assert"
done
echo "HIERARCHICAL_NORMALIZATION_BANK_CORE_SYNTHESIS PASS banks=4,16 lanes=4 engines=8"
