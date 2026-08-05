#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BYPASS_LIST="${BYPASS_LIST:-false true}"
DEPTH_LIST="${DEPTH_LIST:-32 64 128}"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/experiment/results/hierarchy_ready_bypass_sweep.csv}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

first=true
for bypass in $BYPASS_LIST; do
  for depth in $DEPTH_LIST; do
    echo "[hierarchy ready bypass=$bypass depth=$depth]"
    child="$TMP_DIR/bypass_${bypass}_depth_${depth}.csv"
    HIERARCHY_READY_BYPASS="$bypass" \
    FILL_POLICY=row_interleaved FILL_CHANNELS_LIST=32 \
    BUFFER_WRITE_PORTS=0 BUFFER_WRITE_LATENCY=1 \
    POST_FILL_GUARD_CYCLES=0 EPOCH_RELEASE=true \
    ONLINE_QUEUE_BACKPRESSURE=true BROADCAST_QUEUE_DEPTH="$depth" \
    RESULT_FILE="$child" \
      bash "$ROOT_DIR/experiment/run_shared_weight_fill_channel_sweep.sh" >/dev/null
    if [[ "$first" == "true" ]]; then
      head -n 1 "$child" > "$RESULT_FILE"
      first=false
    fi
    tail -n 1 "$child" >> "$RESULT_FILE"
  done
done

echo "Result: $RESULT_FILE"
column -s, -t "$RESULT_FILE" 2>/dev/null || cat "$RESULT_FILE"
