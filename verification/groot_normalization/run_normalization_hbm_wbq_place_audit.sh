#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$root/verification/groot_normalization/eda_environment.sh"
result_dir="$orfs_flow/results/sky130hd/normalization_hbm_wbq/base"
audit_log="$physical_report_root/logic_die_normalization_hbm_top_wbq_place_audit.log"

odb="$result_dir/3_place.odb"
sdc="$result_dir/3_place.sdc"
test -s "$odb"
test -s "$sdc"

export WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd"
export WBQ_PLACE_ODB="$odb"
export WBQ_PLACE_SDC="$sdc"

{
  echo "WBQ_PLACE_AUDIT_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "WBQ_PLACE_AUDIT_ODB_SHA256=$(sha256sum "$odb" | awk '{print $1}')"
  echo "WBQ_PLACE_AUDIT_SDC_SHA256=$(sha256sum "$sdc" | awk '{print $1}')"
  "$openroad_exe" -exit -no_init -threads 1 -no_splash \
    "$root/verification/groot_normalization/audit_normalization_hbm_wbq_place.tcl"
  echo "WBQ_PLACE_AUDIT_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$audit_log" 2>&1

grep -q '^WBQ_PLACE_AUDIT_VIOLATIONS 0$' "$audit_log"
grep -q '^WBQ_PLACE_AUDIT_PASS$' "$audit_log"
echo "NORMALIZATION_HBM_WBQ_PLACE_AUDIT PASS log=$audit_log"
