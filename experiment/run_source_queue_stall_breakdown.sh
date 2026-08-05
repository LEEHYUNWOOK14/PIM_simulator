#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="${LOG_FILE:-$ROOT_DIR/experiment/results/full_uib_source_queue_on_stall_breakdown.log}"

cd "$ROOT_DIR"
RAW_TEST_FILTER=MobileNetV4WorkloadTest.ActualShapeUibRunsEndToEnd \
HIERARCHY_SOURCE_QUEUES=true \
RAW_FILL_CHANNELS="${RAW_FILL_CHANNELS:-32}" \
bash experiment/run_shared_weight_fill_channel_sweep.sh 2>&1 | tee "$LOG_FILE"

echo "Result: $LOG_FILE"
