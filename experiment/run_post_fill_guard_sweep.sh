#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD_LIST="${GUARD_LIST:-0 64 128 256 333 512 666}"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/experiment/results/post_fill_guard_sweep.csv}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

first=true
for guard in $GUARD_LIST; do
  echo "[post-fill guard=$guard cycles per layer]"
  child_result="$TMP_DIR/guard_${guard}.csv"
  FILL_POLICY=row_interleaved \
  FILL_CHANNELS_LIST=32 \
  BUFFER_WRITE_PORTS=0 \
  BUFFER_WRITE_LATENCY=1 \
  POST_FILL_GUARD_CYCLES="$guard" \
  RESULT_FILE="$child_result" \
    bash "$ROOT_DIR/experiment/run_shared_weight_fill_channel_sweep.sh" >/dev/null
  if [[ "$first" == "true" ]]; then
    head -n 1 "$child_result" > "$RESULT_FILE"
    first=false
  fi
  tail -n 1 "$child_result" >> "$RESULT_FILE"
done

echo "Result: $RESULT_FILE"
column -s, -t "$RESULT_FILE" 2>/dev/null || cat "$RESULT_FILE"
