#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILES=(
  "$ROOT_DIR/ini/HBM2_samsung_2M_16B_x64.ini"
  "$ROOT_DIR/system_hbm.ini"
  "$ROOT_DIR/system_hbm_64ch.ini"
)
BACKUP_DIR="$(mktemp -d)"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/experiment/results/shared_weight_fill_channel_sweep.csv}"
FILL_CHANNELS_LIST="${FILL_CHANNELS_LIST:-0 4 8 16 32 64}"

restore_configs() {
  for config_file in "${CONFIG_FILES[@]}"; do
    cp "$BACKUP_DIR/$(basename "$config_file")" "$config_file"
  done
  rm -rf "$BACKUP_DIR"
}

for config_file in "${CONFIG_FILES[@]}"; do
  cp "$config_file" "$BACKUP_DIR/$(basename "$config_file")"
done
trap restore_configs EXIT

set_fill_channels() {
  local channels="$1"
  for config_file in "${CONFIG_FILES[@]}"; do
    perl -0pi -e "s/^ENABLE_BANK_SIDE_PIM=.*/ENABLE_BANK_SIDE_PIM=true/m; \
                  s/^ENABLE_LOGIC_DIE_PIM=.*/ENABLE_LOGIC_DIE_PIM=true/m; \
                  s/^NUM_LOGIC_PIM_UNITS=.*/NUM_LOGIC_PIM_UNITS=16/m; \
                  s/^LOGIC_PIM_LATENCY=.*/LOGIC_PIM_LATENCY=2/m; \
                  s/^LOGIC_PIM_BW=.*/LOGIC_PIM_BW=64/m; \
                  s/^HIERARCHY_PIM_BW=.*/HIERARCHY_PIM_BW=64/m; \
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
                  s/^LOGIC_WEIGHT_BUFFER_WRITE_PORTS=.*/LOGIC_WEIGHT_BUFFER_WRITE_PORTS=${BUFFER_WRITE_PORTS:-0}/m; \
                  s/^LOGIC_WEIGHT_BUFFER_WRITE_LATENCY=.*/LOGIC_WEIGHT_BUFFER_WRITE_LATENCY=${BUFFER_WRITE_LATENCY:-1}/m; \
                  s/^LOGIC_POST_FILL_GUARD_CYCLES=.*/LOGIC_POST_FILL_GUARD_CYCLES=${POST_FILL_GUARD_CYCLES:-0}/m; \
                  s/^DEBUG_CMD_TRACE=.*/DEBUG_CMD_TRACE=false/m; \
                  s/^PIM_TARGET=.*/PIM_TARGET=hybrid/m" "$config_file"
  done
}

extract() {
  local line="$1" key="$2"
  printf '%s\n' "$line" | grep -o "${key}\[[0-9]*\]" | head -n 1 | tr -cd '0-9'
}

cd "$ROOT_DIR"
scons -j"${BUILD_JOBS:-4}"
printf 'fill_policy,fill_channels,buffer_write_ports,buffer_write_latency,post_fill_guard_setting,physical_weight_bytes,physical_writes,buffer_fill_bursts,buffer_read_hits,buffer_read_misses,active_channels,completed_fill_writes,min_writes_per_channel,max_writes_per_channel,min_completion_cycle,max_completion_cycle,fill_activates,fill_precharges,fill_barrier_cycles,port_wait_cycles,post_fill_guard_cycles,write_queue_cycles,global_commands,global_dispatches,global_coalesced,global_dispatch_overhead_cycles,global_queue_cycles,global_service_cycles,total_refreshes,total_cycle\n' \
  > "$RESULT_FILE"

for channels in $FILL_CHANNELS_LIST; do
  echo "[shared weight fill channels=$channels]"
  set_fill_channels "$channels"
  output=""
  test_passed=false
  for attempt in 1 2 3; do
    if output="$(./sim --gtest_filter=MobileNetV4WorkloadTest.ActualShapeUibRunsEndToEnd 2>&1)"; then
      test_passed=true
      break
    fi
    sleep 2
  done
  if [[ "$test_passed" != "true" ]]; then
    printf '%s\n' "$output" >&2
    exit 1
  fi
  line="$(printf '%s\n' "$output" | grep MOBILENETV4_ACTUAL_UIB_RESULT | tail -n 1)"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "${FILL_POLICY:-round_robin}" "$channels" "${BUFFER_WRITE_PORTS:-0}" \
    "${BUFFER_WRITE_LATENCY:-1}" "${POST_FILL_GUARD_CYCLES:-0}" \
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
    "$(extract "$line" logic_weight_buffer_write_queue_cycles)" \
    "$(extract "$line" global_logic_commands)" \
    "$(extract "$line" global_logic_dispatches)" \
    "$(extract "$line" global_logic_coalesced)" \
    "$(extract "$line" global_logic_dispatch_overhead_cycles)" \
    "$(extract "$line" global_logic_queue_cycles)" \
    "$(extract "$line" global_logic_service_cycles)" \
    "$(extract "$line" total_refreshes)" \
    "$(extract "$line" total_cycle)" >> "$RESULT_FILE"
done

echo "Result: $RESULT_FILE"
column -s, -t "$RESULT_FILE" 2>/dev/null || cat "$RESULT_FILE"
