#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workspace="${repo_root}/b0_baseline_experiment"
result_dir="${workspace}/results/synthesis"
mkdir -p "${result_dir}" "${workspace}/manifest"
cd "${repo_root}"

yosys=/home/chandler/.local/oss-cad-suite/bin/yosys
openroad=/home/chandler/.local/stob-eda/openroad/bin/openroad
platform=/home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd
lib="${platform}/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
lef="${platform}/lef/sky130_fd_sc_hd_merged.lef"

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
source_text="${sources[*]}"
params="-set CHANNELS 1 -set BANKS 2 -set PIM_BLOCKS 1 -set PCUS 1 -set ROWS 1 -set COLS 1 -set DATA_WIDTH 32 -set CRF_DEPTH 2 -set WEIGHT_BUFFER_BYTES 16 -set ENABLE_LOGIC_DIE_PCU 0 -set ENABLE_NORMALIZATION_ENGINE 0"

generic_log="${result_dir}/b0_generic_yosys.log"
generic_netlist="${result_dir}/b0_generic.v"
"${yosys}" -Q -q -l "${generic_log}" -p "read_verilog -sv ${source_text}; chparam ${params} full_pim_system_top; hierarchy -check -auto-top; rename -top full_pim_system_top; synth -top full_pim_system_top; check -assert; stat; write_verilog -noattr ${generic_netlist}"

mapped_log="${result_dir}/b0_sky130_yosys.log"
mapped_netlist="${result_dir}/b0_sky130.v"
"${yosys}" -Q -q -l "${mapped_log}" -p "read_liberty -lib -ignore_miss_func ${lib}; read_verilog -sv ${source_text}; chparam ${params} full_pim_system_top; hierarchy -check -auto-top; rename -top full_pim_system_top; synth -noabc -top full_pim_system_top; flatten; opt_clean; dfflibmap -liberty ${lib}; abc -liberty ${lib} -D 10000 -dont_use sky130_fd_sc_hd__lpflow_* -dont_use sky130_fd_sc_hd__probe*; clean -purge; check -assert; stat -liberty ${lib}; write_verilog -noattr -noexpr -nodec ${mapped_netlist}"

sta_log="${result_dir}/b0_sky130_sta.log"
set +e
B0_LIBERTY="${lib}" B0_TECH_LEF="${lef}" B0_NETLIST="${mapped_netlist}" \
B0_TOP=full_pim_system_top B0_CLOCK_PERIOD_NS=10.0 \
"${openroad}" -exit "${workspace}/config/b0_sta.tcl" >"${sta_log}" 2>&1
sta_rc=$?
set -e

grep -q "End of script" "${generic_log}"
grep -q "End of script" "${mapped_log}"
grep -q "B0_STA_MAX_PATH_END" "${sta_log}"

generic_cells="$(awk '/=== design hierarchy ===/{seen=1; next} seen && /full_pim_system_top/{print $1; exit}' "${generic_log}")"
mapped_cells="$(awk '/=== full_pim_system_top ===/{section++; next} section==2 && / cells$/{print $1; exit}' "${mapped_log}")"
chip_area="$(grep -a 'Chip area for module' "${mapped_log}" | tail -1 | awk '{print $NF}')"
worst_slack="$(grep -a 'worst slack max' "${sta_log}" | tail -1 | awk '{print $4}')"
critical_path="$(awk -v p=10.0 -v s="${worst_slack}" 'BEGIN { printf "%.3f", p-s }')"
printf 'metric,value,unit,evidence\ngeneric_cells,%s,cells,MEASURED_YOSYS\nmapped_cells,%s,cells,MEASURED_YOSYS_SKY130HD\nmapped_chip_area,%s,um2,MEASURED_YOSYS_SKY130HD\nprelayout_worst_slack,%s,ns,MEASURED_OPENROAD_STA\nprelayout_critical_path,%s,ns,DERIVED_PERIOD_MINUS_SLACK\nsta_process_exit_code,%s,count,MEASURED_TOOL_EXIT\n' \
  "${generic_cells}" "${mapped_cells}" "${chip_area}" "${worst_slack}" "${critical_path}" "${sta_rc}" >"${result_dir}/b0_synthesis_metrics.csv"

printf '%s\n' "$("${yosys}" -V)" >"${workspace}/manifest/yosys_version.txt"
printf '%s\n' "$("${openroad}" -version 2>/dev/null || true)" >"${workspace}/manifest/openroad_version.txt"
sha256sum "${sources[@]}" >"${workspace}/manifest/rtl_source_sha256.txt"
sha256sum "${workspace}/config/b0_configuration.txt" "${lib}" "${lef}" \
  "${generic_netlist}" "${mapped_netlist}" >"${workspace}/manifest/synthesis_input_output_sha256.txt"

printf 'B0-G0/G1/G2/G4 synthesis+STA complete generic_cells=%s mapped_cells=%s area_um2=%s slack_ns=%s critical_path_ns=%s sta_rc=%s\n' \
  "${generic_cells}" "${mapped_cells}" "${chip_area}" "${worst_slack}" "${critical_path}" "${sta_rc}"
