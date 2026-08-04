#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORTS_LIST="${PORTS_LIST:-0 1 2 4 8 16 32}"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/experiment/results/shared_weight_buffer_port_sweep.csv}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

printf 'fill_policy,fill_channels,buffer_write_ports,buffer_write_latency,post_fill_guard_setting,physical_weight_bytes,physical_writes,buffer_fill_bursts,buffer_read_hits,buffer_read_misses,active_channels,completed_fill_writes,min_writes_per_channel,max_writes_per_channel,min_completion_cycle,max_completion_cycle,fill_activates,fill_precharges,fill_barrier_cycles,port_wait_cycles,post_fill_guard_cycles,write_queue_cycles,global_commands,global_dispatches,global_coalesced,global_dispatch_overhead_cycles,global_queue_cycles,global_service_cycles,total_refreshes,total_cycle\n' \
  > "$RESULT_FILE"

for ports in $PORTS_LIST; do
  echo "[weight buffer write ports=$ports]"
  child_result="$TMP_DIR/ports_${ports}.csv"
  FILL_POLICY=row_interleaved \
  FILL_CHANNELS_LIST=32 \
  BUFFER_WRITE_PORTS="$ports" \
  BUFFER_WRITE_LATENCY="${BUFFER_WRITE_LATENCY:-1}" \
  POST_FILL_GUARD_CYCLES="${POST_FILL_GUARD_CYCLES:-0}" \
  RESULT_FILE="$child_result" \
    bash "$ROOT_DIR/experiment/run_shared_weight_fill_channel_sweep.sh" >/dev/null
  tail -n 1 "$child_result" >> "$RESULT_FILE"
done

echo "Result: $RESULT_FILE"
column -s, -t "$RESULT_FILE" 2>/dev/null || cat "$RESULT_FILE"
