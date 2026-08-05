#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
local_root="${HOME}/.local/iverilog/usr"

if command -v iverilog >/dev/null 2>&1 && command -v vvp >/dev/null 2>&1; then
    iverilog_bin="$(command -v iverilog)"
    vvp_bin="$(command -v vvp)"
    ivl_base=""
elif [[ -x "${local_root}/bin/iverilog" && -x "${local_root}/bin/vvp" ]]; then
    iverilog_bin="${local_root}/bin/iverilog"
    vvp_bin="${local_root}/bin/vvp"
    ivl_base="$(find "${local_root}/lib" -type d -name ivl -print -quit)"
else
    echo "Icarus Verilog not found. Run: bash rtl/bootstrap_iverilog_local.sh" >&2
    exit 1
fi

output="${TMPDIR:-/tmp}/bank_local_reduction_buffer_tb.out"
compile_args=(-g2012 -Wall -s bank_local_reduction_buffer_tb -o "${output}")
if [[ -n "${ivl_base}" ]]; then
    compile_args=(-B "${ivl_base}" "${compile_args[@]}")
fi

cd "${repo_root}"
"${iverilog_bin}" "${compile_args[@]}" \
    rtl/fp16_add.sv \
    rtl/bank_local_reduction_buffer.sv \
    rtl/tb/bank_local_reduction_buffer_tb.sv

if [[ -n "${ivl_base}" ]]; then
    "${vvp_bin}" -M "${ivl_base}" "${output}"
else
    "${vvp_bin}" "${output}"
fi

output="${TMPDIR:-/tmp}/fp16_add_tb.out"
compile_args=(-g2012 -Wall -s fp16_add_tb -o "${output}")
if [[ -n "${ivl_base}" ]]; then
    compile_args=(-B "${ivl_base}" "${compile_args[@]}")
fi
"${iverilog_bin}" "${compile_args[@]}" rtl/fp16_add.sv rtl/tb/fp16_add_tb.sv
if [[ -n "${ivl_base}" ]]; then
    "${vvp_bin}" -M "${ivl_base}" "${output}"
else
    "${vvp_bin}" "${output}"
fi

for pipelines in 1 2 4; do
    output="${TMPDIR:-/tmp}/shared_fp16_reduction_cluster_p${pipelines}_tb.out"
    compile_args=(-g2012 -Wall -s shared_fp16_reduction_cluster_tb \
        -Pshared_fp16_reduction_cluster_tb.PIPELINES="${pipelines}" -o "${output}")
    if [[ -n "${ivl_base}" ]]; then
        compile_args=(-B "${ivl_base}" "${compile_args[@]}")
    fi
    "${iverilog_bin}" "${compile_args[@]}" \
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

vector_generator="${TMPDIR:-/tmp}/generate_fp16_add_vectors"
vector_file="${TMPDIR:-/tmp}/fp16_add_vectors.txt"
g++ -std=c++11 -Wall -Wextra -Wno-class-memaccess -Ilib \
    rtl/tools/generate_fp16_add_vectors.cpp -o "${vector_generator}"
"${vector_generator}" "${vector_file}"
output="${TMPDIR:-/tmp}/fp16_add_random_tb.out"
compile_args=(-g2012 -Wall -s fp16_add_random_tb -o "${output}")
if [[ -n "${ivl_base}" ]]; then
    compile_args=(-B "${ivl_base}" "${compile_args[@]}")
fi
"${iverilog_bin}" "${compile_args[@]}" \
    rtl/fp16_add.sv rtl/tb/fp16_add_random_tb.sv
if [[ -n "${ivl_base}" ]]; then
    "${vvp_bin}" -M "${ivl_base}" "${output}" +VECTORS="${vector_file}"
else
    "${vvp_bin}" "${output}" +VECTORS="${vector_file}"
fi

