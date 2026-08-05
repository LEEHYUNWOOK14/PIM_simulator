#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILES=(
  "$ROOT_DIR/ini/HBM2_samsung_2M_16B_x64.ini"
  "$ROOT_DIR/system_hbm.ini"
  "$ROOT_DIR/system_hbm_64ch.ini"
)
BACKUP_DIR="$(mktemp -d)"
LOCK_DIR="${TMPDIR:-/tmp}/stob_pim_config_sweep.lock"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/experiment/results/shared_weight_fill_channel_sweep.csv}"
FILL_CHANNELS_LIST="${FILL_CHANNELS_LIST:-0 4 8 16 32 64}"
TEST_FILTER="${TEST_FILTER:-MobileNetV4WorkloadTest.ActualShapeUibRunsEndToEnd}"
RESULT_MARKER="${RESULT_MARKER:-MOBILENETV4_ACTUAL_UIB_RESULT}"

restore_configs() {
  for config_file in "${CONFIG_FILES[@]}"; do
    cp "$BACKUP_DIR/$(basename "$config_file")" "$config_file"
  done
  rm -rf "$BACKUP_DIR"
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "Another configuration sweep is running: $LOCK_DIR" >&2
  rm -rf "$BACKUP_DIR"
  exit 1
fi

for config_file in "${CONFIG_FILES[@]}"; do
  cp "$config_file" "$BACKUP_DIR/$(basename "$config_file")"
done
trap restore_configs EXIT

set_fill_channels() {
  local channels="$1"
  for config_file in "${CONFIG_FILES[@]}"; do
    perl -0pi -e "s/^ENABLE_BANK_SIDE_PIM=.*/ENABLE_BANK_SIDE_PIM=true/m; \
                  s/^ENABLE_LOGIC_DIE_PIM=.*/ENABLE_LOGIC_DIE_PIM=true/m; \
                  s/^NUM_LOGIC_PIM_UNITS=.*/NUM_LOGIC_PIM_UNITS=${LOGIC_UNITS:-16}/m; \
                  s/^LOGIC_PIM_LATENCY=.*/LOGIC_PIM_LATENCY=2/m; \
                  s/^LOGIC_PIM_BW=.*/LOGIC_PIM_BW=${LOGIC_BW:-64}/m; \
                  s/^HIERARCHY_PIM_BW=.*/HIERARCHY_PIM_BW=64/m; \
                  s/^HIERARCHY_READY_BYPASS=.*/HIERARCHY_READY_BYPASS=${HIERARCHY_READY_BYPASS:-false}/m; \
                  s/^HIERARCHY_SOURCE_QUEUES=.*/HIERARCHY_SOURCE_QUEUES=${HIERARCHY_SOURCE_QUEUES:-false}/m; \
                  s/^LOGIC_COMPACT_OUTPUT=.*/LOGIC_COMPACT_OUTPUT=true/m; \
                  s/^LOGIC_SPATIAL_GROUPING=.*/LOGIC_SPATIAL_GROUPING=true/m; \
                  s/^LOGIC_GLOBAL_SCHEDULER=.*/LOGIC_GLOBAL_SCHEDULER=true/m; \
                  s/^LOGIC_CMD_OVERHEAD=.*/LOGIC_CMD_OVERHEAD=4/m; \
                  s/^LOGIC_CMD_COALESCING=.*/LOGIC_CMD_COALESCING=true/m; \
                  s/^LOGIC_SHARED_WEIGHT_BUFFER=.*/LOGIC_SHARED_WEIGHT_BUFFER=true/m; \
                  s/^LOGIC_WEIGHT_BUFFER_BYTES=.*/LOGIC_WEIGHT_BUFFER_BYTES=65536/m; \
                  s/^LOGIC_WEIGHT_FILL_CHANNELS=.*/LOGIC_WEIGHT_FILL_CHANNELS=${channels}/m; \
                  s/^LOGIC_WEIGHT_FILL_POLICY=.*/LOGIC_WEIGHT_FILL_POLICY=${FILL_POLICY:-round_robin}/m; \
                  s/^LOGIC_WEIGHT_STAGING_ROW=.*/LOGIC_WEIGHT_STAGING_ROW=${STAGING_ROW:-2048}/m; \
                  s/^LOGIC_DIRECT_STAGING_COMMAND_PATH=.*/LOGIC_DIRECT_STAGING_COMMAND_PATH=${DIRECT_STAGING_COMMAND_PATH:-false}/m; \
                  s/^LOGIC_WEIGHT_BUFFER_WRITE_PORTS=.*/LOGIC_WEIGHT_BUFFER_WRITE_PORTS=${BUFFER_WRITE_PORTS:-0}/m; \
                  s/^LOGIC_WEIGHT_BUFFER_WRITE_LATENCY=.*/LOGIC_WEIGHT_BUFFER_WRITE_LATENCY=${BUFFER_WRITE_LATENCY:-1}/m; \
                  s/^LOGIC_POST_FILL_GUARD_CYCLES=.*/LOGIC_POST_FILL_GUARD_CYCLES=${POST_FILL_GUARD_CYCLES:-0}/m; \
                  s/^LOGIC_OUTPUT_BUFFER_ENABLE=.*/LOGIC_OUTPUT_BUFFER_ENABLE=${OUTPUT_BUFFER_ENABLE:-false}/m; \
                  s/^LOGIC_OUTPUT_BUFFER_ENTRIES=.*/LOGIC_OUTPUT_BUFFER_ENTRIES=${OUTPUT_BUFFER_ENTRIES:-2}/m; \
                  s/^LOGIC_OUTPUT_DRAIN_LATENCY=.*/LOGIC_OUTPUT_DRAIN_LATENCY=${OUTPUT_DRAIN_LATENCY:-0}/m; \
                  s/^LOGIC_OUTPUT_DRAIN_BW=.*/LOGIC_OUTPUT_DRAIN_BW=${OUTPUT_DRAIN_BW:-0}/m; \
                  s/^LOGIC_HAB_RESIDENCY=.*/LOGIC_HAB_RESIDENCY=${HAB_RESIDENCY:-false}/m; \
                  s/^LOGIC_MODE_TRANSITION_LATENCY=.*/LOGIC_MODE_TRANSITION_LATENCY=${MODE_TRANSITION_LATENCY:-0}/m; \
                  s/^PIM_RUN_WATCHDOG_CYCLES=.*/PIM_RUN_WATCHDOG_CYCLES=${PIM_RUN_WATCHDOG_CYCLES:-0}/m; \
                  s/^LOGIC_EPOCH_RELEASE=.*/LOGIC_EPOCH_RELEASE=${EPOCH_RELEASE:-false}/m; \
                  s/^LOGIC_BROADCAST_QUEUE_DEPTH=.*/LOGIC_BROADCAST_QUEUE_DEPTH=${BROADCAST_QUEUE_DEPTH:-0}/m; \
                  s/^LOGIC_ONLINE_QUEUE_BACKPRESSURE=.*/LOGIC_ONLINE_QUEUE_BACKPRESSURE=${ONLINE_QUEUE_BACKPRESSURE:-false}/m; \
                  s/^DEBUG_CMD_TRACE=.*/DEBUG_CMD_TRACE=false/m; \
                  s/^PIM_TARGET=.*/PIM_TARGET=hybrid/m" "$config_file"
  done
}

extract() {
  local line="$1" key="$2"
  printf '%s\n' "$line" | grep -o "${key}\[[0-9]*\]" | head -n 1 | \
    sed -E 's/.*\[([0-9]+)\]/\1/'
}

cd "$ROOT_DIR"
scons -j"${BUILD_JOBS:-4}"
if [[ -n "${RAW_TEST_FILTER:-}" ]]; then
  set_fill_channels "${RAW_FILL_CHANNELS:-32}"
  ./sim --gtest_filter="$RAW_TEST_FILTER"
  exit 0
fi
printf 'fill_policy,fill_channels,buffer_write_ports,buffer_write_latency,post_fill_guard_setting,epoch_release,broadcast_queue_depth,online_queue_backpressure,hierarchy_ready_bypass,expand_stage_cycles,depthwise_stage_cycles,project_stage_cycles,add_stage_cycles,relu_stage_cycles,physical_weight_bytes,physical_writes,buffer_fill_bursts,buffer_read_hits,buffer_read_misses,active_channels,completed_fill_writes,min_writes_per_channel,max_writes_per_channel,min_completion_cycle,max_completion_cycle,fill_activates,fill_precharges,fill_barrier_cycles,port_wait_cycles,post_fill_guard_cycles,release_epochs,release_max_streams,release_complete_masks,release_incomplete_masks,broadcast_masks,broadcast_fanout,broadcast_min_fanout,broadcast_max_fanout,epoch1_masks,epoch1_fanout,epoch1_max_residency,epoch1_total_residency,epoch1_peak_open_masks,epoch1_online_peak_open_masks,epoch1_online_full_events,epoch1_incomplete_expected_masks,epoch2_masks,epoch2_fanout,epoch2_max_residency,epoch2_total_residency,epoch2_peak_open_masks,epoch2_online_peak_open_masks,epoch2_online_full_events,epoch2_incomplete_expected_masks,broadcast_queue_stall_cycles,broadcast_queue_full_events,broadcast_queue_applied_cycles,broadcast_queue_last_pre_stall_cycle,online_issue_blocked_channel_cycles,online_issue_busy_overlap_channel_cycles,blocked_wall_cycles,blocked_streams,min_blocked_per_stream,max_blocked_per_stream,min_issued_per_stream,max_issued_per_stream,blocked_stream_mask_low,blocked_stream_mask_high,command_predicate_reject_cycles,command_predicate_hol_cycles,command_predicate_hol_candidates,command_predicate_hol_max_candidates,command_predicate_bypass_issues,write_queue_cycles,global_commands,global_dispatches,global_coalesced,global_dispatch_overhead_cycles,global_queue_cycles,global_service_cycles,total_refreshes,total_cycle\n' \
  > "$RESULT_FILE"

for channels in $FILL_CHANNELS_LIST; do
  echo "[shared weight fill channels=$channels]"
  set_fill_channels "$channels"
  output=""
  test_passed=false
  for attempt in 1 2 3; do
    if output="$(./sim --gtest_filter="$TEST_FILTER" 2>&1)"; then
      test_passed=true
      break
    fi
    sleep 2
  done
  if [[ "$test_passed" != "true" ]]; then
    printf '%s\n' "$output" >&2
    exit 1
  fi
  line="$(printf '%s\n' "$output" | grep "$RESULT_MARKER" | tail -n 1)"
  row=( \
    "${FILL_POLICY:-round_robin}" "$channels" "${BUFFER_WRITE_PORTS:-0}" \
    "${BUFFER_WRITE_LATENCY:-1}" "${POST_FILL_GUARD_CYCLES:-0}" "${EPOCH_RELEASE:-false}" \
    "${BROADCAST_QUEUE_DEPTH:-0}" \
    "${ONLINE_QUEUE_BACKPRESSURE:-false}" \
    "${HIERARCHY_READY_BYPASS:-false}" \
    "$(extract "$line" expand_stage_cycles)" \
    "$(extract "$line" depthwise_stage_cycles)" \
    "$(extract "$line" project_stage_cycles)" \
    "$(extract "$line" add_stage_cycles)" \
    "$(extract "$line" relu_stage_cycles)" \
    "$(extract "$line" physical_logic_weight_bytes)" "$(extract "$line" writes)" \
    "$(extract "$line" logic_weight_buffer_fill_bursts)" \
    "$(extract "$line" logic_weight_buffer_read_hits)" \
    "$(extract "$line" logic_weight_buffer_read_misses)" \
    "$(extract "$line" logic_weight_fill_active_channels)" \
    "$(extract "$line" logic_weight_fill_completed_writes)" \
    "$(extract "$line" logic_weight_fill_min_writes_per_channel)" \
    "$(extract "$line" logic_weight_fill_max_writes_per_channel)" \
    "$(extract "$line" logic_weight_fill_min_completion_cycle)" \
    "$(extract "$line" logic_weight_fill_max_completion_cycle)" \
    "$(extract "$line" logic_weight_fill_activates)" \
    "$(extract "$line" logic_weight_fill_precharges)" \
    "$(extract "$line" logic_weight_fill_barrier_cycles)" \
    "$(extract "$line" logic_weight_buffer_port_wait_cycles)" \
    "$(extract "$line" logic_post_fill_guard_cycles)" \
    "$(extract "$line" logic_release_epochs)" \
    "$(extract "$line" logic_release_max_streams)" \
    "$(extract "$line" logic_release_complete_masks)" \
    "$(extract "$line" logic_release_incomplete_masks)" \
    "$(extract "$line" logic_broadcast_masks)" \
    "$(extract "$line" logic_broadcast_fanout)" \
    "$(extract "$line" logic_broadcast_min_fanout)" \
    "$(extract "$line" logic_broadcast_max_fanout)" \
    "$(extract "$line" logic_epoch1_masks)" \
    "$(extract "$line" logic_epoch1_fanout)" \
    "$(extract "$line" logic_epoch1_max_residency)" \
    "$(extract "$line" logic_epoch1_total_residency)" \
    "$(extract "$line" logic_epoch1_peak_open_masks)" \
    "$(extract "$line" logic_epoch1_online_peak_open_masks)" \
    "$(extract "$line" logic_epoch1_online_full_events)" \
    "$(extract "$line" logic_epoch1_incomplete_expected_masks)" \
    "$(extract "$line" logic_epoch2_masks)" \
    "$(extract "$line" logic_epoch2_fanout)" \
    "$(extract "$line" logic_epoch2_max_residency)" \
    "$(extract "$line" logic_epoch2_total_residency)" \
    "$(extract "$line" logic_epoch2_peak_open_masks)" \
    "$(extract "$line" logic_epoch2_online_peak_open_masks)" \
    "$(extract "$line" logic_epoch2_online_full_events)" \
    "$(extract "$line" logic_epoch2_incomplete_expected_masks)" \
    "$(extract "$line" logic_broadcast_queue_stall_cycles)" \
    "$(extract "$line" logic_broadcast_queue_full_events)" \
    "$(extract "$line" logic_broadcast_queue_applied_cycles)" \
    "$(extract "$line" logic_broadcast_queue_last_pre_stall_cycle)" \
    "$(extract "$line" logic_online_issue_blocked_channel_cycles)" \
    "$(extract "$line" logic_online_issue_busy_overlap_channel_cycles)" \
    "$(extract "$line" logic_blocked_wall_cycles)" \
    "$(extract "$line" logic_blocked_streams)" \
    "$(extract "$line" logic_min_blocked_per_stream)" \
    "$(extract "$line" logic_max_blocked_per_stream)" \
    "$(extract "$line" logic_min_issued_per_stream)" \
    "$(extract "$line" logic_max_issued_per_stream)" \
    "$(extract "$line" logic_blocked_stream_mask_low)" \
    "$(extract "$line" logic_blocked_stream_mask_high)" \
    "$(extract "$line" command_predicate_reject_cycles)" \
    "$(extract "$line" command_predicate_hol_cycles)" \
    "$(extract "$line" command_predicate_hol_candidates)" \
    "$(extract "$line" command_predicate_hol_max_candidates)" \
    "$(extract "$line" command_predicate_bypass_issues)" \
    "$(extract "$line" logic_weight_buffer_write_queue_cycles)" \
    "$(extract "$line" global_logic_commands)" \
    "$(extract "$line" global_logic_dispatches)" \
    "$(extract "$line" global_logic_coalesced)" \
    "$(extract "$line" global_logic_dispatch_overhead_cycles)" \
    "$(extract "$line" global_logic_queue_cycles)" \
    "$(extract "$line" global_logic_service_cycles)" \
    "$(extract "$line" total_refreshes)" \
    "$(extract "$line" total_cycle)" )
  (IFS=,; echo "${row[*]}") >> "$RESULT_FILE"
done

echo "Result: $RESULT_FILE"
column -s, -t "$RESULT_FILE" 2>/dev/null || cat "$RESULT_FILE"
