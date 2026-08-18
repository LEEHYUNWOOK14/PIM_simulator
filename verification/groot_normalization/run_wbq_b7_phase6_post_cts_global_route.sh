#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"

report="$root/reports/groot_normalization/quad_local_b7"
evidence="$report/phase6"
cts_root="${WBQ_B7_PHASE6_ROOT:-/dev/shm/wbq_b7_phase6_10/phase6_cts}"
route_root="${WBQ_B7_PHASE6_ROUTE_ROOT:-/dev/shm/wbq_b7_phase6_10/phase6_post_cts}"
cts_manifest="$evidence/b7_phase6_cts_execution_report.json"
authorization="$evidence/b7_phase6_post_cts_route_authorization.json"
cts_odb="$cts_root/b7_phase6_cts.odb"
cts_sdc="$cts_root/b7_phase6_cts.sdc"
log="$evidence/b7_phase6_post_cts_global_route.log"
audit_log="$evidence/b7_phase6_post_cts_route_audit.log"
preflight="$evidence/b7_phase6_post_cts_preflight.json"
attempt="$evidence/b7_phase6_post_cts_global_route_invocation.json"
manifest="$evidence/b7_phase6_post_cts_global_route_execution_report.json"
guide="$route_root/b7_phase6_post_cts.route_guide"
congestion="$route_root/b7_phase6_post_cts.congestion.rpt"
routed_odb="$route_root/b7_phase6_post_cts_global_route.odb"
routed_sdc="$route_root/b7_phase6_post_cts_global_route.sdc"
analysis_json="$evidence/b7_phase6_post_cts_congestion_analysis.json"
analysis_md="$evidence/b7_phase6_post_cts_congestion_analysis.md"
runner="$root/verification/groot_normalization/run_wbq_b7_phase6_post_cts_global_route.sh"
tcl="$root/verification/groot_normalization/wbq_b7_phase6_post_cts_global_route.tcl"
audit_tcl="$root/verification/groot_normalization/audit_wbq_b7_phase6_post_cts_route.tcl"
parser="$root/tools/analyze_variant_residual_congestion.py"
snapshot_tool="$root/tools/capture_openroad_stage_snapshot.py"
compare_tool="$root/tools/compare_openroad_stage_snapshots.py"
runner_service="${WBQ_RUNNER_SERVICE:-wbq-b7-phase6-post-cts-route.service}"
frozen_a="$root/reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_wbq_v4_control_global_route.odb"
frozen_b="$root/reports/groot_normalization/quad_local_ab/b_quad_local_global_route.odb"
frozen_b2="$root/reports/groot_normalization/quad_local_b2/b2_quad_local_global_route.odb"

mkdir -p "$evidence" "$route_root"
for path in "$cts_manifest" "$authorization" "$cts_odb" "$cts_sdc" "$runner" "$tcl" "$audit_tcl" "$parser" \
  "$snapshot_tool" "$compare_tool" "$frozen_a" "$frozen_b" "$frozen_b2"; do
  test -s "$path"
done
python3 - "$cts_manifest" "$authorization" "$cts_odb" "$cts_sdc" "$runner" "$tcl" "$audit_tcl" "$parser" "$snapshot_tool" "$compare_tool" <<'PY'
import hashlib, json, pathlib, sys

def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

manifest = json.load(open(sys.argv[1], encoding="utf-8"))
authorization = json.load(open(sys.argv[2], encoding="utf-8"))
if manifest.get("status") != "PASS" or "B7_PHASE6_POST_CTS_GLOBAL_ROUTE_AUTHORIZATION" not in manifest.get("authorizes", []):
    raise SystemExit("B7 CTS gate does not authorize post-CTS route authorization")
if authorization.get("decision") != "PASS" or "B7_PHASE6_POST_CTS_GLOBAL_ROUTE_COMPUTE" not in authorization.get("authorizes", []):
    raise SystemExit("fresh B7 post-CTS route authorization is not PASS")
