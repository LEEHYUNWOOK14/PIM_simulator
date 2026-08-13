#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
log="$root/reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_v2_repair_legalize.log"
/home/chandler/.local/stob-eda/openroad/bin/openroad -exit -no_init -threads 4 -no_splash \
  "$root/verification/groot_normalization/normalization_hbm_v2_repair_legalize.tcl" \
  2>&1 | tee "$log"
grep -q '^V2_REPAIR_LEGAL_PASS$' "$log"
