#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workspace="${repo_root}/b0_baseline_experiment"
result_dir="${workspace}/results/synthesis"
manifest_dir="${workspace}/manifest"
mkdir -p "${manifest_dir}"

generic_log="${result_dir}/b0_generic_yosys.log"
mapped_log="${result_dir}/b0_sky130_yosys.log"
sta_log="${result_dir}/b0_sky130_sta.log"
generic_netlist="${result_dir}/b0_generic.v"
mapped_netlist="${result_dir}/b0_sky130.v"

for f in "${generic_log}" "${mapped_log}" "${sta_log}" "${generic_netlist}" "${mapped_netlist}"; do
  [[ -s "${f}" ]] || { echo "missing artifact: ${f}" >&2; exit 1; }
done
grep -q "End of script" "${generic_log}"
grep -q "End of script" "${mapped_log}"
grep -q "B0_STA_MAX_PATH_END" "${sta_log}"

generic_cells="$(awk '/=== design hierarchy ===/{seen=1; next} seen && /full_pim_system_top/{print $1; exit}' "${generic_log}")"
mapped_cells="$(awk '/=== full_pim_system_top ===/{section++; next} section==2 && / cells$/{print $1; exit}' "${mapped_log}")"
chip_area="$(grep -a 'Chip area for module' "${mapped_log}" | tail -1 | awk '{print $NF}')"
worst_slack="$(grep -a 'worst slack max' "${sta_log}" | tail -1 | awk '{print $4}')"
critical_path="$(awk -v p=10.0 -v s="${worst_slack}" 'BEGIN { printf "%.3f", p-s }')"
mapped_unmapped="$(grep -a -c '\$_' "${mapped_netlist}" || true)"

cat >"${result_dir}/b0_synthesis_metrics.csv" <<EOF
metric,value,unit,evidence
generic_cells,${generic_cells},cells,MEASURED_YOSYS
mapped_cells,${mapped_cells},cells,MEASURED_YOSYS_SKY130HD
mapped_chip_area,${chip_area},um2,MEASURED_YOSYS_SKY130HD
prelayout_worst_slack,${worst_slack},ns,MEASURED_OPENROAD_STA
prelayout_critical_path,${critical_path},ns,DERIVED_PERIOD_MINUS_SLACK
unmapped_internal_cell_tokens,${mapped_unmapped},count,MEASURED_NETLIST_GREP
EOF

cd "${repo_root}"
/home/chandler/.local/oss-cad-suite/bin/yosys -V >"${manifest_dir}/yosys_version.txt"
/home/chandler/.local/stob-eda/openroad/bin/openroad -version >"${manifest_dir}/openroad_version.txt" 2>&1 || true
sha256sum rtl/pim_command_decoder.sv rtl/fp16_add.sv rtl/fp16_mul.sv \
  rtl/fp16_vector_add.sv rtl/pim_vector_alu.sv rtl/pim_crf.sv \
  rtl/dram_bank_array_model.sv rtl/bank_pim_core.sv rtl/bank_side_pim_subsystem.sv \
  rtl/logic_die_link_arbiter.sv rtl/channel_tsv_interconnect.sv \
  rtl/logic_epoch_barrier.sv rtl/logic_shared_buffer.sv rtl/logic_pcu.sv \
  rtl/logic_pcu_scheduler.sv rtl/logic_command_coalescer.sv \
  rtl/logic_operand_context_buffer.sv rtl/cross_channel_reduction_network.sv \
  rtl/logic_result_router.sv rtl/logic_die_pim_top.sv rtl/fp16_rsqrt_lut256.sv \
  rtl/logic_normalization_scalar_engine.sv rtl/logic_normalization_reduction_engine.sv \
  rtl/full_pim_system_top.sv >"${manifest_dir}/rtl_source_sha256.txt"
sha256sum b0_baseline_experiment/config/b0_configuration.txt \
  "${generic_netlist}" "${mapped_netlist}" "${generic_log}" "${mapped_log}" "${sta_log}" \
  >"${manifest_dir}/synthesis_input_output_sha256.txt"

printf 'B0 synthesis/STA collected generic=%s mapped=%s area_um2=%s slack_ns=%s critical_path_ns=%s\n' \
  "${generic_cells}" "${mapped_cells}" "${chip_area}" "${worst_slack}" "${critical_path}"
