#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
openroad=/home/chandler/.local/stob-eda/openroad/bin/openroad
log="$root/reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_coarse_route.log"
"$openroad" -exit -no_init -threads 4 -no_splash \
  "$root/verification/groot_normalization/normalization_hbm_coarse_route.tcl" \
  2>&1 | tee "$log"
grep -q '^COARSE_ROUTE_PASS$' "$log"
