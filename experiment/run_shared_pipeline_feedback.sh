#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="${repo_root}/system_hbm_1ch.ini"
result_dir="${repo_root}/experiment/results/shared_pipeline_feedback"
csv="${repo_root}/experiment/results/shared_pipeline_feedback.csv"
backup="$(mktemp)"
mkdir -p "${result_dir}"
cp "${config}" "${backup}"
restore_config() { cp "${backup}" "${config}"; rm -f "${backup}"; }
trap restore_config EXIT
set_value() { sed -i "s|^$1=.*|$1=$2|" "${config}"; }

set_value HIERARCHY_SOURCE_QUEUES true
set_value LOGIC_DEPTHWISE_ACCUMULATION true
set_value BANK_LOCAL_AGGREGATION_TAPS 3
set_value BANK_LOCAL_ACCUMULATOR_ENTRIES 128
set_value BANK_LOCAL_ACCUMULATOR_PORTS 1
set_value BANK_LOCAL_ACCUMULATOR_LATENCY 1
set_value BANK_LOCAL_ACCUMULATOR_BANKS 8
set_value BANK_LOCAL_ACCUMULATOR_TILE_BATCH 1
set_value LOGIC_ACCUMULATOR_BW 64
set_value LOGIC_ACCUMULATOR_LATENCY 4
set_value LOGIC_ACCUMULATOR_TRACE_FILE none

echo "overlap,pipelines,logic_latency,link_bytes_per_cycle,total_cycle,overlap_cycles,wait_cycles,partial_bursts,final_bursts" > "${csv}"
cd "${repo_root}"
for overlap in false true; do
    set_value LOGIC_ACCUMULATOR_OVERLAP "${overlap}"
    for pipelines in 1 2 4; do
        set_value LOGIC_ACCUMULATOR_PIPELINES "${pipelines}"
        log="${result_dir}/overlap_${overlap}_pipelines_${pipelines}.log"
        ./sim --gtest_filter=MobileNetV4WorkloadTest.DepthwiseHierarchicalAccumulatorOneChannel \
            | tee "${log}"
        line="$(grep 'DEPTHWISE_HIERARCHICAL_ONE_CHANNEL_RESULT' "${log}" | tail -1)"
        field() { sed -n "s/.* $1\[\([0-9]*\)\].*/\1/p" <<<"${line}"; }
        echo "${overlap},${pipelines},4,64,$(field total_cycle),$(field overlap_cycles),$(field wait_cycles),$(field partial_bursts),$(field final_bursts)" >> "${csv}"
    done
done
cat "${csv}"
