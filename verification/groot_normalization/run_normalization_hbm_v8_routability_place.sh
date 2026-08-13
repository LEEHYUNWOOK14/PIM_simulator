#!/usr/bin/env bash
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
report_root="$root/reports/groot_normalization/physical_feasibility"
log="$report_root/logic_die_normalization_hbm_top_v8_routability_place.log"

if pgrep -f '/[o]penroad/bin/openroad' >/dev/null; then
  echo "another OpenROAD process is running; refusing concurrent v8 placement" >&2
  exit 3
fi

{
  echo "PF_V8_SOURCE_DB_SHA256=$(sha256sum "$report_root/logic_die_normalization_hbm_top_v2_repaired_legal.odb" | awk '{print $1}')"
  echo "PF_V8_SOURCE_SDC_SHA256=$(sha256sum "$report_root/logic_die_normalization_hbm_top_v2_repaired_legal.sdc" | awk '{print $1}')"
  echo "PF_V8_PLACEMENT_MODEL=UNCONSTRAINED_ROUTABILITY_DRIVEN"
  echo "PF_V8_TARGET_DENSITY=0.42"
  echo "PF_V8_PIN_MODEL=DISTRIBUTED_INTERNAL_MET5_20UM_LANDING_PAD"
  echo "PF_V8_RANDOM_SEED=42"
} > "$log"

set +e
/home/chandler/.local/stob-eda/openroad/bin/openroad -exit -no_init -threads 1 -no_splash \
  "$root/verification/groot_normalization/normalization_hbm_v8_routability_place.tcl" \
  2>&1 | tee -a "$log"
openroad_rc=${PIPESTATUS[0]}
set -e
echo "PF_V8_OPENROAD_EXIT_CODE=$openroad_rc" | tee -a "$log"
test -s "$report_root/logic_die_normalization_hbm_top_v8_routability_legal.odb"
test -s "$report_root/logic_die_normalization_hbm_top_v8_routability_legal.sdc"
grep -q '^V8_ROUTABILITY_PLACE_PASS$' "$log"
test "$openroad_rc" -eq 0
