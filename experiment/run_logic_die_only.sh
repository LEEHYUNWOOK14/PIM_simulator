#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILES=(
  "$ROOT_DIR/ini/HBM2_samsung_2M_16B_x64.ini"
  "$ROOT_DIR/system_hbm.ini"
  "$ROOT_DIR/system_hbm_64ch.ini"
)

BACKUP_DIR="$(mktemp -d)"

backup_configs() {
  for f in "${CONFIG_FILES[@]}"; do
    cp "$f" "$BACKUP_DIR/$(basename "$f")"
  done
}

restore_configs() {
  for f in "${CONFIG_FILES[@]}"; do
    cp "$BACKUP_DIR/$(basename "$f")" "$f"
  done
}

trap restore_configs EXIT

cd "$ROOT_DIR"
backup_configs

perl -0pi -e 's/^ENABLE_BANK_SIDE_PIM=.*/ENABLE_BANK_SIDE_PIM=false/m; s/^ENABLE_LOGIC_DIE_PIM=.*/ENABLE_LOGIC_DIE_PIM=true/m; s/^PIM_TARGET=.*/PIM_TARGET=logic_die/m' "${CONFIG_FILES[@]}"

echo "[logic-die only] PIMKernelFixture.gemv"
./sim --gtest_filter=PIMKernelFixture.gemv

echo "[logic-die only] PIMKernelFixture.gemv_tree"
./sim --gtest_filter=PIMKernelFixture.gemv_tree

restore_configs
rm -rf "$BACKUP_DIR"