for key, text in (("cts_odb", sys.argv[3]), ("cts_sdc", sys.argv[4])):
    path = pathlib.Path(text)
    if sha(path) != manifest["artifacts"][key]["sha256"]:
        raise SystemExit(f"B7 post-CTS route input hash mismatch: {key}")
for key, text in (
    ("runner", sys.argv[5]), ("route_tcl", sys.argv[6]), ("audit_tcl", sys.argv[7]),
    ("direct_numeric_parser", sys.argv[8]), ("silence_snapshot_tool", sys.argv[9]),
    ("silence_compare_tool", sys.argv[10]),
):
    path = pathlib.Path(text)
    if sha(path) != authorization["inputs"][key]["sha256"]:
        raise SystemExit(f"B7 post-CTS route authorization hash mismatch: {key}")
print("WBQ_B7_PHASE6_POST_CTS_INPUT_GATE PASS")
PY

for path in "$preflight" "$attempt" "$manifest" "$log" "$audit_log" "$guide" "$congestion" \
  "$routed_odb" "$routed_sdc" "$analysis_json" "$analysis_md"; do
  if [[ -e "$path" ]]; then
    echo "B7 post-CTS global route has already been attempted; refusing duplicate ($path)" >&2
    exit 4
  fi
done
if pgrep -x openroad >/dev/null; then
  echo "an OpenROAD process already exists; refusing concurrent B7 post-CTS route" >&2
  pgrep -a -x openroad >&2 || true
  exit 3
fi
free_kib="$(df -Pk "$route_root" | awk 'NR==2 {print $4}')"
available_kib="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
if (( free_kib < 12 * 1024 * 1024 )); then
  echo "less than 12 GiB free for B7 post-CTS route" >&2
  exit 5
fi
if (( available_kib < 32 * 1024 * 1024 )); then
  echo "less than 32 GiB MemAvailable for B7 post-CTS route" >&2
  exit 6
fi

frozen_a_before="$(sha256sum "$frozen_a" | awk '{print $1}')"
frozen_b_before="$(sha256sum "$frozen_b" | awk '{print $1}')"
frozen_b2_before="$(sha256sum "$frozen_b2" | awk '{print $1}')"
[[ "$frozen_a_before" == 964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad ]]
[[ "$frozen_b_before" == ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235 ]]
[[ "$frozen_b2_before" == 2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d ]]

start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cts_manifest_sha="$(sha256sum "$cts_manifest" | awk '{print $1}')"
authorization_sha="$(sha256sum "$authorization" | awk '{print $1}')"
cts_odb_sha="$(sha256sum "$cts_odb" | awk '{print $1}')"
cts_sdc_sha="$(sha256sum "$cts_sdc" | awk '{print $1}')"
runner_sha="$(sha256sum "$runner" | awk '{print $1}')"
tcl_sha="$(sha256sum "$tcl" | awk '{print $1}')"
audit_tcl_sha="$(sha256sum "$audit_tcl" | awk '{print $1}')"
parser_sha="$(sha256sum "$parser" | awk '{print $1}')"
snapshot_tool_sha="$(sha256sum "$snapshot_tool" | awk '{print $1}')"
compare_tool_sha="$(sha256sum "$compare_tool" | awk '{print $1}')"
python3 - "$preflight" "$attempt" "$start" "$runner_service" "$$" "$cts_manifest" "$cts_manifest_sha" \
  "$authorization" "$authorization_sha" "$cts_odb" "$cts_odb_sha" "$cts_sdc" "$cts_sdc_sha" \
  "$runner" "$runner_sha" "$tcl" "$tcl_sha" "$audit_tcl" "$audit_tcl_sha" "$parser" "$parser_sha" \
  "$snapshot_tool" "$snapshot_tool_sha" "$compare_tool" "$compare_tool_sha" "$free_kib" "$available_kib" \
  "$frozen_a_before" "$frozen_b_before" "$frozen_b2_before" <<'PY'
import json, sys

