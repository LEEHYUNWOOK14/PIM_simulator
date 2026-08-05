#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"
config="system_hbm_64ch.ini"
backup="$(mktemp)"
cp "${config}" "${backup}"
restore() {
    cp "${backup}" "${config}"
    rm -f "${backup}"
}
trap restore EXIT

set_value() {
    sed -i -E "s|^$1=.*|$1=$2|" "${config}"
}

set_value ENABLE_BANK_SIDE_PIM true
set_value ENABLE_LOGIC_DIE_PIM true
set_value PIM_TARGET hybrid
set_value HIERARCHY_SOURCE_QUEUES true
set_value NUM_LOGIC_PIM_UNITS 32
set_value LOGIC_PCU_QUEUE_DEPTH 64

./sim --gtest_filter=MobileNetV4WorkloadTest.MiniatureUibRunsEndToEnd |
    tee experiment/results/hard_pcu_queue_smoke.log
