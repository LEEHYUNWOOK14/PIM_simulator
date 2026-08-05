#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/experiment/results/nonblocking_pointwise_test.csv}"

extract() {
  local line="$1" key="$2"
  printf '%s\n' "$line" | grep -o "${key}\[[0-9]*\]" | head -n 1 | sed -E 's/.*\[([0-9]+)\]/\1/'
}

output="$(
  RAW_TEST_FILTER='MobileNetV4WorkloadTest.Nonblocking*:MobileNetV4WorkloadTest.PointwiseSpatialSession*:MobileNetV4WorkloadTest.ActivationRowBuffer*' \
  RAW_FILL_CHANNELS=32 FILL_POLICY=row_interleaved \
  BUFFER_WRITE_PORTS=0 BUFFER_WRITE_LATENCY=1 \
  EPOCH_RELEASE=true ONLINE_QUEUE_BACKPRESSURE=true \
  BROADCAST_QUEUE_DEPTH=128 HIERARCHY_READY_BYPASS=true \
    bash "$ROOT_DIR/experiment/run_shared_weight_fill_channel_sweep.sh" 2>&1
)" || {
  printf '%s\n' "$output" >&2
  exit 1
}
line="$(printf '%s\n' "$output" | grep NONBLOCKING_POINTWISE_RESULT)"
tile_line="$(printf '%s\n' "$output" | grep NONBLOCKING_TILE_ROW_RESULT)"
session_line="$(printf '%s\n' "$output" | grep POINTWISE_ROW_SESSION_RESULT)"
buffer_line="$(printf '%s\n' "$output" | grep ACTIVATION_ROW_BUFFER_RESULT)"
printf 'positions,input_channels,output_channels,enqueue_cycles,wait_cycles,outputs_checked,total_cycle,halo_input_rows,halo_output_rows_checked,halo_width,halo_channels,halo_outputs_checked,halo_total_cycle,session_height,session_width,session_row_ranges,session_completed_rows,session_reused_ranges,session_weight_fill_bursts,session_reused_fill_bursts,session_crf_program_calls,session_reused_crf_calls,session_released_depthwise_rows,session_line_buffer_peak_rows,session_outputs_checked,session_total_cycle,buffer_input_rows,buffer_released_rows,buffer_kernel,buffer_peak_rows,buffer_values_checked\n' > "$RESULT_FILE"
printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
  "$(extract "$line" positions)" "$(extract "$line" input_channels)" \
  "$(extract "$line" output_channels)" "$(extract "$line" enqueue_cycles)" \
  "$(extract "$line" wait_cycles)" "$(extract "$line" outputs_checked)" \
  "$(extract "$line" total_cycle)" \
  "$(extract "$tile_line" input_rows)" \
  "$(extract "$tile_line" output_rows_checked)" \
  "$(extract "$tile_line" width)" "$(extract "$tile_line" channels)" \
  "$(extract "$tile_line" outputs_checked)" \
  "$(extract "$tile_line" total_cycle)" \
  "$(extract "$session_line" height)" "$(extract "$session_line" width)" \
  "$(extract "$session_line" row_ranges)" \
  "$(extract "$session_line" completed_rows)" \
  "$(extract "$session_line" reused_ranges)" \
  "$(extract "$session_line" weight_fill_bursts)" \
  "$(extract "$session_line" reused_fill_bursts)" \
  "$(extract "$session_line" crf_program_calls)" \
  "$(extract "$session_line" reused_crf_calls)" \
  "$(extract "$session_line" released_depthwise_rows)" \
  "$(extract "$session_line" line_buffer_peak_rows)" \
  "$(extract "$session_line" outputs_checked)" \
  "$(extract "$session_line" total_cycle)" \
  "$(extract "$buffer_line" input_rows)" \
  "$(extract "$buffer_line" released_rows)" \
  "$(extract "$buffer_line" kernel)" \
  "$(extract "$buffer_line" peak_rows)" \
  "$(extract "$buffer_line" values_checked)" >> "$RESULT_FILE"

echo "Result: $RESULT_FILE"
column -s, -t "$RESULT_FILE" 2>/dev/null || cat "$RESULT_FILE"
