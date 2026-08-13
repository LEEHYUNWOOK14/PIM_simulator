#!/usr/bin/env bash
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
report_root="$root/reports/groot_normalization/physical_feasibility"
log="$report_root/logic_die_normalization_hbm_top_v5_reclassified_legalize.log"

if pgrep -f '[o]penroad.*normalization_hbm_v5_reclassified_legalize\.tcl' >/dev/null; then
  echo "v5 reclassified legalization already running; refusing duplicate execution" >&2
  exit 3
fi

{
  echo "PF_V5_RECLASSIFIED_SOURCE_DB_SHA256=$(sha256sum "$report_root/logic_die_normalization_hbm_top_v5_bank_gp_reclassified.odb" | awk '{print $1}')"
  echo "PF_V5_RECLASSIFIED_SOURCE_SDC_SHA256=$(sha256sum "$report_root/logic_die_normalization_hbm_top_v2_repaired_legal.sdc" | awk '{print $1}')"
  echo "PF_V5_RECLASSIFIED_MODEL=1530_STRANDED_CELLS_TO_CONTAINING_BANK_GROUP_PLUS_TAPCELL_REBUILD"
  echo "PF_V5_RECLASSIFIED_TAPCELL_DISTANCE_UM=14"
  echo "PF_V5_RECLASSIFIED_MAX_DISPLACEMENT_UM=500x500"
} > "$log"

set +e
/home/chandler/.local/stob-eda/openroad/bin/openroad -exit -no_init -threads 1 -no_splash \
  "$root/verification/groot_normalization/normalization_hbm_v5_reclassified_legalize.tcl" \
  2>&1 | tee -a "$log"
openroad_rc=${PIPESTATUS[0]}
set -e
echo "PF_V5_RECLASSIFIED_OPENROAD_EXIT_CODE=$openroad_rc" | tee -a "$log"
test -s "$report_root/logic_die_normalization_hbm_top_v5_bank_legal.odb"
test -s "$report_root/logic_die_normalization_hbm_top_v5_bank_legal.sdc"
grep -q '^V5_RECLASSIFIED_LEGALIZE_PASS$' "$log"
test "$openroad_rc" -eq 0
