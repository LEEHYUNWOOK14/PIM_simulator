#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
result_dir="${repo_root}/b0_baseline_experiment/results/synthesis"
cd "${repo_root}"
sources=(
  rtl/pim_command_decoder.sv rtl/fp16_add.sv rtl/fp16_mul.sv
  rtl/fp16_vector_add.sv rtl/pim_vector_alu.sv rtl/pim_crf.sv
  rtl/dram_bank_array_model.sv rtl/bank_pim_core.sv rtl/bank_side_pim_subsystem.sv
  rtl/logic_die_link_arbiter.sv rtl/channel_tsv_interconnect.sv
  rtl/logic_epoch_barrier.sv rtl/logic_shared_buffer.sv rtl/logic_pcu.sv
  rtl/logic_pcu_scheduler.sv rtl/logic_command_coalescer.sv
  rtl/logic_operand_context_buffer.sv rtl/cross_channel_reduction_network.sv
  rtl/logic_result_router.sv rtl/logic_die_pim_top.sv rtl/fp16_rsqrt_lut256.sv
  rtl/logic_normalization_scalar_engine.sv rtl/logic_normalization_reduction_engine.sv
  rtl/full_pim_system_top.sv
)
params="-set CHANNELS 1 -set BANKS 2 -set PIM_BLOCKS 1 -set PCUS 1 -set ROWS 1 -set COLS 1 -set DATA_WIDTH 32 -set CRF_DEPTH 2 -set WEIGHT_BUFFER_BYTES 16 -set ENABLE_LOGIC_DIE_PCU 0 -set ENABLE_NORMALIZATION_ENGINE 0"
/home/chandler/.local/oss-cad-suite/bin/yosys -Q -q \
  -l "${result_dir}/b0_generic_yosys.log" \
  -p "read_verilog -sv ${sources[*]}; chparam ${params} full_pim_system_top; hierarchy -check -auto-top; rename -top full_pim_system_top; synth -top full_pim_system_top; check -assert; stat; write_verilog -noattr ${result_dir}/b0_generic.v"
grep -q "End of script" "${result_dir}/b0_generic_yosys.log"
printf 'B0 generic synthesis log regenerated\n'
