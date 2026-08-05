#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
result_dir="${repo_root}/experiment/results/rtl_synthesis"
csv="${repo_root}/experiment/results/shared_fp16_fabric_synthesis.csv"
mkdir -p "${result_dir}"
echo "sources,pipelines,fp16_lanes,generic_cells,flip_flops,topological_depth" > "${csv}"
cd "${repo_root}"
for pipelines in 1 2 4; do
    log="${result_dir}/shared_fp16_fabric_p${pipelines}.log"
    bash rtl/yosys_local.sh -Q -q -l "${log}" -p \
        "read_verilog -sv rtl/fp16_add.sv rtl/fp16_vector_add.sv rtl/shared_fp16_pipeline_fabric.sv; chparam -set SOURCES 8 -set PIPELINES ${pipelines} -set LANES 16 shared_fp16_pipeline_fabric; synth -top shared_fp16_pipeline_fabric; flatten; opt; stat; ltp -noff"
    cells="$(grep 'Number of cells:' "${log}" | tail -1 | awk '{print $4}')"
    dffs="$(awk '/^=== shared_fp16_pipeline_fabric ===/ {sum=0; active=1; next} active && /\$_DFF/ {sum += $2} END {print sum + 0}' "${log}")"
    depth="$(grep 'Longest topological path in shared_fp16_pipeline_fabric' "${log}" | tail -1 | sed -E 's/.*length=([0-9]+).*/\1/')"
    echo "8,${pipelines},$((pipelines * 16)),${cells},${dffs},${depth}" >> "${csv}"
done
cat "${csv}"