(preflight, attempt, start, service, wrapper_pid, cts_manifest, cts_manifest_sha, authorization,
 authorization_sha, odb, odb_sha, sdc, sdc_sha, runner, runner_sha, tcl, tcl_sha, audit_tcl,
 audit_tcl_sha, parser, parser_sha, snapshot_tool, snapshot_tool_sha, compare_tool, compare_tool_sha,
 free_kib, available_kib, frozen_a, frozen_b, frozen_b2) = sys.argv[1:]
payload = {
    "schema_version": 2, "phase": 6, "variant": "B7_PHASE6_POST_CTS", "status": "STARTED",
    "generated_at_utc": start, "service": service, "wrapper_pid": int(wrapper_pid),
    "launcher_pid": None, "compute_pid": None, "audit_compute_pid": None,
    "command": "openroad -exit -no_init -threads 1 -no_splash wbq_b7_phase6_post_cts_global_route.tcl",
    "global_route_invocation_limit": 1, "cugr_congestion_iterations": 10,
    "skip_large_fanout_nets": 20000,
    "reason_for_20000_limit": "sealed mapped contract measured reset leaves up to 13671 sinks and forbids skipping rst_ni",
    "resources": {"free_kib": int(free_kib), "mem_available_kib": int(available_kib)},
    "inputs": {
        "cts_manifest": {"path": cts_manifest, "sha256": cts_manifest_sha},
        "route_authorization": {"path": authorization, "sha256": authorization_sha},
        "cts_odb": {"path": odb, "sha256": odb_sha}, "cts_sdc": {"path": sdc, "sha256": sdc_sha},
        "runner": {"path": runner, "sha256": runner_sha}, "route_tcl": {"path": tcl, "sha256": tcl_sha},
        "audit_tcl": {"path": audit_tcl, "sha256": audit_tcl_sha},
        "direct_numeric_parser": {"path": parser, "sha256": parser_sha},
        "silence_snapshot_tool": {"path": snapshot_tool, "sha256": snapshot_tool_sha},
        "silence_compare_tool": {"path": compare_tool, "sha256": compare_tool_sha},
    },
    "protected_hashes_before": {"frozen_A": frozen_a, "B": frozen_b, "B2": frozen_b2},
    "expected_artifacts": ["route_guide", "congestion_report", "routed_odb", "routed_sdc"],
    "authorizes": ["B7_PHASE6_POST_CTS_GLOBAL_ROUTE_COMPUTE"],
    "next_stage": "B7_PHASE6_POST_CTS_GLOBAL_ROUTE_COMPUTE",
}
with open(preflight, "x", encoding="utf-8") as stream:
    json.dump({**payload, "status": "PASS"}, stream, indent=2); stream.write("\n")
with open(attempt, "x", encoding="utf-8") as stream:
    json.dump({**payload, "invocation_count": 1}, stream, indent=2); stream.write("\n")
PY

compute_pid=""
launcher_pid=""
audit_compute_pid=""
termination_signal=""
finalized=0