output="${TMPDIR:-/tmp}/logic_die_64ch_fp16_timed_payload_tb.out"
compile_args=(-g2012 -Wall -s logic_die_64ch_fp16_timed_payload_tb -o "${output}")
if [[ -n "${ivl_base}" ]]; then
    compile_args=(-B "${ivl_base}" "${compile_args[@]}")
fi
"${iverilog_bin}" "${compile_args[@]}" \
    rtl/fp16_add.sv rtl/bank_local_reduction_buffer.sv \
    rtl/logic_die_link_arbiter.sv rtl/logic_die_dual_link_arbiter.sv \
    rtl/logic_die_64ch_reduction_top.sv \
    rtl/tb/logic_die_64ch_fp16_timed_payload_tb.sv
if [[ -n "${ivl_base}" ]]; then
    "${vvp_bin}" -M "${ivl_base}" "${output}"
else
    "${vvp_bin}" "${output}"
fi

output="${TMPDIR:-/tmp}/logic_die_512source_fp16_payload_tb.out"
compile_args=(-g2012 -Wall -s logic_die_512source_fp16_payload_tb -o "${output}")
if [[ -n "${ivl_base}" ]]; then
    compile_args=(-B "${ivl_base}" "${compile_args[@]}")
fi
"${iverilog_bin}" "${compile_args[@]}" \
    rtl/fp16_add.sv rtl/bank_local_reduction_buffer.sv \
    rtl/bank_local_fp16_reduction.sv rtl/tb/logic_die_512source_fp16_payload_tb.sv
if [[ -n "${ivl_base}" ]]; then
    "${vvp_bin}" -M "${ivl_base}" "${output}"
else
    "${vvp_bin}" "${output}"
fi

output="${TMPDIR:-/tmp}/bank_local_fp16_reduction_tb.out"
compile_args=(-g2012 -Wall -s bank_local_fp16_reduction_tb -o "${output}")
if [[ -n "${ivl_base}" ]]; then
    compile_args=(-B "${ivl_base}" "${compile_args[@]}")
fi
"${iverilog_bin}" "${compile_args[@]}" \
    rtl/fp16_add.sv rtl/bank_local_reduction_buffer.sv \
    rtl/bank_local_fp16_reduction.sv rtl/tb/bank_local_fp16_reduction_tb.sv
if [[ -n "${ivl_base}" ]]; then
    "${vvp_bin}" -M "${ivl_base}" "${output}"
else
    "${vvp_bin}" "${output}"
fi

output="${TMPDIR:-/tmp}/logic_die_64ch_reduction_top.out"
compile_args=(-g2012 -Wall -s logic_die_64ch_reduction_top -o "${output}")
if [[ -n "${ivl_base}" ]]; then
    compile_args=(-B "${ivl_base}" "${compile_args[@]}")
fi
"${iverilog_bin}" "${compile_args[@]}" \
    rtl/fp16_add.sv \
    rtl/bank_local_reduction_buffer.sv \
    rtl/logic_die_link_arbiter.sv \
    rtl/logic_die_dual_link_arbiter.sv \
    rtl/logic_die_64ch_reduction_top.sv
echo "LOGIC_DIE_64CH_REDUCTION_TOP ELABORATION PASS"

output="${TMPDIR:-/tmp}/logic_die_64ch_trace_replay_tb.out"
compile_args=(-g2012 -Wall -s logic_die_64ch_trace_replay_tb -o "${output}")
if [[ -n "${ivl_base}" ]]; then
    compile_args=(-B "${ivl_base}" "${compile_args[@]}")
fi
"${iverilog_bin}" "${compile_args[@]}" \
    rtl/fp16_add.sv \
    rtl/bank_local_reduction_buffer.sv \
    rtl/logic_die_link_arbiter.sv \
    rtl/logic_die_dual_link_arbiter.sv \
    rtl/logic_die_64ch_reduction_top.sv \
    rtl/tb/logic_die_64ch_trace_replay_tb.sv

if [[ -n "${ivl_base}" ]]; then
    "${vvp_bin}" -M "${ivl_base}" "${output}"
