#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$repo_root/b1_logic_die_experiment"
orfs_root="${ORFS_ROOT:-/home/chandler/OpenROAD-flow-scripts}"
flow="$orfs_root/flow"
mkdir -p "$work/orfs" "$work/logs"
repo_wsl="$repo_root"
config="$repo_wsl/b1_logic_die_experiment/orfs_config.mk"
target="${1:-}"
make_args=(DESIGN_CONFIG="$config" STOB_REPO_ROOT="$repo_wsl" WORK_HOME="$repo_wsl/b1_logic_die_experiment/orfs"
  YOSYS_EXE=/home/chandler/.local/oss-cad-suite/bin/yosys
  OPENROAD_EXE=/home/chandler/.local/stob-eda/openroad/bin/openroad
  KLAYOUT_CMD=/usr/bin/klayout NUM_CORES=4 DETAILED_ROUTE_END_ITERATION=0
  MATCH_CELL_FOOTPRINT= SKIP_REPORT_METRICS=1 ENABLE_PLACE_REPAIR_TIMING=0
  ENABLE_DPO=0 SKIP_CTS_REPAIR_TIMING=1 SKIP_INCREMENTAL_REPAIR=1
  SKIP_ANTENNA_REPAIR=1 SKIP_ANTENNA_REPAIR_POST_DRT=1 RECOVER_POWER=0)
cd "$flow"
if [[ -n "$target" ]]; then
  make "${make_args[@]}" -j1 "$target" 2>&1 | tee "$work/logs/orfs_${target}.log"
else
  make "${make_args[@]}" -j1 2>&1 | tee "$work/logs/orfs_all.log"
fi