refresh_compute_pid() {
  mapfile -t openroad_pids < <(pgrep -x openroad || true)
  if (( ${#openroad_pids[@]} == 1 )); then
    compute_pid="${openroad_pids[0]}"
  fi
}

on_signal() {
  termination_signal="$1"
  echo "WBQ_B7_PHASE6_POST_CTS_SIGNAL=$termination_signal" >> "$log"
  refresh_compute_pid
  if [[ -n "$compute_pid" ]] && kill -0 "$compute_pid" 2>/dev/null; then
    kill -TERM "$compute_pid"
  elif [[ -n "$audit_compute_pid" ]] && kill -0 "$audit_compute_pid" 2>/dev/null; then
    kill -TERM "$audit_compute_pid"
  fi
}

write_fail_closed_manifest() {
  local exit_code="$1"
  [[ -e "$manifest" ]] && return
  python3 - "$manifest" "$attempt" "$log" "$audit_log" "$guide" "$congestion" "$routed_odb" "$routed_sdc" \
    "$analysis_json" "$exit_code" "$termination_signal" <<'PY'
import hashlib, json, pathlib, sys

(manifest, attempt, log, audit_log, guide, congestion, odb, sdc, analysis, exit_code, signal) = sys.argv[1:]
def item(text):
    path = pathlib.Path(text)
    if not path.exists(): return {"path": str(path), "exists": False, "bytes": 0, "sha256": None}
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""): digest.update(chunk)
    return {"path": str(path), "exists": True, "bytes": path.stat().st_size, "sha256": digest.hexdigest()}
attempt_data = json.load(open(attempt, encoding="utf-8"))
payload = {
    "schema_version": 2, "phase": 6, "variant": "B7_PHASE6_POST_CTS", "status": "FAIL",
    "failure_class": "interrupted" if signal else "tool_error", "invocation_count": 1,
    "start_utc": attempt_data["generated_at_utc"],
    "end_utc": __import__("datetime").datetime.now(__import__("datetime").timezone.utc).isoformat(),
    "exit_code": int(exit_code), "termination_signal": signal or None,
    "service": attempt_data.get("service"), "wrapper_pid": attempt_data.get("wrapper_pid"),
    "launcher_pid": attempt_data.get("launcher_pid"), "compute_pid": attempt_data.get("compute_pid"),
    "audit_compute_pid": attempt_data.get("audit_compute_pid"),
    "inputs": attempt_data.get("inputs", {}),
    "artifacts": {"log": item(log), "audit_log": item(audit_log), "guide": item(guide),
                  "congestion_report": item(congestion), "routed_odb": item(odb), "routed_sdc": item(sdc),
                  "direct_analysis": item(analysis)},
    "authorizes": [], "next_stage": None,
}
with open(manifest, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2); stream.write("\n")
PY
}

on_exit() {
  local exit_code="$?"
  if (( finalized == 0 )); then
    refresh_compute_pid
    if [[ -n "$compute_pid" ]] && kill -0 "$compute_pid" 2>/dev/null; then kill -TERM "$compute_pid" 2>/dev/null || true; fi
    if [[ -n "$audit_compute_pid" ]] && kill -0 "$audit_compute_pid" 2>/dev/null; then kill -TERM "$audit_compute_pid" 2>/dev/null || true; fi
    write_fail_closed_manifest "$exit_code" || true
  fi
}

trap 'on_signal INT' INT
trap 'on_signal TERM' TERM
trap 'on_exit' EXIT

{
  echo "WBQ_B7_PHASE6_POST_CTS_START_UTC=$start"
  echo "WBQ_B7_PHASE6_POST_CTS_GLOBAL_ROUTE_INVOCATION_COUNT=1"
  echo "WBQ_B7_PHASE6_POST_CTS_CUGR_ITERATIONS=10"
  echo "WBQ_B7_PHASE6_POST_CTS_SKIP_LARGE_FANOUT_NETS=20000"
  echo "WBQ_B7_PHASE6_POST_CTS_SERVICE=$runner_service"
  echo "WBQ_B7_PHASE6_POST_CTS_WRAPPER_PID=$$"
  echo "WBQ_B7_PHASE6_POST_CTS_MANIFEST_SHA256=$cts_manifest_sha"
  echo "WBQ_B7_PHASE6_POST_CTS_AUTHORIZATION_SHA256=$authorization_sha"
  echo "WBQ_B7_PHASE6_POST_CTS_ODB_SHA256=$cts_odb_sha"
  echo "WBQ_B7_PHASE6_POST_CTS_SDC_SHA256=$cts_sdc_sha"
} > "$log"
export WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd"
export WBQ_CTS_ODB="$cts_odb"
export WBQ_CTS_SDC="$cts_sdc"
export WBQ_ROUTE_OUTPUT_ROOT="$route_root"
export WBQ_B7_PHASE6_CUGR_CONGESTION_ITERATIONS=10
/usr/bin/time -v "$openroad_exe" -exit -no_init -threads 1 -no_splash "$tcl" >> "$log" 2>&1 &
launcher_pid="$!"
echo "WBQ_B7_PHASE6_POST_CTS_LAUNCHER_PID=$launcher_pid" >> "$log"
python3 - "$attempt" "$launcher_pid" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1]); data = json.loads(path.read_text(encoding="utf-8"))
data["launcher_pid"] = int(sys.argv[2]); path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
for _ in $(seq 1 120); do
  refresh_compute_pid
  if [[ -n "$compute_pid" ]]; then
    echo "WBQ_B7_PHASE6_POST_CTS_COMPUTE_PID=$compute_pid" >> "$log"
    python3 - "$attempt" "$compute_pid" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1]); data = json.loads(path.read_text(encoding="utf-8"))
