#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "$root"
results="reports/groot_normalization/results";mkdir -p "$results"
common="rtl/fp16_add.sv rtl/fp16_mul.sv rtl/bf16_add.sv rtl/bf16_mul.sv rtl/fp16_rsqrt_lut256.sv rtl/bf16_rsqrt_lut256.sv rtl/logic_normalization_scalar_engine.sv rtl/logic_normalization_reduction_engine.sv rtl/bank_normalization_local_reducer.sv rtl/bank_normalization_apply.sv rtl/hierarchical_normalization_datapath.sv"
for format in 0 1;do
 suffix="fp16";if [[ "$format" == 1 ]];then suffix="bf16";fi
 for top in logic_normalization_scalar_engine logic_normalization_reduction_engine hierarchical_normalization_datapath;do
  params="chparam -set DATA_FORMAT ${format} ${top};"
  if [[ "$top" != logic_normalization_scalar_engine ]];then params="chparam -set DATA_FORMAT ${format} -set BANKS 4 ${top};";fi
  bash rtl/yosys_local.sh -Q -q -l "${results}/${top}_${suffix}_yosys.log" -p \
   "read_verilog -sv -I. ${common}; ${params} hierarchy -check -top ${top}; synth -top ${top}; check -assert; stat; flatten; opt; ltp -noff"
 done
done

full_files="rtl/pim_command_decoder.sv rtl/fp16_add.sv rtl/fp16_mul.sv rtl/bf16_add.sv rtl/bf16_mul.sv rtl/fp16_vector_add.sv rtl/pim_vector_alu.sv rtl/pim_crf.sv rtl/dram_bank_array_model.sv rtl/bank_pim_core.sv rtl/bank_side_pim_subsystem.sv rtl/logic_die_link_arbiter.sv rtl/channel_tsv_interconnect.sv rtl/logic_epoch_barrier.sv rtl/logic_shared_buffer.sv rtl/logic_pcu.sv rtl/logic_pcu_scheduler.sv rtl/logic_command_coalescer.sv rtl/logic_operand_context_buffer.sv rtl/cross_channel_reduction_network.sv rtl/logic_result_router.sv rtl/logic_die_pim_top.sv rtl/fp16_rsqrt_lut256.sv rtl/bf16_rsqrt_lut256.sv rtl/logic_normalization_scalar_engine.sv rtl/logic_normalization_reduction_engine.sv rtl/full_pim_system_top.sv"
for format in 0 1;do
 suffix="fp16";if [[ "$format" == 1 ]];then suffix="bf16";fi
 bash rtl/yosys_local.sh -Q -q -l "${results}/full_pim_normalization_top_${suffix}_structural_yosys.log" -p \
  "read_verilog -sv -I. ${full_files}; chparam -set NORMALIZATION_DATA_FORMAT ${format} -set CHANNELS 1 -set BANKS 1 -set PIM_BLOCKS 1 -set PCUS 1 -set ROWS 2 -set COLS 2 -set DATA_WIDTH 16 -set CRF_DEPTH 2 -set WEIGHT_BUFFER_BYTES 16 full_pim_system_top; hierarchy -check -auto-top; proc; opt_clean; check -assert; stat"
done
echo "NORMALIZATION_FULLPATH_SYNTHESIS PASS formats=FP16,BF16 scalar reduction hierarchical full_top_elaboration"
