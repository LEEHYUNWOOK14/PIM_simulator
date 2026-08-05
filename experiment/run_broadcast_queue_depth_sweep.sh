#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPTH_LIST="${DEPTH_LIST:-0 32 64 78 96 128}"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/experiment/results/broadcast_queue_depth_sweep.csv}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

first=true
for depth in $DEPTH_LIST; do
  echo "[broadcast queue depth=$depth]"
  child="$TMP_DIR/depth_${depth}.csv"
  FILL_POLICY=row_interleaved FILL_CHANNELS_LIST=32 \
  BUFFER_WRITE_PORTS=0 BUFFER_WRITE_LATENCY=1 \
  POST_FILL_GUARD_CYCLES=0 EPOCH_RELEASE=true \
  ONLINE_QUEUE_BACKPRESSURE="${ONLINE_QUEUE_BACKPRESSURE:-false}" \
  BROADCAST_QUEUE_DEPTH="$depth" RESULT_FILE="$child" \
    bash "$ROOT_DIR/experiment/run_shared_weight_fill_channel_sweep.sh" >/dev/null
  if [[ "$first" == "true" ]]; then
    head -n 1 "$child" > "$RESULT_FILE"
    first=false
  fi
  tail -n 1 "$child" >> "$RESULT_FILE"
done

echo "Result: $RESULT_FILE"
column -s, -t "$RESULT_FILE" 2>/dev/null || cat "$RESULT_FILE"
