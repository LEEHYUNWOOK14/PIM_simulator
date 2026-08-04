#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILES=(
  "$ROOT_DIR/ini/HBM2_samsung_2M_16B_x64.ini"
  "$ROOT_DIR/system_hbm.ini"
  "$ROOT_DIR/system_hbm_64ch.ini"
)
BACKUP_DIR="$(mktemp -d)"

restore_configs() {
  for config_file in "${CONFIG_FILES[@]}"; do
    cp "$BACKUP_DIR/$(basename "$config_file")" "$config_file"
  done
}

for config_file in "${CONFIG_FILES[@]}"; do
  cp "$config_file" "$BACKUP_DIR/$(basename "$config_file")"
done
trap restore_configs EXIT

set_logic_config() {
  local units="$1"
  local latency="$2"
  local bandwidth="$3"

  for config_file in "${CONFIG_FILES[@]}"; do
    perl -0pi -e "s/^ENABLE_BANK_SIDE_PIM=.*/ENABLE_BANK_SIDE_PIM=false/m; \
                  s/^ENABLE_LOGIC_DIE_PIM=.*/ENABLE_LOGIC_DIE_PIM=true/m; \
                  s/^NUM_LOGIC_PIM_UNITS=.*/NUM_LOGIC_PIM_UNITS=${units}/m; \
                  s/^LOGIC_PIM_LATENCY=.*/LOGIC_PIM_LATENCY=${latency}/m; \
                  s/^LOGIC_PIM_BW=.*/LOGIC_PIM_BW=${bandwidth}/m; \
                  s/^PIM_TARGET=.*/PIM_TARGET=logic_die/m" "$config_file"
  done
}

run_case() {
  local name="$1"
  local units="$2"
  local latency="$3"
  local bandwidth="$4"

  set_logic_config "$units" "$latency" "$bandwidth"
  echo "[$name] units=$units latency=$latency bandwidth=$bandwidth"
  "$ROOT_DIR/sim" --gtest_filter=PIMBenchFixture.gemv || true
}

run_case "compatibility" 8 0 0
run_case "constrained" 2 4 32

