#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cli_handoff_gate="$root/reports/final_integrated_gds_execution/CLI_OWNS_PHASE4"

stop_for_cli_handoff() {
  if test -f "$cli_handoff_gate"; then
    echo "WBQ_PHASE4_STOPPED_FOR_CLI_HANDOFF gate=$cli_handoff_gate"
    exit 0
  fi
}

stop_for_cli_handoff

phase3_watcher_pid="${1:?usage: $0 PHASE3_WATCHER_PID}"
placement_json_rel="reports/final_integrated_gds_execution/wbq_placement_manifest.json"
placement_html_rel="reports/final_integrated_gds_execution/03_wbq_placement_report.html"
route_json_rel="reports/final_integrated_gds_execution/wbq_global_route_manifest.json"
route_html_rel="reports/final_integrated_gds_execution/04_wbq_global_route_report.html"
decision_json_rel="reports/final_integrated_gds_execution/wbq_post_route_decision.json"
placement_json="$root/$placement_json_rel"
placement_html="$root/$placement_html_rel"
route_json="$root/$route_json_rel"
route_html="$root/$route_html_rel"
decision_json="$root/$decision_json_rel"

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
  echo "WBQ_FOLLOWUP_REMOTE_SHA_MATCH $local_sha"
}

commit_reports() {
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

echo "WBQ_PHASE3_PHASE4_FOLLOWUP_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
wait_for_pid_exit "$phase3_watcher_pid"
stop_for_cli_handoff

python3 - "$placement_json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
manifest = json.loads(path.read_text(encoding="utf-8"))
if manifest.get("gate_pass") is not True:
    raise SystemExit("Phase-3 placement manifest gate_pass is not true")
print("WBQ_FOLLOWUP_PHASE3_GATE PASS")
PY
test -s "$placement_html"
commit_reports "Record wbq placement and legalization evidence" \
  "$placement_json_rel" "$placement_html_rel"

bash "$root/verification/groot_normalization/run_normalization_hbm_wbq_v4_control_route.sh"
python3 "$root/tools/run_wbq_post_route_transition.py"
test -s "$route_json"
test -s "$route_html"
test -s "$decision_json"
commit_reports "Record wbq global route comparison and next-stage decision" \
  "$route_json_rel" "$route_html_rel" "$decision_json_rel"

echo "WBQ_PHASE3_PHASE4_FOLLOWUP_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
