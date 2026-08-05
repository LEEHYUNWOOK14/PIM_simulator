#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
result_dir="${repo_root}/experiment/results/rtl_synthesis"
csv="${repo_root}/experiment/results/fp16_synthesis_sweep.csv"
mkdir -p "${result_dir}"

echo "lanes,data_width_bits,generic_cells,topological_depth" > "${csv}"
cd "${repo_root}"
for lanes in 1 2 4 8 16; do
    log="${result_dir}/fp16_vector_${lanes}lane.log"
    bash rtl/yosys_local.sh -Q -q -l "${log}" -p \
        "read_verilog -sv rtl/fp16_add.sv rtl/fp16_vector_add.sv; chparam -set LANES ${lanes} fp16_vector_add; synth -top fp16_vector_add; flatten; opt; stat; ltp -noff"
    cells="$(grep 'Number of cells:' "${log}" | tail -1 | awk '{print $4}')"
    depth="$(grep 'Longest topological path in fp16_vector_add' "${log}" | tail -1 | sed -E 's/.*length=([0-9]+).*/\1/')"
    echo "${lanes},$((lanes * 16)),${cells},${depth}" >> "${csv}"
done

source_log="${result_dir}/bank_local_fp16_1source.log"
bash rtl/yosys_local.sh -Q -q -l "${source_log}" -p \
    "read_verilog -sv rtl/fp16_add.sv rtl/bank_local_reduction_buffer.sv rtl/bank_local_fp16_reduction.sv; chparam -set BANKS 1 -set ENTRIES_PER_BANK 16 -set KEY_WIDTH 64 -set LANES 16 bank_local_fp16_reduction; synth -top bank_local_fp16_reduction; flatten; opt; stat; ltp -noff"
source_cells="$(grep 'Number of cells:' "${source_log}" | tail -1 | awk '{print $4}')"
source_dffs="$(awk '/^=== bank_local_fp16_reduction ===/ {sum=0; active=1; next} active && /\$_DFF/ {sum += $2} END {print sum + 0}' "${source_log}")"
source_depth="$(grep 'Longest topological path in bank_local_fp16_reduction' "${source_log}" | tail -1 | sed -E 's/.*length=([0-9]+).*/\1/')"
component_csv="${repo_root}/experiment/results/fp16_component_synthesis.csv"
base_cells="$(awk -F, '$1 == 16 {print $3}' "${csv}")"
base_depth="$(awk -F, '$1 == 16 {print $4}' "${csv}")"
buffer_overhead=$((source_cells - base_cells))
cat > "${component_csv}" <<EOF
component,generic_cells,flip_flops,topological_depth
fp16_burst_pipeline_16lane,${base_cells},0,${base_depth}
source_buffer_plus_fp16_pipeline,${source_cells},${source_dffs},${source_depth}
source_buffer_control_overhead,${buffer_overhead},${source_dffs},not_separated
EOF

architecture_csv="${repo_root}/experiment/results/fp16_architecture_area_proxy.csv"
echo "architecture,burst_pipelines,fp16_lanes,estimated_generic_cells,estimated_flip_flops" > "${architecture_csv}"
for pipelines in 1 2 4 8 16 64 512; do
    estimated_cells=$((512 * buffer_overhead + pipelines * base_cells))
    echo "shared_pipeline_with_512_source_buffers,${pipelines},$((pipelines * 16)),${estimated_cells},$((512 * source_dffs))" >> "${architecture_csv}"
done

echo "FP16_SYNTHESIS_SWEEP PASS"
cat "${csv}"
cat "${component_csv}"
cat "${architecture_csv}"
