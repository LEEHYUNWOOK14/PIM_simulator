#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="${HOME}/.local/iverilog/usr";iverilog="${root}/bin/iverilog";vvp="${root}/bin/vvp"
base="$(find "${root}/lib" -type d -name ivl -print -quit)"
if command -v iverilog >/dev/null 2>&1;then iverilog="$(command -v iverilog)";vvp="$(command -v vvp)";base="";fi
cd "${repo_root}"
for pipelines in 1 2 4;do
    out="${TMPDIR:-/tmp}/shared_channel_trace_p${pipelines}.out"
    args=(-g2012 -Wall -s shared_channel_actual_trace_tb -Pshared_channel_actual_trace_tb.PIPELINES="${pipelines}" -o "${out}")
    if [[ -n "${base}" ]];then args=(-B "${base}" "${args[@]}");fi
    "${iverilog}" "${args[@]}" rtl/fp16_add.sv rtl/fp16_vector_add.sv \
        rtl/bank_local_reduction_buffer.sv rtl/shared_fp16_pipeline_fabric.sv \
        rtl/shared_fp16_reduction_cluster.sv rtl/logic_die_link_arbiter.sv \
        rtl/shared_channel_reduction_path.sv rtl/tb/shared_channel_actual_trace_tb.sv
    if [[ -n "${base}" ]];then "${vvp}" -M "${base}" "${out}";else "${vvp}" "${out}";fi
done
