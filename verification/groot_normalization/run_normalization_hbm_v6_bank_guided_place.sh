#!/usr/bin/env bash
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
report_root="$root/reports/groot_normalization/physical_feasibility"
log="$report_root/logic_die_normalization_hbm_top_v6_bank_guided_place.log"
odb="$report_root/logic_die_normalization_hbm_top_v6_bank_guided_legal.odb"
sdc="$report_root/logic_die_normalization_hbm_top_v6_bank_guided_legal.sdc"

if pgrep -f '[o]penroad.*normalization_hbm_v6_bank_guided_place\.tcl' >/dev/null; then
  echo "v6 bank-guided placement already running; refusing duplicate execution" >&2
  exit 3
fi

{
  echo "PF_V6_SOURCE_REGION_DB_SHA256=$(sha256sum "$report_root/logic_die_normalization_hbm_top_v5_bank_regions.odb" | awk '{print $1}')"
  echo "PF_V6_SOURCE_SDC_SHA256=$(sha256sum "$report_root/logic_die_normalization_hbm_top_v2_repaired_legal.sdc" | awk '{print $1}')"
  echo "PF_V6_PLACE_DENSITY=0.39"
  echo "PF_V6_BANK_GUIDES=4x4_SUGGESTED"
  echo "PF_V6_PIN_MODEL=DISTRIBUTED_INTERNAL_MET5_20UM_LANDING_PAD"
} > "$log"

set +e
/home/chandler/.local/stob-eda/openroad/bin/openroad -exit -no_init -threads 1 -no_splash \
  "$root/verification/groot_normalization/normalization_hbm_v6_bank_guided_place.tcl" \
  2>&1 | tee -a "$log"
openroad_rc=${PIPESTATUS[0]}
set -e
echo "PF_V6_OPENROAD_EXIT_CODE=$openroad_rc" | tee -a "$log"
test -s "$odb"
test -s "$sdc"
grep -q '^V6_BANK_GUIDED_PLACE_PASS$' "$log"
test "$openroad_rc" -eq 0
