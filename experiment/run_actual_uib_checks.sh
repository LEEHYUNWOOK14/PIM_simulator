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
  rm -rf "$BACKUP_DIR"
}

for config_file in "${CONFIG_FILES[@]}"; do
  cp "$config_file" "$BACKUP_DIR/$(basename "$config_file")"
done
trap restore_configs EXIT

set_mode() {
  local bank_enabled="$1"
  local logic_enabled="$2"
  local target="$3"
  for config_file in "${CONFIG_FILES[@]}"; do
    perl -0pi -e "s/^ENABLE_BANK_SIDE_PIM=.*/ENABLE_BANK_SIDE_PIM=${bank_enabled}/m; \
                  s/^ENABLE_LOGIC_DIE_PIM=.*/ENABLE_LOGIC_DIE_PIM=${logic_enabled}/m; \
                  s/^NUM_LOGIC_PIM_UNITS=.*/NUM_LOGIC_PIM_UNITS=8/m; \
                  s/^LOGIC_PIM_LATENCY=.*/LOGIC_PIM_LATENCY=2/m; \
                  s/^LOGIC_PIM_BW=.*/LOGIC_PIM_BW=64/m; \
                  s/^HIERARCHY_PIM_BW=.*/HIERARCHY_PIM_BW=64/m; \
                  s/^LOGIC_COMPACT_OUTPUT=.*/LOGIC_COMPACT_OUTPUT=false/m; \
                  s/^LOGIC_SPATIAL_GROUPING=.*/LOGIC_SPATIAL_GROUPING=false/m; \
                  s/^PIM_TARGET=.*/PIM_TARGET=${target}/m" "$config_file"
  done
}

cd "$ROOT_DIR"

echo "[1/2] actual-shape UIB with bank-side PIM only"
set_mode true false bank_side
./sim --gtest_filter='MobileNetV4WorkloadTest.PointwiseBatchRunsMobileNetV4Shape:MobileNetV4WorkloadTest.ActualShapeUibRunsEndToEnd'

echo "[2/2] actual-shape UIB with hierarchical bank-side + logic-die PIM"
set_mode true true hybrid
./sim --gtest_filter='MobileNetV4WorkloadTest.PointwiseBatchRunsMobileNetV4Shape:MobileNetV4WorkloadTest.ActualShapeUibRunsEndToEnd'
