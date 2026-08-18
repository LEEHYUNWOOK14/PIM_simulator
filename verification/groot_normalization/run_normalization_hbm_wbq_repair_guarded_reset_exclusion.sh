#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$root/verification/groot_normalization/eda_environment.sh"
config="$root/flow/designs/sky130hd/normalization_hbm_wbq/config.mk"
policy="$root/verification/groot_normalization/wbq_pre_resize_guarded_reset_exclusion.tcl"
result_dir="$orfs_flow/results/sky130hd/normalization_hbm_wbq/base"
log_dir="$orfs_flow/logs/sky130hd/normalization_hbm_wbq/base"
report="$physical_report_root/logic_die_normalization_hbm_top_wbq_repair_guarded_reset_exclusion.log"
archive="$physical_report_root/guarded_reset_exclusion_archive_$(date -u +%Y%m%dT%H%M%SZ)"

if pgrep -f '[o]penroad.*normalization_hbm_wbq' >/dev/null; then
  echo "wbq OpenROAD job already running; refusing duplicate execution" >&2
  exit 3
fi
test -s "$result_dir/3_3_place_gp.odb"
test -s "$result_dir/2_floorplan.sdc"
test -s "$policy"
test -f "$root/reports/final_integrated_gds_execution/CLI_OWNS_PHASE4"

mkdir -p "$archive/results" "$archive/logs"
for name in 3_4_place_resized.odb; do
  if test -e "$result_dir/$name"; then
    mv "$result_dir/$name" "$archive/results/$name"
  fi
done
for name in 3_4_place_resized.log 3_4_place_resized.tmp.log 3_4_place_resized.json; do
  if test -e "$log_dir/$name"; then
    mv "$log_dir/$name" "$archive/logs/$name"
  fi
done

{
  echo "WBQ_REPAIR_GUARDED_RESET_EXCLUSION_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "WBQ_REPAIR_GUARDED_RESET_EXCLUSION_SOURCE=$result_dir/3_3_place_gp.odb"
  echo "WBQ_REPAIR_GUARDED_RESET_EXCLUSION_SOURCE_SHA256=$(sha256sum "$result_dir/3_3_place_gp.odb" | awk '{print $1}')"
  echo "WBQ_REPAIR_GUARDED_RESET_EXCLUSION_POLICY=$policy"
  echo "WBQ_REPAIR_GUARDED_RESET_EXCLUSION_POLICY_SHA256=$(sha256sum "$policy" | awk '{print $1}')"
  echo "WBQ_REPAIR_GUARDED_RESET_EXCLUSION_PREVIOUS_ATTEMPT_ARCHIVE=$archive"
  echo "WBQ_REPAIR_GUARDED_RESET_EXCLUSION_GIT_SHA=$(git -C "$root" rev-parse HEAD)"
  echo "WBQ_REPAIR_GUARDED_RESET_EXCLUSION_ORFS_SHA=$(git -C "$orfs_root" rev-parse HEAD)"
  echo "WBQ_REPAIR_GUARDED_RESET_EXCLUSION_OPENROAD_VERSION=$($openroad_exe -version 2>&1)"
} > "$report"

set +e
/usr/bin/time -v make -C "$orfs_flow" \
  DESIGN_CONFIG="$config" STOB_REPO_ROOT="$root" \
  YOSYS_EXE="$yosys_exe" OPENROAD_EXE="$openroad_exe" \
  PRE_RESIZE_TCL="$policy" NUM_CORES="${NUM_CORES:-16}" \
  SKIP_REPORT_METRICS=1 -j1 do-3_4_place_resized \
  >> "$report" 2>&1
rc=$?
set -e
{
  echo "WBQ_REPAIR_GUARDED_RESET_EXCLUSION_EXIT_CODE=$rc"
  echo "WBQ_REPAIR_GUARDED_RESET_EXCLUSION_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >> "$report"

test "$rc" -eq 0
test -s "$result_dir/3_4_place_resized.odb"
grep -q 'WBQ_GUARDED_RESET_EXCLUSION rst_ni=dont_touch,placement_parasitics_skip clk_i_alpha=0.0 ordinary_alpha=inherited' \
  "$log_dir/3_4_place_resized.log"
echo "NORMALIZATION_HBM_WBQ_REPAIR_GUARDED_RESET_EXCLUSION PASS odb=$result_dir/3_4_place_resized.odb" \
  | tee -a "$report"
