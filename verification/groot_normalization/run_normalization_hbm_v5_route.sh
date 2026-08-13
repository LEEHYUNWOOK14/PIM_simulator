#!/usr/bin/env bash
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
report_root="$root/reports/groot_normalization/physical_feasibility"
log="$report_root/logic_die_normalization_hbm_top_v5_route.log"
guide="$report_root/logic_die_normalization_hbm_top_v5.route_guide"
congestion="$report_root/logic_die_normalization_hbm_top_v5.congestion.rpt"

if pgrep -f '[o]penroad.*normalization_hbm_v5_route\.tcl' >/dev/null; then
  echo "v5 route already running; refusing duplicate execution" >&2
  exit 3
fi

{
  echo "PF_V5_SOURCE_DB_SHA256=$(sha256sum "$report_root/logic_die_normalization_hbm_top_v5_bank_legal.odb" | awk '{print $1}')"
  echo "PF_V5_PLACEMENT_MODEL=BANK_AWARE_4X4_GUIDED_THEN_RELEASED"
  echo "PF_V5_PIN_MODEL=DISTRIBUTED_INTERNAL_MET5_20UM_LANDING_PAD"
  echo "PF_V5_CONGESTION_ITERATIONS=1"
  echo "PF_V5_GLOBAL_ROUTER=CUGR"
} > "$log"

set +e
/home/chandler/.local/stob-eda/openroad/bin/openroad -exit -no_init -threads 1 -no_splash \
  "$root/verification/groot_normalization/normalization_hbm_v5_route.tcl" \
  2>&1 | tee -a "$log"
openroad_rc=${PIPESTATUS[0]}
set -e
echo "PF_V5_OPENROAD_EXIT_CODE=$openroad_rc" | tee -a "$log"
test -s "$guide"
test -s "$congestion"
grep -q '^V5_ROUTE_PASS$' "$log"
test "$openroad_rc" -eq 0
