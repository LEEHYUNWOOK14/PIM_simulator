#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/experiment/results/hierarchy_shared_drain.csv}"

extract() {
  local line="$1" key="$2"
  printf '%s\n' "$line" | grep -o "${key}\[[0-9]*\]" | head -n 1 | sed -E 's/.*\[([0-9]+)\]/\1/'
}

output="$(
  RAW_TEST_FILTER=MobileNetV4WorkloadTest.BankDepthwiseStageAndLogicPointwiseShareDrain \
  RAW_FILL_CHANNELS=32 FILL_POLICY=row_interleaved \
  BUFFER_WRITE_PORTS=0 BUFFER_WRITE_LATENCY=1 \
  EPOCH_RELEASE=true ONLINE_QUEUE_BACKPRESSURE=true \
  BROADCAST_QUEUE_DEPTH=128 HIERARCHY_READY_BYPASS=true \
  HIERARCHY_SOURCE_QUEUES=${HIERARCHY_SOURCE_QUEUES:-false} \
    bash "$ROOT_DIR/experiment/run_shared_weight_fill_channel_sweep.sh" 2>&1
)" || {
  printf '%s\n' "$output" >&2
  exit 1
}

line="$(printf '%s\n' "$output" | grep HIERARCHY_SHARED_DRAIN_RESULT)"
printf 'bank_stages_enqueued,bank_stages_completed,logic_rows_enqueued,logic_outputs_checked,shared_drain_cycles,bank_issues,logic_issues,bank_first_issue,bank_last_issue,logic_first_issue,logic_last_issue,overlapping_issue_cycles,overlapping_window_cycles,pending_after_drain\n' > "$RESULT_FILE"
printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
  "$(extract "$line" bank_stages_enqueued)" \
  "$(extract "$line" bank_stages_completed)" \
  "$(extract "$line" logic_rows_enqueued)" \
  "$(extract "$line" logic_outputs_checked)" \
  "$(extract "$line" shared_drain_cycles)" \
  "$(extract "$line" bank_issues)" \
  "$(extract "$line" logic_issues)" \
  "$(extract "$line" bank_first_issue)" \
  "$(extract "$line" bank_last_issue)" \
  "$(extract "$line" logic_first_issue)" \
  "$(extract "$line" logic_last_issue)" \
  "$(extract "$line" overlapping_issue_cycles)" \
  "$(extract "$line" overlapping_window_cycles)" \
  "$(extract "$line" pending_after_drain)" >> "$RESULT_FILE"

echo "Result: $RESULT_FILE"
column -s, -t "$RESULT_FILE" 2>/dev/null || cat "$RESULT_FILE"
