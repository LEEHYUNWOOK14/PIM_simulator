#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT_DIR/experiment/run_shared_weight_fill_channel_sweep.sh"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/experiment/results/issuability_mode_latency_ab.csv}"
GLOBAL_RESULT_FILE="${GLOBAL_RESULT_FILE:-$ROOT_DIR/experiment/results/global_blocked_mode_latency_ab.csv}"
PREDICATE_RESULT_FILE="${PREDICATE_RESULT_FILE:-$ROOT_DIR/experiment/results/global_predicate_blocked_mode_latency_ab.csv}"
EXCLUSIVE_RESULT_FILE="${EXCLUSIVE_RESULT_FILE:-$ROOT_DIR/experiment/results/global_exclusive_blocked_mode_latency_ab.csv}"
LATENCIES="${LATENCIES:-0 32}"

extract() {
  local line="$1" key="$2"
  printf '%s\n' "$line" | grep -o "${key}\[[0-9]*\]" | tail -n 1 | sed -E 's/.*\[([0-9]+)\]/\1/'
}

printf 'mode_latency,result,outputs_checked,total_cycle,rank_rejects,rank_mode_rejects,rank_logic_queue_rejects,rank_mode_blocked_controller_cycles,rank_logic_queue_blocked_controller_cycles,logic_busy_attempts,logic_busy_wall_cycles,mode_attempts,mode_wall_cycles,bank_state_attempts,bank_state_wall_cycles,timing_attempts,timing_wall_cycles,row_mismatch_attempts,row_mismatch_wall_cycles,row_limit_attempts,row_limit_wall_cycles,xaw_attempts,xaw_wall_cycles,bank_state_blocked_controller_cycles,timing_blocked_controller_cycles,row_mismatch_blocked_controller_cycles,mode_blocked_controller_cycles\n' > "$RESULT_FILE"
printf 'mode_latency,result,total_cycle,rank_mode_any_cycles,rank_mode_all_active_cycles,rank_mode_peak_channels,bank_state_any_cycles,bank_state_all_active_cycles,bank_state_peak_channels,timing_any_cycles,timing_all_active_cycles,timing_peak_channels,row_mismatch_any_cycles,row_mismatch_all_active_cycles,row_mismatch_peak_channels\n' > "$GLOBAL_RESULT_FILE"
printf 'mode_latency,result,total_cycle,epoch_any_cycles,epoch_all_active_cycles,epoch_peak_channels,barrier_any_cycles,barrier_all_active_cycles,barrier_peak_channels,write_bus_any_cycles,write_bus_all_active_cycles,write_bus_peak_channels\n' > "$PREDICATE_RESULT_FILE"
printf 'mode_latency,result,total_cycle,hierarchy_union_any_cycles,hierarchy_union_all_active_cycles,hierarchy_union_peak_channels,bank_all_no_hierarchy_cycles,bank_all_with_hierarchy_cycles,bank_state_only_cycles,hierarchy_all_no_issuability_cycles,bank_hierarchy_all_intersection_cycles\n' > "$EXCLUSIVE_RESULT_FILE"