data["compute_pid"] = int(sys.argv[2]); path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
    break
  fi
  kill -0 "$launcher_pid" 2>/dev/null || break
  sleep 1
done
set +e
wait "$launcher_pid"
route_rc=$?
set -e
compute_pid=""
echo "WBQ_B7_PHASE6_POST_CTS_EXIT_CODE=$route_rc" >> "$log"
echo "WBQ_B7_PHASE6_POST_CTS_ROUTE_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$log"

audit_rc=1
if [[ "$route_rc" -eq 0 && -s "$routed_odb" && -s "$routed_sdc" ]]; then
  {
    echo "WBQ_B7_PHASE6_ROUTE_AUDIT_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "WBQ_B7_PHASE6_ROUTE_AUDIT_ODB_SHA256=$(sha256sum "$routed_odb" | awk '{print $1}')"
    echo "WBQ_B7_PHASE6_ROUTE_AUDIT_SDC_SHA256=$(sha256sum "$routed_sdc" | awk '{print $1}')"
  } > "$audit_log"
  WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd" WBQ_ROUTED_ODB="$routed_odb" WBQ_ROUTED_SDC="$routed_sdc" \
    "$openroad_exe" -exit -no_init -threads 1 -no_splash "$audit_tcl" >> "$audit_log" 2>&1 &
  audit_compute_pid="$!"
  python3 - "$attempt" "$audit_compute_pid" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1]); data = json.loads(path.read_text(encoding="utf-8"))
data["audit_compute_pid"] = int(sys.argv[2]); path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
  set +e
  wait "$audit_compute_pid"
  audit_rc=$?
  set -e
  audit_compute_pid=""
  echo "WBQ_B7_PHASE6_ROUTE_AUDIT_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$audit_log"
fi

analysis_rc=1
if [[ "$route_rc" -eq 0 && "$audit_rc" -eq 0 && -s "$guide" && -e "$congestion" ]]; then
  set +e
  python3 "$parser" \
    --variant B7_PHASE6_POST_CTS --pass-token 'WBQ_B7_PHASE6_POST_CTS_GLOBAL_ROUTE PASS' --cugr-iterations 10 \
    --report "$congestion" --log "$log" --guide "$guide" --odb "$routed_odb" --sdc "$routed_sdc" \
    --invocation "$attempt" --output-json "$analysis_json" --output-md "$analysis_md" \
    --max-hotspots-in-output 500 --max-windows-in-output 0
  analysis_rc=$?
  set -e
fi
end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
frozen_a_after="$(sha256sum "$frozen_a" | awk '{print $1}')"
frozen_b_after="$(sha256sum "$frozen_b" | awk '{print $1}')"
frozen_b2_after="$(sha256sum "$frozen_b2" | awk '{print $1}')"

python3 - "$manifest" "$attempt" "$end" "$route_rc" "$audit_rc" "$analysis_rc" "$termination_signal" \
  "$log" "$audit_log" "$guide" "$congestion" "$routed_odb" "$routed_sdc" "$analysis_json" "$analysis_md" \
  "$frozen_a_after" "$frozen_b_after" "$frozen_b2_after" <<'PY'
import hashlib, json, pathlib, re, sys

(manifest, attempt, end, route_rc, audit_rc, analysis_rc, signal, log, audit_log, guide,
 congestion, odb, sdc, analysis, analysis_md, frozen_a, frozen_b, frozen_b2) = sys.argv[1:]
