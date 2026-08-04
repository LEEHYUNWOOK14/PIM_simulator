#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGIC_UNITS="${LOGIC_UNITS:-8}"
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

for config_file in "${CONFIG_FILES[@]}"; do
  perl -0pi -e "s/^ENABLE_BANK_SIDE_PIM=.*/ENABLE_BANK_SIDE_PIM=true/m; \
                s/^ENABLE_LOGIC_DIE_PIM=.*/ENABLE_LOGIC_DIE_PIM=true/m; \
                s/^NUM_LOGIC_PIM_UNITS=.*/NUM_LOGIC_PIM_UNITS=${LOGIC_UNITS}/m; \
                s/^LOGIC_PIM_LATENCY=.*/LOGIC_PIM_LATENCY=2/m; \
                s/^LOGIC_PIM_BW=.*/LOGIC_PIM_BW=64/m; \
                s/^HIERARCHY_PIM_BW=.*/HIERARCHY_PIM_BW=64/m; \
                s/^LOGIC_COMPACT_OUTPUT=.*/LOGIC_COMPACT_OUTPUT=true/m; \
                s/^LOGIC_SPATIAL_GROUPING=.*/LOGIC_SPATIAL_GROUPING=true/m; \
                s/^LOGIC_GLOBAL_SCHEDULER=.*/LOGIC_GLOBAL_SCHEDULER=true/m; \
                s/^LOGIC_CMD_OVERHEAD=.*/LOGIC_CMD_OVERHEAD=0/m; \
                s/^LOGIC_SHARED_WEIGHT_BUFFER=.*/LOGIC_SHARED_WEIGHT_BUFFER=false/m; \
                s/^LOGIC_WEIGHT_BUFFER_BYTES=.*/LOGIC_WEIGHT_BUFFER_BYTES=0/m; \
                s/^LOGIC_WEIGHT_FILL_CHANNELS=.*/LOGIC_WEIGHT_FILL_CHANNELS=0/m; \
                s/^LOGIC_WEIGHT_FILL_POLICY=.*/LOGIC_WEIGHT_FILL_POLICY=round_robin/m; \
                s/^LOGIC_WEIGHT_STAGING_ROW=.*/LOGIC_WEIGHT_STAGING_ROW=2048/m; \
                s/^DEBUG_CMD_TRACE=.*/DEBUG_CMD_TRACE=false/m; \
                s/^PIM_TARGET=.*/PIM_TARGET=hybrid/m" "$config_file"
done

cd "$ROOT_DIR"
echo "Global logic PCU units: $LOGIC_UNITS"
scons -j"${BUILD_JOBS:-4}"
./sim --gtest_filter=MobileNetV4WorkloadTest.ActualShapeUibRunsEndToEnd
