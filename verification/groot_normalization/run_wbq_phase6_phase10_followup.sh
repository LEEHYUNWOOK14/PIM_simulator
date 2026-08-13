#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
decision_watcher_pid="${1:?usage: $0 POST_ROUTE_DECISION_WATCHER_PID}"
out="reports/final_integrated_gds_execution"
decision_rel="$out/wbq_post_route_decision.json"
decision="$root/$decision_rel"

wait_for_pid_exit() {
  local pid="$1"
  while test -d "/proc/$pid"; do
    sleep 30
  done
}

verify_remote_head() {
  local local_sha remote_sha
  local_sha="$(git -C "$root" rev-parse HEAD)"
  remote_sha="$(git -C "$root" ls-remote origin refs/heads/PIM_Simulator | awk '{print $1}')"
  test -n "$remote_sha"
  test "$local_sha" = "$remote_sha"
  echo "WBQ_PHASE6_PHASE10_REMOTE_SHA_MATCH $local_sha"
}

commit_paths() {
  local message="$1"
  shift
  git -C "$root" diff --check -- "$@"
  git -C "$root" add -- "$@"
  if ! git -C "$root" diff --cached --quiet -- "$@"; then
    git -C "$root" commit -m "$message" -- "$@"
  fi
  git -C "$root" push origin PIM_Simulator
  verify_remote_head
}

commit_forced_paths() {
  local message="$1"
  shift
  git -C "$root" diff --check -- "$@"
  git -C "$root" add -f -- "$@"
  if ! git -C "$root" diff --cached --quiet -- "$@"; then
    git -C "$root" commit -m "$message" -- "$@"
  fi
  git -C "$root" push origin PIM_Simulator
  verify_remote_head
}

echo "WBQ_PHASE6_PHASE10_FOLLOWUP_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
wait_for_pid_exit "$decision_watcher_pid"
test -s "$decision"

decision_value="$(python3 - "$decision" <<'PY'
import json
import sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
print(doc.get("decision", ""))
PY
)"
commit_paths "Record wbq post-route phase decision" "$decision_rel"

if test "$decision_value" = "PHASE5_HIERARCHICAL_ARCHITECTURE"; then
  echo "WBQ_PHASE6_PHASE10_STOP_PHASE5_REQUIRED"
  exit 0
fi
if test "$decision_value" != "PHASE6_CLOCK_AND_DETAILED_ROUTE"; then
  echo "invalid or unsafe post-route decision: $decision_value" >&2
  exit 2
fi

bash "$root/verification/groot_normalization/run_normalization_hbm_wbq_phase6_cts.sh"
bash "$root/verification/groot_normalization/run_normalization_hbm_wbq_phase6_cts_audit.sh"
python3 "$root/tools/collect_wbq_phase6_cts_evidence.py"
commit_paths "Record wbq CTS evidence" \
  "$out/wbq_phase6_cts_manifest.json" \
  "$out/06_clock_and_detailed_route_report.html"

bash "$root/verification/groot_normalization/run_normalization_hbm_wbq_phase6_post_cts_route.sh"
bash "$root/verification/groot_normalization/run_normalization_hbm_wbq_phase6_post_cts_route_audit.sh"
python3 "$root/tools/collect_wbq_phase6_post_cts_route_evidence.py"
commit_paths "Record wbq post-CTS route evidence" \
  "$out/wbq_phase6_post_cts_route_manifest.json" \
  "$out/06_clock_and_detailed_route_report.html"

bash "$root/verification/groot_normalization/run_normalization_hbm_wbq_phase7_detailed_route.sh"
bash "$root/verification/groot_normalization/run_normalization_hbm_wbq_phase7_detailed_route_audit.sh"
python3 "$root/tools/collect_wbq_phase7_detailed_route_evidence.py"
commit_paths "Record wbq detailed-route evidence" \
  "$out/wbq_phase7_detailed_route_manifest.json" \
  "$out/06_clock_and_detailed_route_report.html"

bash "$root/tools/run_wbq_phase7_rtl_gds_streamout.sh"
python3 "$root/tools/check_wbq_phase7_rtl_gds.py"
commit_paths "Record wbq RTL GDS readback evidence" \
  "$out/wbq_phase7_rtl_gds_manifest.json" \
  "$out/07_rtl_gds_report.html"

bash "$root/tools/run_wbq_overlay_freeze.sh"
commit_forced_paths "Freeze wbq research overlay evidence" \
  "$out/wbq_overlay_validation.json" \
  "$out/08_overlay_merge_report.html" \
  "output/final_integrated_gds/inputs/floorplan_manifest.json" \
  "output/final_integrated_gds/inputs/floorplan_transform.json" \
  "output/final_integrated_gds/inputs/tsv_connectivity.csv"

bash "$root/tools/run_wbq_final_gds_merge.sh"
bash "$root/tools/run_wbq_final_gds_render.sh"
python3 "$root/tools/audit_wbq_final_completion.py"
commit_forced_paths "Audit final integrated wbq research GDS" \
  "$out/wbq_final_completion_manifest.json" \
  "$out/09_final_completion_report.html" \
  "output/final_integrated_gds/recipe/final_gds_merge_recipe.json" \
  "output/final_integrated_gds/validation/merged_final_physical_report.json"

echo "WBQ_PHASE6_PHASE10_FOLLOWUP_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
