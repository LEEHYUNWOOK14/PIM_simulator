#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
result_dir="${repo_root}/experiment/results/full_pim_rtl"
mkdir -p "${result_dir}"
cd "${repo_root}"
common_sources="rtl/pim_command_decoder.sv rtl/fp16_add.sv rtl/fp16_mul.sv rtl/fp16_vector_add.sv rtl/pim_vector_alu.sv rtl/pim_crf.sv rtl/dram_bank_array_model.sv rtl/bank_pim_core.sv rtl/bank_side_pim_subsystem.sv rtl/logic_die_link_arbiter.sv rtl/channel_tsv_interconnect.sv rtl/logic_epoch_barrier.sv rtl/logic_shared_buffer.sv rtl/logic_pcu.sv rtl/logic_pcu_scheduler.sv rtl/logic_command_coalescer.sv rtl/logic_operand_context_buffer.sv rtl/cross_channel_reduction_network.sv rtl/logic_result_router.sv rtl/logic_die_pim_top.sv rtl/fp16_rsqrt_lut256.sv rtl/logic_normalization_scalar_engine.sv rtl/logic_normalization_reduction_engine.sv rtl/full_pim_system_top.sv"
bank_log="${result_dir}/bank_pim_core_dw32.log"
bash rtl/yosys_local.sh -Q -q -l "${bank_log}" -p \
  "read_verilog -sv ${common_sources}; chparam -set DATA_WIDTH 32 bank_pim_core; hierarchy -check -top bank_pim_core; synth -top bank_pim_core; stat; check"
logic_log="${result_dir}/logic_scheduler_2pcu_dw32.log"
bash rtl/yosys_local.sh -Q -q -l "${logic_log}" -p \
  "read_verilog -sv ${common_sources}; chparam -set PCUS 2 -set ISSUE_PORTS 2 -set DATA_WIDTH 32 logic_pcu_scheduler; hierarchy -check -top logic_pcu_scheduler; synth -top logic_pcu_scheduler; stat; check"
full_log="${result_dir}/full_top_2ch_dw32.log"
bash rtl/yosys_local.sh -Q -q -l "${full_log}" -p \
  "read_verilog -sv ${common_sources}; chparam -set CHANNELS 2 -set BANKS 4 -set PIM_BLOCKS 2 -set PCUS 2 -set ROWS 8 -set COLS 8 -set DATA_WIDTH 32 full_pim_system_top; hierarchy -check -top full_pim_system_top; check; stat"
csv="${result_dir}/synthesis_summary.csv"
echo "design,configuration,cells" > "${csv}"
for item in "bank_pim_core,dw32,${bank_log}" \
            "logic_pcu_scheduler,2pcu_dw32,${logic_log}" \
            "full_pim_system_top,2ch_2pb_2pcu_dw32,${full_log}"; do
  IFS=, read -r design config log <<< "${item}"
  cells="$(grep -a 'Number of cells:' "${log}" | tail -1 | awk '{print $4}')"
  echo "${design},${config},${cells:-0}" >> "${csv}"
done
cat "${csv}"
