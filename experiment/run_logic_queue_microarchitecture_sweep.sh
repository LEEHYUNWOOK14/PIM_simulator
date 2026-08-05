#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGIC_UNITS_LIST="${LOGIC_UNITS_LIST:-8 16 32}"
LOGIC_BW_LIST="${LOGIC_BW_LIST:-32 64 128}"
DEPTH_LIST="${DEPTH_LIST:-64 128}"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/experiment/results/logic_queue_microarchitecture_sweep.csv}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

first=true
for units in $LOGIC_UNITS_LIST; do
  for bandwidth in $LOGIC_BW_LIST; do
    for depth in $DEPTH_LIST; do
      echo "[logic units=$units bandwidth=$bandwidth depth=$depth]"
      child="$TMP_DIR/u${units}_bw${bandwidth}_d${depth}.csv"
      LOGIC_UNITS="$units" LOGIC_BW="$bandwidth" \
      FILL_POLICY=row_interleaved FILL_CHANNELS_LIST=32 \
      BUFFER_WRITE_PORTS=0 BUFFER_WRITE_LATENCY=1 \
      POST_FILL_GUARD_CYCLES=0 EPOCH_RELEASE=true \
      ONLINE_QUEUE_BACKPRESSURE=true BROADCAST_QUEUE_DEPTH="$depth" \
      RESULT_FILE="$child" \
        bash "$ROOT_DIR/experiment/run_shared_weight_fill_channel_sweep.sh" >/dev/null

      if [[ "$first" == "true" ]]; then
        printf 'logic_units,logic_bw,broadcast_queue_depth_requested,' > "$RESULT_FILE"
        head -n 1 "$child" >> "$RESULT_FILE"
        first=false
      fi
      printf '%s,%s,%s,' "$units" "$bandwidth" "$depth" >> "$RESULT_FILE"
      tail -n 1 "$child" >> "$RESULT_FILE"
    done
  done
done

echo "Result: $RESULT_FILE"
column -s, -t "$RESULT_FILE" 2>/dev/null || cat "$RESULT_FILE"
