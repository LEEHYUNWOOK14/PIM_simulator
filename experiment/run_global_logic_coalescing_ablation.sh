#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILES=(
  "$ROOT_DIR/ini/HBM2_samsung_2M_16B_x64.ini"
  "$ROOT_DIR/system_hbm.ini"
  "$ROOT_DIR/system_hbm_64ch.ini"
)
BACKUP_DIR="$(mktemp -d)"
RESULT_FILE="$ROOT_DIR/experiment/results/global_logic_coalescing_ablation.csv"

restore_configs() {
  for config_file in "${CONFIG_FILES[@]}"; do
    cp "$BACKUP_DIR/$(basename "$config_file")" "$config_file"
  done
  rm -rf "$BACKUP_DIR"
}

for config_file in "${CONFIG_FILES[@]}"; do
  cp "$config_file" "$BACKUP_DIR/$(basename "$config_file")"
done
trap restore_configs EXIT

set_case() {
  local coalescing="$1"
  for config_file in "${CONFIG_FILES[@]}"; do
    perl -0pi -e "s/^ENABLE_BANK_SIDE_PIM=.*/ENABLE_BANK_SIDE_PIM=true/m; \
                  s/^ENABLE_LOGIC_DIE_PIM=.*/ENABLE_LOGIC_DIE_PIM=true/m; \
                  s/^NUM_LOGIC_PIM_UNITS=.*/NUM_LOGIC_PIM_UNITS=16/m; \
                  s/^LOGIC_PIM_LATENCY=.*/LOGIC_PIM_LATENCY=2/m; \
                  s/^LOGIC_PIM_BW=.*/LOGIC_PIM_BW=64/m; \
                  s/^HIERARCHY_PIM_BW=.*/HIERARCHY_PIM_BW=64/m; \
                  s/^LOGIC_COMPACT_OUTPUT=.*/LOGIC_COMPACT_OUTPUT=true/m; \
                  s/^LOGIC_SPATIAL_GROUPING=.*/LOGIC_SPATIAL_GROUPING=true/m; \
                  s/^LOGIC_GLOBAL_SCHEDULER=.*/LOGIC_GLOBAL_SCHEDULER=true/m; \
                  s/^LOGIC_CMD_OVERHEAD=.*/LOGIC_CMD_OVERHEAD=4/m; \
                  s/^LOGIC_CMD_COALESCING=.*/LOGIC_CMD_COALESCING=${coalescing}/m; \
                  s/^LOGIC_SHARED_WEIGHT_BUFFER=.*/LOGIC_SHARED_WEIGHT_BUFFER=false/m; \
                  s/^LOGIC_WEIGHT_BUFFER_BYTES=.*/LOGIC_WEIGHT_BUFFER_BYTES=0/m; \
                  s/^LOGIC_WEIGHT_FILL_CHANNELS=.*/LOGIC_WEIGHT_FILL_CHANNELS=0/m; \
                  s/^LOGIC_WEIGHT_FILL_POLICY=.*/LOGIC_WEIGHT_FILL_POLICY=round_robin/m; \
                  s/^LOGIC_WEIGHT_STAGING_ROW=.*/LOGIC_WEIGHT_STAGING_ROW=2048/m; \
                  s/^DEBUG_CMD_TRACE=.*/DEBUG_CMD_TRACE=false/m; \
                  s/^PIM_TARGET=.*/PIM_TARGET=hybrid/m" "$config_file"
  done
}

extract() {
  local line="$1" key="$2"
  printf '%s\n' "$line" | grep -o "${key}\[[0-9]*\]" | head -n 1 | tr -cd '0-9'
}

cd "$ROOT_DIR"
scons -j"${BUILD_JOBS:-4}"
printf 'coalescing,commands,dispatches,coalesced,dispatch_overhead_cycles,service_cycles,busy_until,cycle\n' \
  > "$RESULT_FILE"

for coalescing in false true; do
  echo "[command coalescing=$coalescing]"
  set_case "$coalescing"
  output="$(./sim --gtest_filter=MobileNetV4WorkloadTest.PointwiseBatchRunsMobileNetV4Shape 2>&1)" || {
    printf '%s\n' "$output" >&2
    exit 1
  }
  line="$(printf '%s\n' "$output" | grep MOBILENETV4_BATCH_POINTWISE_RESULT | tail -n 1)"
  printf '%s,%s,%s,%s,%s,%s,%s,%s\n' "$coalescing" \
    "$(extract "$line" global_logic_commands)" \
    "$(extract "$line" global_logic_dispatches)" \
    "$(extract "$line" global_logic_coalesced)" \
    "$(extract "$line" global_logic_dispatch_overhead_cycles)" \
    "$(extract "$line" global_logic_service_cycles)" \
    "$(extract "$line" global_logic_busy_until)" "$(extract "$line" cycle)" \
    >> "$RESULT_FILE"
done

echo "Result: $RESULT_FILE"
column -s, -t "$RESULT_FILE" 2>/dev/null || cat "$RESULT_FILE"
