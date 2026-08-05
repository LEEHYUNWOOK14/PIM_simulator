#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/experiment/results/mode_transition_latency_sweep.csv}"
LATENCIES="${LATENCIES:-0 32 64}"

extract() {
  local line="$1" key="$2"
  printf '%s\n' "$line" | grep -o "${key}\[[0-9]*\]" | head -n 1 | sed -E 's/.*\[([0-9]+)\]/\1/'
}

printf 'mode_transition_latency,hab_residency,channels,positions,outputs_checked,spatial_groups,batch_waves,hab_entries,hab_exits,total_cycle,status\n' > "$RESULT_FILE"

for latency in $LATENCIES; do
  for residency in false true; do
    echo "[mode_transition_latency=$latency hab_residency=$residency]"
    output="$(
      RAW_TEST_FILTER=MobileNetV4WorkloadTest.PointwiseHabResidencySingleGroupTwoWaves \
      RAW_FILL_CHANNELS=32 HIERARCHY_SOURCE_QUEUES=true \
      OUTPUT_BUFFER_ENABLE=true OUTPUT_BUFFER_ENTRIES=2 \
      OUTPUT_DRAIN_LATENCY=4 OUTPUT_DRAIN_BW=8 \
      HAB_RESIDENCY="$residency" MODE_TRANSITION_LATENCY="$latency" \
        bash "$ROOT_DIR/experiment/run_shared_weight_fill_channel_sweep.sh" 2>&1
    )"
    line="$(printf '%s\n' "$output" | grep MODE_TRANSITION_LATENCY_RESULT | tail -n 1)"
    status=FAIL
    if printf '%s\n' "$output" | grep -q '\[  PASSED  \] 1 test'; then status=PASS; fi
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$latency" "$residency" "$(extract "$line" channels)" \
      "$(extract "$line" positions)" "$(extract "$line" outputs_checked)" \
      "$(extract "$line" spatial_groups)" "$(extract "$line" batch_waves)" \
      "$(extract "$line" hab_entries)" "$(extract "$line" hab_exits)" \
      "$(extract "$line" total_cycle)" "$status" >> "$RESULT_FILE"
  done
done

echo "Result: $RESULT_FILE"
column -s, -t "$RESULT_FILE" 2>/dev/null || cat "$RESULT_FILE"
