#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$root/verification/groot_normalization/eda_environment.sh"
result_dir="$orfs_flow/results/sky130hd/normalization_hbm_wbq/base"
output_root="$physical_report_root"
log="$output_root/logic_die_normalization_hbm_top_wbq_v4_control_route.log"
guide="$output_root/logic_die_normalization_hbm_top_wbq_v4_control.route_guide"
congestion="$output_root/logic_die_normalization_hbm_top_wbq_v4_control.congestion.rpt"
routed_odb="$output_root/logic_die_normalization_hbm_top_wbq_v4_control_global_route.odb"
routed_sdc="$output_root/logic_die_normalization_hbm_top_wbq_v4_control_global_route.sdc"
place_odb="$result_dir/3_place.odb"
place_sdc="$result_dir/3_place.sdc"
tcl="$root/verification/groot_normalization/normalization_hbm_wbq_v4_control_route.tcl"

if pgrep -f '[o]penroad.*normalization_hbm_wbq_v4_control_route\.tcl' >/dev/null; then
  echo "wbq V4-control route already running; refusing duplicate execution" >&2
  exit 3
fi
test -s "$place_odb"
test -s "$place_sdc"

export WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd"
export WBQ_PLACE_ODB="$place_odb"
export WBQ_PLACE_SDC="$place_sdc"
export WBQ_ROUTE_OUTPUT_ROOT="$output_root"

{
  echo "WBQ_ROUTE_GIT_SHA=$(git -C "$root" rev-parse HEAD)"
  echo "WBQ_ROUTE_PLACE_ODB_SHA256=$(sha256sum "$place_odb" | awk '{print $1}')"
  echo "WBQ_ROUTE_PLACE_SDC_SHA256=$(sha256sum "$place_sdc" | awk '{print $1}')"
  echo "WBQ_ROUTE_TCL_SHA256=$(sha256sum "$tcl" | awk '{print $1}')"
  echo "WBQ_ROUTE_PIN_MODEL=DISTRIBUTED_INTERNAL_MET5_20UM_LANDING_PAD"
  echo "WBQ_ROUTE_SIGNAL_LAYERS=met1-met5"
  echo "WBQ_ROUTE_CLOCK_LAYERS=met2-met5"
  echo "WBQ_ROUTE_CONGESTION_ITERATIONS=1"
  echo "WBQ_ROUTE_GLOBAL_ROUTER=CUGR"
  echo "WBQ_ROUTE_SKIP_LARGE_FANOUT_NETS=5000"
  echo "WBQ_ROUTE_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$log"

set +e
/usr/bin/time -v "$openroad_exe" -exit -no_init -threads 1 -no_splash "$tcl" >> "$log" 2>&1
rc=$?
set -e
echo "WBQ_ROUTE_EXIT_CODE=$rc" >> "$log"
echo "WBQ_ROUTE_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$log"

test "$rc" -eq 0
test -s "$guide"
test -s "$congestion"
test -s "$routed_odb"
test -s "$routed_sdc"
grep -q '^WBQ_V4_CONTROL_ROUTE_PASS$' "$log"
awk -f "$root/verification/groot_normalization/summarize_congestion.awk" "$congestion" \
  > "$output_root/logic_die_normalization_hbm_top_wbq_v4_control.congestion.summary"
awk -f "$root/verification/groot_normalization/classify_congestion_sources.awk" "$congestion" \
  > "$output_root/logic_die_normalization_hbm_top_wbq_v4_control.sources.summary"
echo "NORMALIZATION_HBM_WBQ_V4_CONTROL_ROUTE PASS guide=$guide" | tee -a "$log"
