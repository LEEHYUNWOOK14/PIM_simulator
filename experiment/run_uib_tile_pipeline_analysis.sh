#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/experiment/results/uib_tile_pipeline_analysis.csv}"
TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

extract_marker() {
  local line="$1" key="$2"
  printf '%s\n' "$line" | grep -o "${key}\[[0-9]*\]" | head -n 1 | sed -E 's/.*\[([0-9]+)\]/\1/'
}

cd "$ROOT_DIR"
FILL_POLICY=row_interleaved FILL_CHANNELS_LIST=32 \
BUFFER_WRITE_PORTS=0 BUFFER_WRITE_LATENCY=1 \
POST_FILL_GUARD_CYCLES=0 EPOCH_RELEASE=true \
ONLINE_QUEUE_BACKPRESSURE=true BROADCAST_QUEUE_DEPTH=128 \
HIERARCHY_READY_BYPASS=true RESULT_FILE="$TMP_FILE" \
  bash "$ROOT_DIR/experiment/run_shared_weight_fill_channel_sweep.sh" >/dev/null

stage_header="$(head -n 1 "$TMP_FILE")"
stage_row="$(tail -n 1 "$TMP_FILE")"
pipeline_output="$(./sim --gtest_filter=HierarchyTilePipelineTest.UsesMeasuredUibStagesWithDepthwiseHalo 2>&1)"
pipeline_line="$(printf '%s\n' "$pipeline_output" | grep HIERARCHY_TILE_PIPELINE_RESULT)"

csv_field() {
  local key="$1"
  awk -F, -v key="$key" -v header="$stage_header" -v row="$stage_row" 'BEGIN {
    count = split(header, names, ","); split(row, values, ",");
    for (i = 1; i <= count; i++) if (names[i] == key) { print values[i]; exit }
  }'
}

printf 'height,width,expand_stage_cycles,depthwise_stage_cycles,project_stage_cycles,add_stage_cycles,relu_stage_cycles,sequential_cycles,pipelined_cycles,overlap_gain_cycles,first_depthwise_start,last_expand_end,first_project_start,logic_resource_cycles,bank_resource_cycles\n' > "$RESULT_FILE"
printf '14,14,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
  "$(csv_field expand_stage_cycles)" "$(csv_field depthwise_stage_cycles)" \
  "$(csv_field project_stage_cycles)" "$(csv_field add_stage_cycles)" \
  "$(csv_field relu_stage_cycles)" \
  "$(extract_marker "$pipeline_line" sequential_cycles)" \
  "$(extract_marker "$pipeline_line" pipelined_cycles)" \
  "$(extract_marker "$pipeline_line" overlap_gain_cycles)" \
  "$(extract_marker "$pipeline_line" first_depthwise_start)" \
  "$(extract_marker "$pipeline_line" last_expand_end)" \
  "$(extract_marker "$pipeline_line" first_project_start)" \
  "$(extract_marker "$pipeline_line" logic_resource_cycles)" \
  "$(extract_marker "$pipeline_line" bank_resource_cycles)" >> "$RESULT_FILE"

echo "Result: $RESULT_FILE"
column -s, -t "$RESULT_FILE" 2>/dev/null || cat "$RESULT_FILE"
