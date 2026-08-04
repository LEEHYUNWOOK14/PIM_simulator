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

apply_mode() {
  local bank_side="$1"
  local logic_die="$2"
  local target="$3"

  for f in "${CONFIG_FILES[@]}"; do
    perl -0pi -e "s/^ENABLE_BANK_SIDE_PIM=.*/ENABLE_BANK_SIDE_PIM=${bank_side}/m; \
                  s/^ENABLE_LOGIC_DIE_PIM=.*/ENABLE_LOGIC_DIE_PIM=${logic_die}/m; \
                  s/^PIM_TARGET=.*/PIM_TARGET=${target}/m" "$f"
  done
}

run_tests() {
  local title="$1"
  shift
  echo
  echo "[$title]"
  for test_name in "$@"; do
    echo "Note: Google Test filter = ${test_name}"
    local attempt=0
    local ok=0
    while [ $attempt -lt 3 ]; do
      if ./sim --gtest_filter="${test_name}"; then
        ok=1
        break
      fi
      if [ $? -ne 0 ] && [ $attempt -lt 2 ]; then
        sleep 1
      fi
      attempt=$((attempt + 1))
    done
    if [ $ok -eq 1 ]; then
      echo "[PASS] ${test_name}"
    else
      echo "[FAIL] ${test_name}"
    fi
  done
}

cleanup() {
  restore_configs
  rm -rf "$BACKUP_DIR"
}

trap cleanup EXIT

cd "$ROOT_DIR"
backup_configs

apply_mode true false bank_side
run_tests "1/3 bank-side only" \
  PIMKernelFixture.add \
  PIMKernelFixture.relu \
  PIMKernelFixture.mul \
  PIMKernelFixture.gemv \
  PIMKernelFixture.gemv_tree

apply_mode false true logic_die
run_tests "2/3 logic-die only" \
  PIMKernelFixture.gemv \
  PIMKernelFixture.gemv_tree

apply_mode true true hybrid
run_tests "3/3 hybrid" \
  PIMKernelFixture.add \
  PIMKernelFixture.relu \
  PIMKernelFixture.mul \
  PIMKernelFixture.gemv

echo
echo "Done. Config files restored."
