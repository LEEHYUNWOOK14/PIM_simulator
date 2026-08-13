#!/usr/bin/env bash
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
report_root="$root/reports/groot_normalization/physical_feasibility"
log="$report_root/logic_die_normalization_hbm_top_v5_bank_place.log"

if pgrep -f '[o]penroad.*normalization_hbm_v5_bank_place\.tcl' >/dev/null; then
  echo "v5 bank placement already running; refusing duplicate execution" >&2
  exit 3
fi

{
  echo "PF_V5_SOURCE_DB_SHA256=$(sha256sum "$report_root/logic_die_normalization_hbm_top_v5_bank_regions.odb" | awk '{print $1}')"
  echo "PF_V5_GROUP_MODEL=16_SUGGESTED_PHYSICAL_CLUSTERS_4X4"
  echo "PF_V5_PIN_MODEL=DISTRIBUTED_INTERNAL_MET5_20UM_LANDING_PAD"
  echo "PF_V5_PLACE_DENSITY=0.39"
} > "$log"

set +e
/home/chandler/.local/stob-eda/openroad/bin/openroad -exit -no_init -threads 1 -no_splash \
  "$root/verification/groot_normalization/normalization_hbm_v5_bank_place.tcl" \
  2>&1 | tee -a "$log"
openroad_rc=${PIPESTATUS[0]}
set -e
echo "PF_V5_OPENROAD_EXIT_CODE=$openroad_rc" | tee -a "$log"
test -s "$report_root/logic_die_normalization_hbm_top_v5_bank_legal.odb"
grep -q '^V5_BANK_PLACE_PASS$' "$log"
test "$openroad_rc" -eq 0
