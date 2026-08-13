#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$root/verification/groot_normalization/eda_environment.sh"
config="$root/flow/designs/sky130hd/normalization_hbm_wbq/config.mk"
result_dir="$orfs_flow/results/sky130hd/normalization_hbm_wbq/base"
log="$physical_report_root/logic_die_normalization_hbm_top_wbq_orfs_place.log"

if pgrep -f '[o]penroad.*normalization_hbm_wbq' >/dev/null; then
  echo "wbq OpenROAD job already running; refusing duplicate execution" >&2
  exit 3
fi

mkdir -p "$physical_report_root"
{
  echo "WBQ_PLACE_GIT_SHA=$(git -C "$root" rev-parse HEAD)"
  echo "WBQ_PLACE_NETLIST_SHA256=$(sha256sum "$physical_report_root/logic_die_normalization_hbm_top_wbq_sky130.v" | awk '{print $1}')"
  echo "WBQ_PLACE_CONFIG_SHA256=$(sha256sum "$config" | awk '{print $1}')"
  echo "WBQ_PLACE_ORFS_SHA=$(git -C "$orfs_root" rev-parse HEAD)"
  echo "WBQ_PLACE_OPENROAD_VERSION=$($openroad_exe -version 2>&1)"
  echo "WBQ_PLACE_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$log"

set +e
/usr/bin/time -v make -C "$orfs_flow" \
  DESIGN_CONFIG="$config" STOB_REPO_ROOT="$root" \
  YOSYS_EXE="$yosys_exe" OPENROAD_EXE="$openroad_exe" \
  NUM_CORES="${NUM_CORES:-16}" SKIP_REPORT_METRICS=1 -j1 place \
  >> "$log" 2>&1
rc=$?
set -e
echo "WBQ_PLACE_EXIT_CODE=$rc" >> "$log"
echo "WBQ_PLACE_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$log"

test "$rc" -eq 0
test -s "$result_dir/3_place.odb"
test -s "$result_dir/3_place.sdc"
grep -q 'Placement Analysis' "$orfs_flow/logs/sky130hd/normalization_hbm_wbq/base/3_5_place_dp.log"
echo "NORMALIZATION_HBM_WBQ_PLACE PASS odb=$result_dir/3_place.odb" | tee -a "$log"

