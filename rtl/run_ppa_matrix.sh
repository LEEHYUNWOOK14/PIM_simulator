#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
result_dir="${repo_root}/experiment/results/ppa_matrix"
mkdir -p "${result_dir}"
cd "${repo_root}"

# Keep the matrix focused on the production full-top hierarchy. Reading every
# exploratory RTL module makes Yosys elaborate many unrelated designs and can
# also pull in duplicate OneDrive conflict copies.
sources=(
  rtl/pim_command_decoder.sv rtl/fp16_add.sv rtl/fp16_mul.sv
  rtl/fp16_vector_add.sv rtl/pim_vector_alu.sv rtl/pim_crf.sv
  rtl/dram_bank_array_model.sv rtl/bank_pim_core.sv
  rtl/bank_side_pim_subsystem.sv rtl/logic_die_link_arbiter.sv
  rtl/channel_tsv_interconnect.sv rtl/logic_epoch_barrier.sv
  rtl/logic_shared_buffer.sv rtl/logic_pcu.sv rtl/logic_pcu_scheduler.sv
  rtl/logic_command_coalescer.sv rtl/logic_operand_context_buffer.sv
  rtl/cross_channel_reduction_network.sv rtl/logic_result_router.sv
  rtl/logic_die_pim_top.sv rtl/fp16_rsqrt_lut256.sv
  rtl/logic_normalization_scalar_engine.sv
  rtl/logic_normalization_reduction_engine.sv rtl/full_pim_system_top.sv
)
read_cmd="read_verilog -sv ${sources[*]}"

cat > "${result_dir}/configuration.txt" <<'EOF'
technology=sky130hd (technology mapping is a later OpenROAD step)
top=full_pim_system_top
CHANNELS=1 BANKS=1 PIM_BLOCKS=1 PCUS=1 ROWS=1 COLS=1 DATA_WIDTH=16 CRF_DEPTH=2 WEIGHT_BUFFER_BYTES=16
B0=ENABLE_LOGIC_DIE_PCU:0 ENABLE_NORMALIZATION_ENGINE:0
B1=ENABLE_LOGIC_DIE_PCU:1 ENABLE_NORMALIZATION_ENGINE:0
B2=ENABLE_LOGIC_DIE_PCU:1 ENABLE_NORMALIZATION_ENGINE:1
EOF

echo 'design,logic_die_pcu,normalization_engine,cells' > "${result_dir}/synthesis_summary.csv"

run_case() {
    local name="$1"
    local logic_enable="$2"
    local norm_enable="$3"
    local log="${result_dir}/${name}.log"
    local netlist="${result_dir}/${name}.v"
    local script="${result_dir}/${name}.ys"

    cat > "${script}" <<EOF
${read_cmd}
chparam -set CHANNELS 1 -set BANKS 1 -set PIM_BLOCKS 1 -set PCUS 1 -set ROWS 1 -set COLS 1 -set DATA_WIDTH 16 -set CRF_DEPTH 2 -set WEIGHT_BUFFER_BYTES 16 -set ENABLE_LOGIC_DIE_PCU ${logic_enable} -set ENABLE_NORMALIZATION_ENGINE ${norm_enable} full_pim_system_top
# hierarchy selects the generated parameterized full_pim_system_top created by
# chparam; the original unparameterized module is intentionally replaced.
hierarchy -check -auto-top
synth
stat
write_verilog -noattr ${netlist}
EOF

    bash rtl/yosys_local.sh -Q -q -l "${log}" "${script}"
    local cells
    cells="$(grep -a 'Number of cells:' "${log}" | tail -1 | awk '{print $4}')"
    echo "${name},${logic_enable},${norm_enable},${cells:-0}" >> "${result_dir}/synthesis_summary.csv"
}

run_case B0 0 0
run_case B1 1 0
run_case B2 1 1
cat "${result_dir}/synthesis_summary.csv"
