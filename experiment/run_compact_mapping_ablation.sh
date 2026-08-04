#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILES=(
  "$ROOT_DIR/ini/HBM2_samsung_2M_16B_x64.ini"
  "$ROOT_DIR/system_hbm.ini"
  "$ROOT_DIR/system_hbm_64ch.ini"
)
BACKUP_DIR="$(mktemp -d)"
RESULT_DIR="$ROOT_DIR/experiment/results"
RESULT_FILE="$RESULT_DIR/compact_mapping_pointwise.csv"
TEST_FILTER='MobileNetV4WorkloadTest.PointwiseBatchRunsMobileNetV4Shape'

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
mkdir -p "$RESULT_DIR"

set_case() {
  local logic_enabled="$1"
  local target="$2"
  local compact="$3"
  local latency="$4"
  local logic_bw="$5"
  for config_file in "${CONFIG_FILES[@]}"; do
    perl -0pi -e "s/^ENABLE_BANK_SIDE_PIM=.*/ENABLE_BANK_SIDE_PIM=true/m; \
                  s/^ENABLE_LOGIC_DIE_PIM=.*/ENABLE_LOGIC_DIE_PIM=${logic_enabled}/m; \
                  s/^NUM_LOGIC_PIM_UNITS=.*/NUM_LOGIC_PIM_UNITS=8/m; \
                  s/^LOGIC_PIM_LATENCY=.*/LOGIC_PIM_LATENCY=${latency}/m; \
                  s/^LOGIC_PIM_BW=.*/LOGIC_PIM_BW=${logic_bw}/m; \
                  s/^HIERARCHY_PIM_BW=.*/HIERARCHY_PIM_BW=64/m; \
                  s/^LOGIC_COMPACT_OUTPUT=.*/LOGIC_COMPACT_OUTPUT=${compact}/m; \
                  s/^LOGIC_SPATIAL_GROUPING=.*/LOGIC_SPATIAL_GROUPING=false/m; \
                  s/^PIM_TARGET=.*/PIM_TARGET=${target}/m" "$config_file"
  done
}

run_case() {
  local name="$1"
  local logic_enabled="$2"
  local target="$3"
  local compact="$4"
  local latency="$5"
  local logic_bw="$6"
  echo "[$name] compact=$compact latency=$latency logic_bw=$logic_bw"
  set_case "$logic_enabled" "$target" "$compact" "$latency" "$logic_bw"
  local output line cycle channels physical reads writes
  output="$(./sim --gtest_filter="$TEST_FILTER" 2>&1)" || {
    printf '%s\n' "$output" >&2
    return 1
  }
  line="$(printf '%s\n' "$output" | grep 'MOBILENETV4_BATCH_POINTWISE_RESULT' | tail -n 1)"
  cycle="$(printf '%s\n' "$line" | sed -n 's/.*cycle\[\([0-9]*\)\].*/\1/p')"
  channels="$(printf '%s\n' "$line" | sed -n 's/.*active_channels\[\([0-9]*\)\].*/\1/p')"
  physical="$(printf '%s\n' "$line" | sed -n 's/.*physical_output_dim\[\([0-9]*\)\].*/\1/p')"
  reads="$(printf '%s\n' "$line" | sed -n 's/.*reads\[\([0-9]*\)\].*/\1/p')"
  writes="$(printf '%s\n' "$line" | sed -n 's/.*writes\[\([0-9]*\)\].*/\1/p')"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$name" "$compact" "$latency" "$logic_bw" "$channels" "$physical" "$reads" "$writes" "$cycle" \
    >> "$RESULT_FILE"
}

cd "$ROOT_DIR"
printf 'case,compact,logic_latency,logic_bw,active_channels,physical_output_dim,reads,writes,cycle\n' \
  > "$RESULT_FILE"
run_case bank_fixed false bank_side false 0 0
run_case hybrid_fixed true hybrid false 2 64
run_case hybrid_compact_current true hybrid true 2 64
run_case hybrid_compact_ideal true hybrid true 0 0

echo "Result: $RESULT_FILE"
column -s, -t "$RESULT_FILE" 2>/dev/null || cat "$RESULT_FILE"
