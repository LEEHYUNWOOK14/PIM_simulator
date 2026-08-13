#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$root/verification/groot_normalization/eda_environment.sh"
odb="$orfs_flow/results/sky130hd/normalization_hbm_wbq/base/3_3_place_gp.odb"
log="$physical_report_root/logic_die_normalization_hbm_top_wbq_net_fanout_audit.log"
test -s "$odb"
export WBQ_FANOUT_ODB="$odb"
{
  echo "WBQ_FANOUT_AUDIT_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "WBQ_FANOUT_AUDIT_ODB_SHA256=$(sha256sum "$odb" | awk '{print $1}')"
  /usr/bin/time -v "$openroad_exe" -exit -no_init -threads 1 -no_splash \
    "$root/verification/groot_normalization/audit_normalization_hbm_wbq_net_fanout.tcl"
  echo "WBQ_FANOUT_AUDIT_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$log" 2>&1
grep -q '^WBQ_FANOUT_AUDIT_PASS$' "$log"
echo "NORMALIZATION_HBM_WBQ_NET_FANOUT_AUDIT PASS log=$log"
