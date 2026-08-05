#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/experiment/results/epoch_release_comparison.csv}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

run_case() {
  local name="$1" epoch="$2" guard="$3" ports="$4"
  local child="$TMP_DIR/${name}.csv"
  FILL_POLICY=row_interleaved FILL_CHANNELS_LIST=32 \
  BUFFER_WRITE_PORTS="$ports" BUFFER_WRITE_LATENCY=1 \
  POST_FILL_GUARD_CYCLES="$guard" EPOCH_RELEASE="$epoch" \
  RESULT_FILE="$child" \
    bash "$ROOT_DIR/experiment/run_shared_weight_fill_channel_sweep.sh" >/dev/null
  if [[ ! -f "$RESULT_FILE" ]]; then
    printf 'case,' > "$RESULT_FILE"
    head -n 1 "$child" >> "$RESULT_FILE"
  fi
  printf '%s,' "$name" >> "$RESULT_FILE"
  tail -n 1 "$child" >> "$RESULT_FILE"
}

rm -f "$RESULT_FILE"
run_case guard0_epoch_off false 0 0
run_case guard128_epoch_off false 128 0
run_case guard0_epoch_on true 0 0
run_case port4_epoch_on true 0 4

echo "Result: $RESULT_FILE"
column -s, -t "$RESULT_FILE" 2>/dev/null || cat "$RESULT_FILE"
