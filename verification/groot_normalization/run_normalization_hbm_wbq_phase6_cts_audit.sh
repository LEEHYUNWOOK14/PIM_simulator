#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$root/verification/groot_normalization/eda_environment.sh"

result_dir="$orfs_flow/results/sky130hd/normalization_hbm_wbq/base"
cts_odb="$result_dir/4_cts.odb"
cts_sdc="$result_dir/4_cts.sdc"
run_log="$physical_report_root/logic_die_normalization_hbm_top_wbq_phase6_cts.log"
audit_log="$physical_report_root/logic_die_normalization_hbm_top_wbq_phase6_cts_audit.log"

if pgrep -f '[o]penroad.*normalization_hbm_wbq' >/dev/null; then
  echo "wbq OpenROAD job already running; refusing concurrent CTS audit" >&2
  exit 3
fi

test -s "$cts_odb"
test -s "$cts_sdc"
test -s "$run_log"
grep -q '^WBQ_PHASE6_CTS_EXIT_CODE=0$' "$run_log"
grep -q '^NORMALIZATION_HBM_WBQ_PHASE6_CTS PASS ' "$run_log"

export WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd"
export WBQ_CTS_ODB="$cts_odb"
export WBQ_CTS_SDC="$cts_sdc"

{
  echo "WBQ_PHASE6_CTS_AUDIT_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "WBQ_PHASE6_CTS_AUDIT_ODB_SHA256=$(sha256sum "$cts_odb" | awk '{print $1}')"
  echo "WBQ_PHASE6_CTS_AUDIT_SDC_SHA256=$(sha256sum "$cts_sdc" | awk '{print $1}')"
  "$openroad_exe" -exit -no_init -threads 1 -no_splash \
    "$root/verification/groot_normalization/audit_normalization_hbm_wbq_phase6_cts.tcl"
  echo "WBQ_PHASE6_CTS_AUDIT_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$audit_log" 2>&1

grep -q '^WBQ_PHASE6_CTS_AUDIT_TOP logic_die_normalization_hbm_top$' "$audit_log"
grep -q '^WBQ_PHASE6_CTS_AUDIT_VIOLATIONS 0$' "$audit_log"
grep -q '^WBQ_PHASE6_CTS_AUDIT_PASS$' "$audit_log"
echo "NORMALIZATION_HBM_WBQ_PHASE6_CTS_AUDIT PASS log=$audit_log"
