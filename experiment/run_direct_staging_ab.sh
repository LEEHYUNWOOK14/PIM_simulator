#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT_DIR/experiment/run_shared_weight_fill_channel_sweep.sh"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/experiment/results/direct_staging_ab.csv}"
STAGE_RESULT_FILE="${STAGE_RESULT_FILE:-$ROOT_DIR/experiment/results/direct_staging_stage_breakdown.csv}"

extract() {
  local line="$1" key="$2"
  printf '%s\n' "$line" | grep -o "${key}\[[0-9]*\]" | tail -n 1 | sed -E 's/.*\[([0-9]+)\]/\1/'
}

printf 'direct_staging,result,outputs_checked,total_cycle,modeled_writes,fill_completed_writes,fill_activates,fill_precharges,bank_state_any_cycles,bank_state_all_active_cycles,bank_state_only_cycles,hierarchy_union_all_active_cycles\n' > "$RESULT_FILE"
printf 'direct_staging,result,expand_cycles,expand_bank_only,expand_bank_all,expand_hierarchy_all,depthwise_cycles,depthwise_bank_only,depthwise_bank_all,depthwise_hierarchy_all,project_cycles,project_bank_only,project_bank_all,project_hierarchy_all,add_cycles,add_bank_only,add_bank_all,add_hierarchy_all,relu_cycles,relu_bank_only,relu_bank_all,relu_hierarchy_all,total_cycle\n' > "$STAGE_RESULT_FILE"

for direct in false true; do
  echo "[Full UIB direct staging=$direct]"
  output="$(
    RAW_TEST_FILTER=MobileNetV4WorkloadTest.ActualShapeUibRunsEndToEnd \
    RAW_FILL_CHANNELS=32 HIERARCHY_SOURCE_QUEUES=true \
    OUTPUT_BUFFER_ENABLE=true OUTPUT_BUFFER_ENTRIES=2 \
    OUTPUT_DRAIN_LATENCY=4 OUTPUT_DRAIN_BW=8 \
    HAB_RESIDENCY=true MODE_TRANSITION_LATENCY=32 \
    PIM_RUN_WATCHDOG_CYCLES=0 EPOCH_RELEASE=true \
    ONLINE_QUEUE_BACKPRESSURE=true BROADCAST_QUEUE_DEPTH=128 \
    HIERARCHY_READY_BYPASS=true FILL_POLICY=row_interleaved \
    DIRECT_STAGING_COMMAND_PATH="$direct" bash "$RUNNER" 2>&1
  )"
  main_line="$(printf '%s\n' "$output" | grep MOBILENETV4_ACTUAL_UIB_RESULT | tail -n 1)"
  global_line="$(printf '%s\n' "$output" | grep GLOBAL_BLOCKED_RESULT | tail -n 1)"
  exclusive_line="$(printf '%s\n' "$output" | grep GLOBAL_EXCLUSIVE_BLOCKED_RESULT | tail -n 1)"
  stage_line="$(printf '%s\n' "$output" | grep STAGE_BLOCKED_RESULT | tail -n 1)"
  status=FAIL
  if printf '%s\n' "$output" | grep -q '\[  PASSED  \] 1 test'; then status=PASS; fi
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$direct" "$status" "$(extract "$main_line" outputs_checked)" \
    "$(extract "$main_line" total_cycle)" "$(extract "$main_line" modeled_writes)" \
    "$(extract "$main_line" logic_weight_fill_completed_writes)" \
    "$(extract "$main_line" logic_weight_fill_activates)" \
    "$(extract "$main_line" logic_weight_fill_precharges)" \
    "$(extract "$global_line" bank_state_any_cycles)" \
    "$(extract "$global_line" bank_state_all_active_cycles)" \
    "$(extract "$exclusive_line" bank_state_only_cycles)" \
    "$(extract "$exclusive_line" hierarchy_union_all_active_cycles)" >> "$RESULT_FILE"
  [[ "$status" == "PASS" ]] || { printf '%s\n' "$output" >&2; exit 1; }
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$direct" "$status" \
    "$(extract "$stage_line" expand_cycles)" "$(extract "$stage_line" expand_bank_only)" \
    "$(extract "$stage_line" expand_bank_all)" "$(extract "$stage_line" expand_hierarchy_all)" \
    "$(extract "$stage_line" depthwise_cycles)" "$(extract "$stage_line" depthwise_bank_only)" \
    "$(extract "$stage_line" depthwise_bank_all)" "$(extract "$stage_line" depthwise_hierarchy_all)" \
    "$(extract "$stage_line" project_cycles)" "$(extract "$stage_line" project_bank_only)" \
    "$(extract "$stage_line" project_bank_all)" "$(extract "$stage_line" project_hierarchy_all)" \
    "$(extract "$stage_line" add_cycles)" "$(extract "$stage_line" add_bank_only)" \
    "$(extract "$stage_line" add_bank_all)" "$(extract "$stage_line" add_hierarchy_all)" \
    "$(extract "$stage_line" relu_cycles)" "$(extract "$stage_line" relu_bank_only)" \
    "$(extract "$stage_line" relu_bank_all)" "$(extract "$stage_line" relu_hierarchy_all)" \
    "$(extract "$stage_line" total_cycle)" >> "$STAGE_RESULT_FILE"
done

echo "Result: $RESULT_FILE"
column -s, -t "$RESULT_FILE" 2>/dev/null || cat "$RESULT_FILE"
echo "Stage result: $STAGE_RESULT_FILE"
column -s, -t "$STAGE_RESULT_FILE" 2>/dev/null || cat "$STAGE_RESULT_FILE"
