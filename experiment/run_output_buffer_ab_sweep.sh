#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILES=("$ROOT_DIR/system_hbm.ini" "$ROOT_DIR/system_hbm_64ch.ini")
BACKUP_DIR="$(mktemp -d)"
LOCK_DIR="${TMPDIR:-/tmp}/stob_pim_output_buffer_sweep.lock"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/experiment/results/output_buffer_ab_sweep.csv}"

restore_configs() {
  for file in "${CONFIG_FILES[@]}"; do
    cp "$BACKUP_DIR/$(basename "$file")" "$file"
  done
  rm -rf "$BACKUP_DIR"
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "Another output-buffer sweep is running: $LOCK_DIR" >&2
  rm -rf "$BACKUP_DIR"
  exit 1
fi
for file in "${CONFIG_FILES[@]}"; do cp "$file" "$BACKUP_DIR/$(basename "$file")"; done
trap restore_configs EXIT

set_output_config() {
  local enabled="$1" entries="$2" latency="$3" bandwidth="$4"
  for file in "${CONFIG_FILES[@]}"; do
    perl -0pi -e "s/^LOGIC_OUTPUT_BUFFER_ENABLE=.*/LOGIC_OUTPUT_BUFFER_ENABLE=$enabled/m; \
                  s/^LOGIC_OUTPUT_BUFFER_ENTRIES=.*/LOGIC_OUTPUT_BUFFER_ENTRIES=$entries/m; \
                  s/^LOGIC_OUTPUT_DRAIN_LATENCY=.*/LOGIC_OUTPUT_DRAIN_LATENCY=$latency/m; \
                  s/^LOGIC_OUTPUT_DRAIN_BW=.*/LOGIC_OUTPUT_DRAIN_BW=$bandwidth/m" "$file"
  done
}

extract() {
  local line="$1" key="$2"
  printf '%s\n' "$line" | grep -o "${key}\[[0-9]*\]" | head -n 1 | sed -E 's/.*\[([0-9]+)\]/\1/'
}

cd "$ROOT_DIR"
scons -j"${BUILD_JOBS:-4}"
printf 'mode,enabled,entries,drain_latency,drain_bw,outputs_checked,reservations,retirements,full_retry_channel_cycles,full_wall_cycles,peak_entries,drain_busy_cycles,total_cycle,result\n' > "$RESULT_FILE"

cases=(
  "post_copy false 2 0 0"
  "callback_zero_latency true 2 0 0"
  "callback_drain_4_8 true 2 4 8"
)

for spec in "${cases[@]}"; do
  read -r mode enabled entries latency bandwidth <<< "$spec"
  echo "[output buffer: $mode]"
  set_output_config "$enabled" "$entries" "$latency" "$bandwidth"
  output="$(./sim --gtest_filter=MobileNetV4WorkloadTest.ActualShapeUibRunsEndToEnd 2>&1)"
  line="$(printf '%s\n' "$output" | grep 'MOBILENETV4_ACTUAL_UIB_RESULT' | tail -n 1)"
  actual_enabled="$(extract "$line" logic_output_buffer_enabled)"
  expected_enabled=0
  [[ "$enabled" == "true" ]] && expected_enabled=1
  if [[ "$actual_enabled" != "$expected_enabled" ]]; then
    echo "Configuration injection failed for $mode" >&2
    exit 1
  fi
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,PASS\n' \
    "$mode" "$actual_enabled" "$(extract "$line" logic_output_buffer_entries_setting)" \
    "$(extract "$line" logic_output_drain_latency_setting)" \
    "$(extract "$line" logic_output_drain_bw_setting)" \
    "$(extract "$line" outputs_checked)" \
    "$(extract "$line" logic_output_buffer_reservations)" \
    "$(extract "$line" logic_output_buffer_retirements)" \
    "$(extract "$line" logic_output_buffer_full_stalls)" \
    "$(extract "$line" logic_output_buffer_full_wall_cycles)" \
    "$(extract "$line" logic_output_buffer_peak_entries)" \
    "$(extract "$line" logic_output_drain_busy_cycles)" \
    "$(extract "$line" total_cycle)" >> "$RESULT_FILE"
done

echo "Result: $RESULT_FILE"
