#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workspace="${repo_root}/b0_baseline_experiment"
cd "${repo_root}"
grep -q 'B0_FULL_PIM_SYSTEM_TB PASS' "${workspace}/results/functional/b0_run.log"
grep -q 'End of script' "${workspace}/results/synthesis/b0_generic_yosys.log"
grep -q 'End of script' "${workspace}/results/synthesis/b0_sky130_yosys.log"
grep -q 'B0_STA_MAX_PATH_END' "${workspace}/results/synthesis/b0_sky130_sta.log"
grep -q 'B0_STAGE_TIMING_END post_cts' "${workspace}/results/physical/b0_post_cts_timing.log"
grep -q 'B0_STAGE_TIMING_END post_route' "${workspace}/results/physical/b0_post_route_timing.log"
grep -q 'FULL_PIM_GDS PASS' "${workspace}/results/physical/b0_gds_validation.log"
grep -q 'Annotated 101486 pin activities' "${workspace}/results/power/b0_postroute_vcd_power.log"
python3 - <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import json
root=Path('b0_baseline_experiment')
for rel in ('plan/b0_experiment_plan.html','report/b0_experiment_report.html'):
    HTMLParser().feed((root/rel).read_text(encoding='utf-8'))
data=json.loads((root/'manifest/b0_final_manifest.json').read_text(encoding='utf-8'))
assert data['status']=='COMPLETE_WITH_FEASIBILITY_VIOLATIONS'
assert len(data['gates'])==10
PY
sha256sum \
  "${workspace}/plan/b0_experiment_plan.html" \
  "${workspace}/report/b0_experiment_report.html" \
  "${workspace}/manifest/b0_final_manifest.json" \
  "${workspace}/results/functional/b0_functional_results.csv" \
  "${workspace}/results/synthesis/b0_synthesis_metrics.csv" \
  "${workspace}/results/physical/b0_physical_metrics.csv" \
  "${workspace}/results/power/b0_power_metrics.csv" \
  >"${workspace}/manifest/final_delivery_sha256.txt"
printf 'B0 FINAL AUDIT PASS gates=10/10 status=COMPLETE_WITH_FEASIBILITY_VIOLATIONS\n' \
  | tee "${workspace}/manifest/final_audit.log"
