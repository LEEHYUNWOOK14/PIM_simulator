#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

config="system_hbm_64ch.ini"
trace="${UIB_TRACE_FILE:-experiment/results/uib_integration_trace.csv}"
log="${UIB_TRACE_LOG:-experiment/results/uib_integration_trace.log}"
backup="$(mktemp)"
cp "${config}" "${backup}"
restore() {
    cp "${backup}" "${config}"
    rm -f "${backup}"
}
trap restore EXIT

set_config() {
    local key="$1"
    local value="$2"
    sed -i -E "s|^${key}=.*|${key}=${value}|" "${config}"
}

set_config ENABLE_BANK_SIDE_PIM true
set_config ENABLE_LOGIC_DIE_PIM true
set_config PIM_TARGET hybrid
set_config HIERARCHY_SOURCE_QUEUES true
set_config NUM_LOGIC_PIM_UNITS "${NUM_LOGIC_PIM_UNITS:-16}"
set_config LOGIC_PCU_QUEUE_DEPTH "${LOGIC_PCU_QUEUE_DEPTH:-0}"
set_config LOGIC_DEPTHWISE_ACCUMULATION true
set_config BANK_LOCAL_AGGREGATION_TAPS 9
set_config LOGIC_ACCUMULATOR_PIPELINES 2
set_config LOGIC_ACCUMULATOR_TRACE_FILE none
set_config LOGIC_UIB_TRACE_FILE "${trace}"

./sim --gtest_filter=MobileNetV4WorkloadTest.ActualShapeUibRunsEndToEnd | tee "${log}"
python3 experiment/verify_uib_integration_trace.py "${trace}"
python3 experiment/analyze_uib_pointwise_requests.py "${trace}.requests.csv"
if [[ "${RUN_TRACE_REPLAYS:-true}" == "true" ]]; then
    python3 experiment/replay_uib_pointwise_pcu_sweep.py "${trace}.requests.csv"
    python3 experiment/replay_uib_bounded_pointwise_scheduler.py "${trace}.requests.csv"
fi
