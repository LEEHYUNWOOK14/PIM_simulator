#!/usr/bin/env bash
set -euo pipefail

# Recover a legal Phase-3 checkpoint after the full repair_design pass was
# externally interrupted.  This does not claim repair completion: it preserves
# the partial repair log and legalizes the last completed global-placement ODB.

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$root/verification/groot_normalization/eda_environment.sh"

config="$root/flow/designs/sky130hd/normalization_hbm_wbq/config.mk"
result_dir="$orfs_flow/results/sky130hd/normalization_hbm_wbq/base"
orfs_log_dir="$orfs_flow/logs/sky130hd/normalization_hbm_wbq/base"
raw_dir="$root/reports/groot_normalization/physical_feasibility"
recovery_log="$raw_dir/logic_die_normalization_hbm_top_wbq_place_recovery.log"
source_odb="$result_dir/3_3_place_gp.odb"
resize_odb="$result_dir/3_4_place_resized.odb"
partial_log="$orfs_log_dir/3_4_place_resized.tmp.log"
resize_log="$orfs_log_dir/3_4_place_resized.log"

if pgrep -f '[o]penroad.*normalization_hbm_wbq' >/dev/null; then
  echo "wbq OpenROAD job already running; refusing duplicate recovery" >&2
  exit 3
fi

test -s "$source_odb"
test -s "$result_dir/2_floorplan.sdc"
test -s "$partial_log"
mkdir -p "$raw_dir"

{
  echo "WBQ_PLACE_RECOVERY_CLASSIFICATION=interrupted"
  echo "WBQ_PLACE_RECOVERY_REASON=process_disappeared_without_tool_error_or_terminal_checkpoint_cause_unknown"
  echo "WBQ_PLACE_RECOVERY_REPAIR_COMPLETED=false"
  echo "WBQ_PLACE_RECOVERY_SOURCE_ODB=$source_odb"
  echo "WBQ_PLACE_RECOVERY_SOURCE_ODB_SHA256=$(sha256sum "$source_odb" | awk '{print $1}')"
  echo "WBQ_PLACE_RECOVERY_PARTIAL_LOG=$partial_log"
  echo "WBQ_PLACE_RECOVERY_PARTIAL_LOG_SHA256=$(sha256sum "$partial_log" | awk '{print $1}')"
  echo "WBQ_PLACE_RECOVERY_CONFIG_SHA256=$(sha256sum "$config" | awk '{print $1}')"
  echo "WBQ_PLACE_RECOVERY_GIT_SHA=$(git -C "$root" rev-parse HEAD)"
  echo "WBQ_PLACE_RECOVERY_ORFS_SHA=$(git -C "$orfs_root" rev-parse HEAD)"
  echo "WBQ_PLACE_RECOVERY_OPENROAD_VERSION=$($openroad_exe -version 2>&1)"
  echo "WBQ_PLACE_RECOVERY_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "WBQ_PLACE_RECOVERY_LAST_REPAIR_ROW=$(tail -n 1 "$partial_log" | sed 's/^[[:space:]]*//')"
} > "$recovery_log"

# ORFS detailed_place loads this conventional stage name.  The hash equality
# with 3_3_place_gp.odb is deliberate evidence that no completed repair output
# exists; the recovery manifest must retain this fact.
cp --reflink=auto --preserve=timestamps "$source_odb" "$resize_odb"
cp --preserve=timestamps "$partial_log" "$resize_log"

set +e
/usr/bin/time -v make -C "$orfs_flow" \
  DESIGN_CONFIG="$config" STOB_REPO_ROOT="$root" \
  YOSYS_EXE="$yosys_exe" OPENROAD_EXE="$openroad_exe" \
  NUM_CORES="${NUM_CORES:-16}" SKIP_REPORT_METRICS=1 -j1 place \
  >> "$recovery_log" 2>&1
rc=$?
set -e

{
  echo "WBQ_PLACE_RECOVERY_EXIT_CODE=$rc"
  echo "WBQ_PLACE_RECOVERY_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >> "$recovery_log"

test "$rc" -eq 0
test -s "$result_dir/3_place.odb"
test -s "$result_dir/3_place.sdc"
grep -q 'Placement Analysis' "$orfs_log_dir/3_5_place_dp.log"

bash "$root/verification/groot_normalization/run_normalization_hbm_wbq_place_audit.sh" \
  >> "$recovery_log" 2>&1

# A non-zero collector result is expected because repair_completed must remain
# false.  The generated manifest/HTML are still required recovery evidence.
set +e
python3 "$root/tools/collect_wbq_placement_evidence.py" >> "$recovery_log" 2>&1
collector_rc=$?
set -e
echo "WBQ_PLACE_RECOVERY_COLLECTOR_EXIT_CODE=$collector_rc" >> "$recovery_log"
test "$collector_rc" -eq 1
echo "NORMALIZATION_HBM_WBQ_PLACE_RECOVERY PARTIAL legal_odb=$result_dir/3_place.odb" \
  | tee -a "$recovery_log"
