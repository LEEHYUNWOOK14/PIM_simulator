#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$root/verification/groot_normalization/eda_environment.sh"
if [[ "${WBQ_B2:-0}" == 1 ]]; then
  nickname=normalization_hbm_quad_local_b2
  report_dir="$root/reports/groot_normalization/quad_local_b2"
  prefix=b2
else
  nickname=normalization_hbm_quad_local_ab
  report_dir="$root/reports/groot_normalization/quad_local_ab"
  prefix=b
fi
result_dir="$orfs_flow/results/sky130hd/$nickname/base"
log="$report_dir/${prefix}_global_route.log"
tcl="$root/verification/groot_normalization/wbq_quad_local_global_route.tcl"
place_odb="$result_dir/3_place.odb"
place_sdc="$result_dir/3_place.sdc"
test -s "$place_odb"
test -s "$place_sdc"
grep -q "WBQ_QUAD_LOCAL_PLACEMENT_AUDIT PASS" "$report_dir/${prefix}_place.log"
if pgrep -f '[o]penroad.*wbq_quad_local_global_route\.tcl' >/dev/null; then
  echo "B global route already running; refusing duplicate" >&2
  exit 3
fi
export WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd"
export WBQ_QUAD_PLACE_ODB="$place_odb"
export WBQ_QUAD_PLACE_SDC="$place_sdc"
export WBQ_QUAD_ROUTE_OUTPUT_ROOT="$report_dir"
export WBQ_QUAD_ROUTE_PREFIX="$prefix"
{
  echo "WBQ_QUAD_ROUTE_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "WBQ_QUAD_ROUTE_PLACE_ODB_SHA256=$(sha256sum "$place_odb" | awk '{print $1}')"
  echo "WBQ_QUAD_ROUTE_PLACE_SDC_SHA256=$(sha256sum "$place_sdc" | awk '{print $1}')"
} > "$log"
set +e
/usr/bin/time -v "$openroad_exe" -exit -no_init -threads 1 -no_splash "$tcl" >> "$log" 2>&1
rc=$?
set -e
echo "WBQ_QUAD_ROUTE_EXIT_CODE=$rc" >> "$log"
test "$rc" -eq 0
test -s "$report_dir/${prefix}_quad_local.route_guide"
test -s "$report_dir/${prefix}_quad_local.congestion.rpt"
test -s "$report_dir/${prefix}_quad_local_global_route.odb"
test -s "$report_dir/${prefix}_quad_local_global_route.sdc"
grep -q "WBQ_QUAD_LOCAL_GLOBAL_ROUTE PASS" "$log"
awk -f "$root/verification/groot_normalization/summarize_congestion.awk" \
  "$report_dir/${prefix}_quad_local.congestion.rpt" > "$report_dir/${prefix}_quad_local.congestion.summary"
awk -f "$root/verification/groot_normalization/classify_congestion_sources.awk" \
  "$report_dir/${prefix}_quad_local.congestion.rpt" > "$report_dir/${prefix}_quad_local.sources.summary"
echo "WBQ_QUAD_LOCAL_GLOBAL_ROUTE_RUN PASS guide=$report_dir/${prefix}_quad_local.route_guide" | tee -a "$log"
