#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workspace="${repo_root}/b0_baseline_experiment"
base="${workspace}/orfs/results/sky130hd/b0_bank_only_baseline/base"
out="${workspace}/results/physical"
openroad=/home/chandler/.local/stob-eda/openroad/bin/openroad
lib=/home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
mkdir -p "${out}"
run_stage() {
  local name="$1" odb="$2" sdc="$3" spef="${4:-}"
  B0_LIBERTY="${lib}" B0_STAGE_NAME="${name}" B0_STAGE_ODB="${odb}" \
  B0_STAGE_SDC="${sdc}" B0_STAGE_SPEF="${spef}" \
    "${openroad}" -no_init -no_splash -exit "${workspace}/config/b0_stage_timing.tcl" \
    >"${out}/b0_${name}_timing.log" 2>&1
  grep -q "B0_STAGE_TIMING_END ${name}" "${out}/b0_${name}_timing.log"
}
run_stage post_cts "${base}/4_cts.odb" "${base}/4_cts.sdc"
run_stage post_route "${base}/6_final.odb" "${base}/6_final.sdc" "${base}/6_final.spef"
printf 'B0 post-CTS and post-route timing reports complete\n'