for latency in $LATENCIES; do
  echo "[Full UIB issuability: mode latency=$latency]"
  output="$(
    RAW_TEST_FILTER=MobileNetV4WorkloadTest.ActualShapeUibRunsEndToEnd \
    RAW_FILL_CHANNELS=32 HIERARCHY_SOURCE_QUEUES=true \
    OUTPUT_BUFFER_ENABLE=true OUTPUT_BUFFER_ENTRIES=2 \
    OUTPUT_DRAIN_LATENCY=4 OUTPUT_DRAIN_BW=8 \
    HAB_RESIDENCY=true MODE_TRANSITION_LATENCY="$latency" \
    PIM_RUN_WATCHDOG_CYCLES=0 EPOCH_RELEASE=true \
    ONLINE_QUEUE_BACKPRESSURE=true BROADCAST_QUEUE_DEPTH=128 \
    HIERARCHY_READY_BYPASS=true FILL_POLICY=row_interleaved \
    bash "$RUNNER" 2>&1
  )"
  main_line="$(printf '%s\n' "$output" | grep MOBILENETV4_ACTUAL_UIB_RESULT | tail -n 1)"
  issue_line="$(printf '%s\n' "$output" | grep COMMAND_ISSUABILITY_RESULT | tail -n 1)"
  global_line="$(printf '%s\n' "$output" | grep GLOBAL_BLOCKED_RESULT | tail -n 1)"
  predicate_line="$(printf '%s\n' "$output" | grep GLOBAL_PREDICATE_BLOCKED_RESULT | tail -n 1)"
  exclusive_line="$(printf '%s\n' "$output" | grep GLOBAL_EXCLUSIVE_BLOCKED_RESULT | tail -n 1)"
  status=FAIL
  if printf '%s\n' "$output" | grep -q '\[  PASSED  \] 1 test'; then status=PASS; fi
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$latency" "$status" \
    "$(extract "$main_line" outputs_checked)" "$(extract "$main_line" total_cycle)" \
    "$(extract "$main_line" rank_command_rejects)" \
    "$(extract "$main_line" rank_mode_transition_rejects)" \
    "$(extract "$main_line" rank_logic_queue_rejects)" \
    "$(extract "$issue_line" rank_mode_blocked_controller_cycles)" \
    "$(extract "$issue_line" rank_logic_queue_blocked_controller_cycles)" \
    "$(extract "$issue_line" logic_busy_attempts)" \
    "$(extract "$issue_line" logic_busy_wall_cycles)" \
    "$(extract "$issue_line" mode_attempts)" "$(extract "$issue_line" mode_wall_cycles)" \
    "$(extract "$issue_line" bank_state_attempts)" \
    "$(extract "$issue_line" bank_state_wall_cycles)" \
    "$(extract "$issue_line" timing_attempts)" "$(extract "$issue_line" timing_wall_cycles)" \
    "$(extract "$issue_line" row_mismatch_attempts)" \
    "$(extract "$issue_line" row_mismatch_wall_cycles)" \
    "$(extract "$issue_line" row_limit_attempts)" \
    "$(extract "$issue_line" row_limit_wall_cycles)" \
    "$(extract "$issue_line" xaw_attempts)" "$(extract "$issue_line" xaw_wall_cycles)" \
    "$(extract "$issue_line" bank_state_blocked_controller_cycles)" \
    "$(extract "$issue_line" timing_blocked_controller_cycles)" \
    "$(extract "$issue_line" row_mismatch_blocked_controller_cycles)" \
    "$(extract "$issue_line" mode_blocked_controller_cycles)" \
    >> "$RESULT_FILE"
  [[ "$status" == "PASS" ]] || { printf '%s\n' "$output" >&2; exit 1; }
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$latency" "$status" "$(extract "$global_line" total_cycle)" \
    "$(extract "$global_line" rank_mode_any_cycles)" \
    "$(extract "$global_line" rank_mode_all_active_cycles)" \
    "$(extract "$global_line" rank_mode_peak_channels)" \
    "$(extract "$global_line" bank_state_any_cycles)" \
    "$(extract "$global_line" bank_state_all_active_cycles)" \
    "$(extract "$global_line" bank_state_peak_channels)" \
    "$(extract "$global_line" timing_any_cycles)" \
    "$(extract "$global_line" timing_all_active_cycles)" \
    "$(extract "$global_line" timing_peak_channels)" \
    "$(extract "$global_line" row_mismatch_any_cycles)" \
    "$(extract "$global_line" row_mismatch_all_active_cycles)" \
    "$(extract "$global_line" row_mismatch_peak_channels)" >> "$GLOBAL_RESULT_FILE"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$latency" "$status" "$(extract "$predicate_line" total_cycle)" \
    "$(extract "$predicate_line" epoch_any_cycles)" \
    "$(extract "$predicate_line" epoch_all_active_cycles)" \
    "$(extract "$predicate_line" epoch_peak_channels)" \
    "$(extract "$predicate_line" barrier_any_cycles)" \
    "$(extract "$predicate_line" barrier_all_active_cycles)" \
    "$(extract "$predicate_line" barrier_peak_channels)" \
    "$(extract "$predicate_line" write_bus_any_cycles)" \
    "$(extract "$predicate_line" write_bus_all_active_cycles)" \
    "$(extract "$predicate_line" write_bus_peak_channels)" >> "$PREDICATE_RESULT_FILE"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$latency" "$status" "$(extract "$exclusive_line" total_cycle)" \
    "$(extract "$exclusive_line" hierarchy_union_any_cycles)" \
    "$(extract "$exclusive_line" hierarchy_union_all_active_cycles)" \
    "$(extract "$exclusive_line" hierarchy_union_peak_channels)" \
    "$(extract "$exclusive_line" bank_all_no_hierarchy_cycles)" \
    "$(extract "$exclusive_line" bank_all_with_hierarchy_cycles)" \
    "$(extract "$exclusive_line" bank_state_only_cycles)" \
    "$(extract "$exclusive_line" hierarchy_all_no_issuability_cycles)" \
    "$(extract "$exclusive_line" bank_hierarchy_all_intersection_cycles)" \
    >> "$EXCLUSIVE_RESULT_FILE"
done

echo "Result: $RESULT_FILE"
column -s, -t "$RESULT_FILE" 2>/dev/null || cat "$RESULT_FILE"
echo "Global result: $GLOBAL_RESULT_FILE"
column -s, -t "$GLOBAL_RESULT_FILE" 2>/dev/null || cat "$GLOBAL_RESULT_FILE"
echo "Predicate result: $PREDICATE_RESULT_FILE"
column -s, -t "$PREDICATE_RESULT_FILE" 2>/dev/null || cat "$PREDICATE_RESULT_FILE"
echo "Exclusive result: $EXCLUSIVE_RESULT_FILE"
column -s, -t "$EXCLUSIVE_RESULT_FILE" 2>/dev/null || cat "$EXCLUSIVE_RESULT_FILE"
