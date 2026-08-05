#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORTS_LIST="${PORTS_LIST:-0 1 2 4 8 16 32}"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/experiment/results/shared_weight_buffer_port_sweep.csv}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

first=true

for ports in $PORTS_LIST; do
  echo "[weight buffer write ports=$ports]"
  child_result="$TMP_DIR/ports_${ports}.csv"
  FILL_POLICY=row_interleaved \
  FILL_CHANNELS_LIST=32 \
  BUFFER_WRITE_PORTS="$ports" \
  BUFFER_WRITE_LATENCY="${BUFFER_WRITE_LATENCY:-1}" \
  POST_FILL_GUARD_CYCLES="${POST_FILL_GUARD_CYCLES:-0}" \
  EPOCH_RELEASE="${EPOCH_RELEASE:-false}" \
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