else
    "${vvp_bin}" "${output}"
fi

output="${TMPDIR:-/tmp}/logic_die_64ch_reduction_top_tb.out"
compile_args=(-g2012 -Wall -s logic_die_64ch_reduction_top_tb -o "${output}")
if [[ -n "${ivl_base}" ]]; then
    compile_args=(-B "${ivl_base}" "${compile_args[@]}")
fi
"${iverilog_bin}" "${compile_args[@]}" \
    rtl/fp16_add.sv \
    rtl/bank_local_reduction_buffer.sv \
    rtl/logic_die_link_arbiter.sv \
    rtl/logic_die_dual_link_arbiter.sv \
    rtl/logic_die_64ch_reduction_top.sv \
    rtl/tb/logic_die_64ch_reduction_top_tb.sv

if [[ -n "${ivl_base}" ]]; then
    "${vvp_bin}" -M "${ivl_base}" "${output}"
else
    "${vvp_bin}" "${output}"
fi

output="${TMPDIR:-/tmp}/logic_die_dual_link_stress_tb.out"
compile_args=(-g2012 -Wall -s logic_die_dual_link_stress_tb -o "${output}")
if [[ -n "${ivl_base}" ]]; then
    compile_args=(-B "${ivl_base}" "${compile_args[@]}")
fi
"${iverilog_bin}" "${compile_args[@]}" \
    rtl/logic_die_dual_link_arbiter.sv \
    rtl/tb/logic_die_dual_link_stress_tb.sv

if [[ -n "${ivl_base}" ]]; then
    "${vvp_bin}" -M "${ivl_base}" "${output}"
else
    "${vvp_bin}" "${output}"
fi

output="${TMPDIR:-/tmp}/hierarchical_reduction_path_tb.out"
compile_args=(-g2012 -Wall -s hierarchical_reduction_path_tb -o "${output}")
if [[ -n "${ivl_base}" ]]; then
    compile_args=(-B "${ivl_base}" "${compile_args[@]}")
fi
"${iverilog_bin}" "${compile_args[@]}" \
    rtl/bank_local_reduction_buffer.sv \
    rtl/logic_die_dual_link_arbiter.sv \
    rtl/hierarchical_reduction_path.sv \
    rtl/tb/hierarchical_reduction_path_tb.sv

if [[ -n "${ivl_base}" ]]; then
    "${vvp_bin}" -M "${ivl_base}" "${output}"
else
    "${vvp_bin}" "${output}"
fi

output="${TMPDIR:-/tmp}/logic_die_dual_link_arbiter_tb.out"
compile_args=(-g2012 -Wall -s logic_die_dual_link_arbiter_tb -o "${output}")
if [[ -n "${ivl_base}" ]]; then
    compile_args=(-B "${ivl_base}" "${compile_args[@]}")
fi
"${iverilog_bin}" "${compile_args[@]}" \
    rtl/logic_die_dual_link_arbiter.sv \
    rtl/tb/logic_die_dual_link_arbiter_tb.sv

if [[ -n "${ivl_base}" ]]; then
    "${vvp_bin}" -M "${ivl_base}" "${output}"
else
    "${vvp_bin}" "${output}"
fi

output="${TMPDIR:-/tmp}/logic_die_link_arbiter_tb.out"
compile_args=(-g2012 -Wall -s logic_die_link_arbiter_tb -o "${output}")
if [[ -n "${ivl_base}" ]]; then
    compile_args=(-B "${ivl_base}" "${compile_args[@]}")
fi
"${iverilog_bin}" "${compile_args[@]}" \
    rtl/logic_die_link_arbiter.sv \
    rtl/tb/logic_die_link_arbiter_tb.sv

if [[ -n "${ivl_base}" ]]; then
    "${vvp_bin}" -M "${ivl_base}" "${output}"
else
    "${vvp_bin}" "${output}"
fi

bash rtl/run_shared_trace_tests.sh