def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""): digest.update(chunk)
    return digest.hexdigest()
def item(text):
    path = pathlib.Path(text)
    return {"path": str(path), "exists": path.exists(), "bytes": path.stat().st_size if path.exists() else 0,
            "sha256": sha(path) if path.exists() else None}
run_text = pathlib.Path(log).read_text(encoding="utf-8", errors="replace")
skipped = [{"net": net, "terminals": int(terminals)} for net, terminals in
           re.findall(r"Skipping net (\S+) with (\d+) terminals", run_text)]
analysis_data = json.load(open(analysis, encoding="utf-8")) if pathlib.Path(analysis).exists() else {}
totals = analysis_data.get("totals", {})
attempt_data = json.load(open(attempt, encoding="utf-8"))
after = {"frozen_A": frozen_a, "B": frozen_b, "B2": frozen_b2}
preserved = after == attempt_data["protected_hashes_before"]
passed = (int(route_rc) == 0 and int(audit_rc) == 0 and int(analysis_rc) == 0 and not signal
          and totals.get("rrr_residual") == 0 and totals.get("overflow_edges") == 0
          and attempt_data.get("compute_pid") is not None and attempt_data.get("audit_compute_pid") is not None
          and not skipped and preserved and "WBQ_B7_PHASE6_POST_CTS_ROUTE_AUDIT PASS" in pathlib.Path(audit_log).read_text(errors="replace"))
payload = {
    "schema_version": 2, "phase": 6, "variant": "B7_PHASE6_POST_CTS",
    "status": "PASS" if passed else "FAIL",
    "verdict": "PASS_POST_CTS_ZERO_CONGESTION" if passed else "ROUTED_NOT_CLOSED",
    "failure_class": None if passed else ("interrupted" if signal else "design_fail"),
    "invocation_count": 1, "audit_invocation_count": 1 if pathlib.Path(audit_log).exists() else 0,
    "cugr_congestion_iterations": 10, "start_utc": attempt_data["generated_at_utc"], "end_utc": end,
    "exit_code": int(route_rc), "audit_exit_code": int(audit_rc), "direct_parser_exit_code": int(analysis_rc),
    "termination_signal": signal or None, "service": attempt_data.get("service"),
    "wrapper_pid": attempt_data.get("wrapper_pid"), "compute_pid": attempt_data.get("compute_pid"),
    "launcher_pid": attempt_data.get("launcher_pid"),
    "audit_compute_pid": attempt_data.get("audit_compute_pid"), "inputs": attempt_data["inputs"],
    "skipped_nets": skipped,
    "metrics": {"rrr_residual": totals.get("rrr_residual"), "overflow_edges": totals.get("overflow_edges"),
                "overflow_tracks": totals.get("overflow_tracks"), "congestion_windows": totals.get("windows")},
    "protected_hashes_before": attempt_data["protected_hashes_before"], "protected_hashes_after": after,
    "protected_artifacts_preserved": preserved,
    "artifacts": {"log": item(log), "audit_log": item(audit_log), "guide": item(guide),
                  "congestion_report": item(congestion), "routed_odb": item(odb), "routed_sdc": item(sdc),
                  "direct_analysis": item(analysis), "direct_analysis_markdown": item(analysis_md)},
    "authorizes": ["B7_PHASE7_DETAILED_ROUTE_AUTHORIZATION"] if passed else [],
    "next_stage": "B7_PHASE7_DETAILED_ROUTE_AUTHORIZATION" if passed else None,
    "claim_boundary": "Post-CTS global-route research checkpoint; detailed route and manufacturing signoff are not established.",
}
with open(manifest, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2); stream.write("\n")
PY

finalized=1
trap - EXIT INT TERM
test "$route_rc" -eq 0
test "$audit_rc" -eq 0
test "$analysis_rc" -eq 0
grep -q '"status": "PASS"' "$manifest"
echo "WBQ_B7_PHASE6_POST_CTS_GLOBAL_ROUTE PASS report=$manifest"

