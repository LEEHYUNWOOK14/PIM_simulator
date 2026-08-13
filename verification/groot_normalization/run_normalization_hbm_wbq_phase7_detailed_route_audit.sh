#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$root/verification/groot_normalization/eda_environment.sh"

prefix="$physical_report_root/logic_die_normalization_hbm_top_wbq_phase7_detailed_route"
run_log="${prefix}.log"
odb="${prefix}.odb"
sdc="${prefix}.sdc"
audit_log="${prefix}_audit.log"

if pgrep -f '[o]penroad.*normalization_hbm_wbq' >/dev/null; then
  echo "wbq OpenROAD job already running; refusing concurrent detailed-route audit" >&2
  exit 3
fi

test -s "$run_log"
test -s "$odb"
test -s "$sdc"
grep -q '^WBQ_PHASE7_EXIT_CODE=0$' "$run_log"
grep -q '^NORMALIZATION_HBM_WBQ_PHASE7_DETAILED_ROUTE PASS ' "$run_log"
if test -e "$audit_log"; then
  echo "existing Phase-7 audit prevents overwrite: $audit_log" >&2
  exit 4
fi

export WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd"
export WBQ_DRT_ODB="$odb"
export WBQ_DRT_SDC="$sdc"

{
  echo "WBQ_PHASE7_AUDIT_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "WBQ_PHASE7_AUDIT_ODB_SHA256=$(sha256sum "$odb" | awk '{print $1}')"
  echo "WBQ_PHASE7_AUDIT_SDC_SHA256=$(sha256sum "$sdc" | awk '{print $1}')"
  "$openroad_exe" -exit -no_init -threads 1 -no_splash \
    "$root/verification/groot_normalization/audit_normalization_hbm_wbq_phase7_detailed_route.tcl"
  echo "WBQ_PHASE7_AUDIT_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$audit_log" 2>&1

grep -q '^WBQ_PHASE7_AUDIT_TOP logic_die_normalization_hbm_top$' "$audit_log"
grep -q '^WBQ_PHASE7_AUDIT_DESIGN_IS_ROUTED 1$' "$audit_log"
grep -q '^WBQ_PHASE7_AUDIT_PASS$' "$audit_log"
echo "NORMALIZATION_HBM_WBQ_PHASE7_DETAILED_ROUTE_AUDIT PASS log=$audit_log"
