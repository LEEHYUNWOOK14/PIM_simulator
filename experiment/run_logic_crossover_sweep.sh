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
RESULT_FILE="$RESULT_DIR/logic_crossover_pointwise.csv"
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

set_mode() {
  local bank_enabled="$1"
  local logic_enabled="$2"
  local target="$3"
  local units="$4"
  local latency="$5"
  local logic_bw="$6"
  local hierarchy_bw="$7"
  for config_file in "${CONFIG_FILES[@]}"; do
    perl -0pi -e "s/^ENABLE_BANK_SIDE_PIM=.*/ENABLE_BANK_SIDE_PIM=${bank_enabled}/m; \
                  s/^ENABLE_LOGIC_DIE_PIM=.*/ENABLE_LOGIC_DIE_PIM=${logic_enabled}/m; \
                  s/^NUM_LOGIC_PIM_UNITS=.*/NUM_LOGIC_PIM_UNITS=${units}/m; \
                  s/^LOGIC_PIM_LATENCY=.*/LOGIC_PIM_LATENCY=${latency}/m; \
                  s/^LOGIC_PIM_BW=.*/LOGIC_PIM_BW=${logic_bw}/m; \
                  s/^HIERARCHY_PIM_BW=.*/HIERARCHY_PIM_BW=${hierarchy_bw}/m; \
                  s/^LOGIC_COMPACT_OUTPUT=.*/LOGIC_COMPACT_OUTPUT=false/m; \
                  s/^LOGIC_SPATIAL_GROUPING=.*/LOGIC_SPATIAL_GROUPING=false/m; \
                  s/^PIM_TARGET=.*/PIM_TARGET=${target}/m" "$config_file"
  done
}

run_pointwise() {
  local output
  output="$(./sim --gtest_filter="$TEST_FILTER" 2>&1)" || {
    printf '%s\n' "$output" >&2
    return 1
  }
  printf '%s\n' "$output" | sed -n \
    's/.*MOBILENETV4_BATCH_POINTWISE_RESULT.*cycle\[\([0-9][0-9]*\)\].*/\1/p' | tail -n 1
}

cd "$ROOT_DIR"
printf 'case,mode,units,logic_latency,logic_bw,hierarchy_bw,cycle,bank_speedup\n' > "$RESULT_FILE"

echo "[baseline] bank-only"
set_mode true false bank_side 8 0 0 64
bank_cycle="$(run_pointwise)"
printf 'bank_baseline,bank_only,8,0,0,64,%s,1.000000\n' "$bank_cycle" >> "$RESULT_FILE"

run_hybrid_case() {
  local name="$1"
  local units="$2"
  local latency="$3"
  local logic_bw="$4"
  local hierarchy_bw="$5"
  echo "[$name] units=$units latency=$latency logic_bw=$logic_bw hierarchy_bw=$hierarchy_bw"
  set_mode true true hybrid "$units" "$latency" "$logic_bw" "$hierarchy_bw"
  local cycle
  cycle="$(run_pointwise)"
  local speedup
  speedup="$(awk -v baseline="$bank_cycle" -v measured="$cycle" \
    'BEGIN { printf "%.6f", baseline / measured }')"
  printf '%s,hybrid,%s,%s,%s,%s,%s,%s\n' \
    "$name" "$units" "$latency" "$logic_bw" "$hierarchy_bw" "$cycle" "$speedup" \
    >> "$RESULT_FILE"
}

run_hybrid_case ideal_unlimited 8 0 0 0
run_hybrid_case compute_one_cycle 8 1 0 0
run_hybrid_case balanced_fast 8 1 256 256
run_hybrid_case half_units 4 2 0 64
run_hybrid_case current_model 8 2 64 64
run_hybrid_case constrained 2 4 32 32

echo "Result: $RESULT_FILE"
column -s, -t "$RESULT_FILE" 2>/dev/null || cat "$RESULT_FILE"
