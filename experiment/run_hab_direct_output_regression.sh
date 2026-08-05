#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT_DIR/experiment/run_shared_weight_fill_channel_sweep.sh"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/experiment/results/hab_direct_output_regression.csv}"
INCLUDE_LONG="${INCLUDE_LONG:-false}"

tests=(
  MobileNetV4WorkloadTest.PointwiseHabResidencyThreeChannelGroup
  MobileNetV4WorkloadTest.PointwiseHabResidencyTwoThreeChannelGroups
)
if [[ "$INCLUDE_LONG" == "true" ]]; then
  tests+=(MobileNetV4WorkloadTest.NonblockingExpandFeedsTwoDepthwiseTileRows)
fi

extract() {
  local text="$1" key="$2"
  printf '%s\n' "$text" | grep -o "${key}\[[0-9]*\]" | tail -n 1 | sed -E 's/.*\[([0-9]+)\]/\1/'
}

printf 'test,result,outputs_checked,hab_entries,hab_exits,rank_command_rejects,rank_mode_transition_rejects,rank_logic_queue_rejects,rank_bank_domain_rejects,rank_logic_domain_rejects,total_cycle\n' > "$RESULT_FILE"
for test_name in "${tests[@]}"; do
  echo "[HAB direct-output regression: $test_name]"
  set +e
  output="$(
    RAW_TEST_FILTER="$test_name" RAW_FILL_CHANNELS=32 \
    HIERARCHY_SOURCE_QUEUES=true OUTPUT_BUFFER_ENABLE=true \
    OUTPUT_BUFFER_ENTRIES=2 OUTPUT_DRAIN_LATENCY=4 OUTPUT_DRAIN_BW=8 \
    HAB_RESIDENCY=true MODE_TRANSITION_LATENCY=32 \
    PIM_RUN_WATCHDOG_CYCLES="${WATCHDOG_CYCLES:-200000}" \
    EPOCH_RELEASE=true ONLINE_QUEUE_BACKPRESSURE=true \
    BROADCAST_QUEUE_DEPTH=128 HIERARCHY_READY_BYPASS=true \
    FILL_POLICY=row_interleaved bash "$RUNNER" 2>&1
  )"
  rc=$?
  set -e
  printf '%s\n' "$output"
  status=FAIL
  if [[ $rc -eq 0 ]] && printf '%s\n' "$output" | grep -q '\[  PASSED  \] 1 test'; then
    status=PASS
  fi
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$test_name" "$status" \
    "$(extract "$output" outputs_checked || true)" \
    "$(extract "$output" hab_entries || true)" \
    "$(extract "$output" hab_exits || true)" \
    "$(extract "$output" rank_command_rejects || true)" \
    "$(extract "$output" rank_mode_transition_rejects || true)" \
    "$(extract "$output" rank_logic_queue_rejects || true)" \
    "$(extract "$output" rank_bank_domain_rejects || true)" \
    "$(extract "$output" rank_logic_domain_rejects || true)" \
    "$(extract "$output" total_cycle || true)" >> "$RESULT_FILE"
  [[ "$status" == "PASS" ]] || exit 1
done

echo "Result: $RESULT_FILE"
column -s, -t "$RESULT_FILE" 2>/dev/null || cat "$RESULT_FILE"
