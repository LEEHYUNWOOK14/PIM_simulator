#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="${repo_root}/system_hbm_64ch.ini"
backup="$(mktemp)"
mode="${1:-all}"

cp "${config}" "${backup}"
restore_config() {
    cp "${backup}" "${config}"
    rm -f "${backup}"
}
trap restore_config EXIT

set_value() {
    local key="$1" value="$2"
    sed -i "s|^${key}=.*|${key}=${value}|" "${config}"
}

run_cpp() {
    set_value HIERARCHY_SOURCE_QUEUES true
    set_value LOGIC_DEPTHWISE_ACCUMULATION true
    set_value LOGIC_ACCUMULATOR_OVERLAP true
    set_value BANK_LOCAL_AGGREGATION_TAPS 3
    set_value BANK_LOCAL_ACCUMULATOR_ENTRIES 128
    set_value BANK_LOCAL_ACCUMULATOR_PORTS 1
    set_value BANK_LOCAL_ACCUMULATOR_LATENCY 1
    set_value BANK_LOCAL_ACCUMULATOR_BANKS 8
    set_value BANK_LOCAL_ACCUMULATOR_TILE_BATCH 1
    set_value LOGIC_ACCUMULATOR_TRACE_FILE \
        experiment/results/depthwise_actual_payload_trace.csv
    cd "${repo_root}"
    ./sim --gtest_filter=MobileNetV4WorkloadTest.DepthwiseHierarchicalActualShape
}

run_rtl() {
    cd "${repo_root}"
    bash rtl/run_tests.sh
}

case "${mode}" in
    cpp) run_cpp ;;
    rtl) run_rtl ;;
    all) run_cpp; run_rtl ;;
    *) echo "usage: bash experiment/run_fp16_payload_replay.sh [cpp|rtl|all]" >&2; exit 2 ;;
esac
