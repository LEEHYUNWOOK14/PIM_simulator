#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
local_root="${HOME}/.local/iverilog/usr"
iverilog_bin="${local_root}/bin/iverilog"
vvp_bin="${local_root}/bin/vvp"
ivl_base="$(find "${local_root}/lib" -type d -name ivl -print -quit)"
if command -v iverilog >/dev/null 2>&1; then
    iverilog_bin="$(command -v iverilog)"
    vvp_bin="$(command -v vvp)"
    ivl_base=""
elif [[ ! -x "${iverilog_bin}" || ! -x "${vvp_bin}" ]]; then
    echo "Icarus Verilog not found. Run: bash rtl/bootstrap_iverilog_local.sh" >&2
    exit 1
fi

cd "${repo_root}"
for pipelines in 1 2 4; do
    output="${TMPDIR:-/tmp}/shared_fp16_reduction_cluster_p${pipelines}_tb.out"
    args=(-g2012 -Wall -s shared_fp16_reduction_cluster_tb \
        -Pshared_fp16_reduction_cluster_tb.PIPELINES="${pipelines}" -o "${output}")
    if [[ -n "${ivl_base}" ]]; then args=(-B "${ivl_base}" "${args[@]}"); fi
    "${iverilog_bin}" "${args[@]}" \
        rtl/fp16_add.sv rtl/fp16_vector_add.sv \
        rtl/bank_local_reduction_buffer.sv rtl/shared_fp16_pipeline_fabric.sv \
        rtl/shared_fp16_reduction_cluster.sv \
        rtl/tb/shared_fp16_reduction_cluster_tb.sv
    if [[ -n "${ivl_base}" ]]; then
        "${vvp_bin}" -M "${ivl_base}" "${output}"
    else
        "${vvp_bin}" "${output}"
    fi
done
