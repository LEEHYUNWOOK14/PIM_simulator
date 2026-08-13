#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$root/verification/groot_normalization/eda_environment.sh"

prefix="$physical_report_root/logic_die_normalization_hbm_top_wbq_phase6_post_cts"
run_log="${prefix}_route.log"
routed_odb="${prefix}_global_route.odb"
routed_sdc="${prefix}_global_route.sdc"
audit_log="${prefix}_route_audit.log"

if pgrep -f '[o]penroad.*normalization_hbm_wbq' >/dev/null; then
  echo "wbq OpenROAD job already running; refusing concurrent route audit" >&2
  exit 3
fi

test -s "$run_log"
test -s "$routed_odb"
test -s "$routed_sdc"
grep -q '^WBQ_PHASE6_POST_CTS_EXIT_CODE=0$' "$run_log"
grep -q '^NORMALIZATION_HBM_WBQ_PHASE6_POST_CTS_ROUTE PASS ' "$run_log"
if test -e "$audit_log"; then
  echo "existing Phase-6 route audit prevents overwrite: $audit_log" >&2
  exit 4
fi

export WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd"
export WBQ_ROUTED_ODB="$routed_odb"
export WBQ_ROUTED_SDC="$routed_sdc"

{
  echo "WBQ_PHASE6_ROUTE_AUDIT_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "WBQ_PHASE6_ROUTE_AUDIT_ODB_SHA256=$(sha256sum "$routed_odb" | awk '{print $1}')"
  echo "WBQ_PHASE6_ROUTE_AUDIT_SDC_SHA256=$(sha256sum "$routed_sdc" | awk '{print $1}')"
  "$openroad_exe" -exit -no_init -threads 1 -no_splash \
    "$root/verification/groot_normalization/audit_normalization_hbm_wbq_phase6_post_cts_route.tcl"
  echo "WBQ_PHASE6_ROUTE_AUDIT_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$audit_log" 2>&1

grep -q '^WBQ_PHASE6_ROUTE_AUDIT_TOP logic_die_normalization_hbm_top$' "$audit_log"
grep -q '^WBQ_PHASE6_ROUTE_AUDIT_HAS_GLOBAL_ROUTES 1$' "$audit_log"
grep -q '^WBQ_PHASE6_ROUTE_AUDIT_VIOLATIONS 0$' "$audit_log"
grep -q '^WBQ_PHASE6_ROUTE_AUDIT_PASS$' "$audit_log"
echo "NORMALIZATION_HBM_WBQ_PHASE6_POST_CTS_ROUTE_AUDIT PASS log=$audit_log"
