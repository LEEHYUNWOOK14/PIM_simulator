#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"

report="$root/reports/groot_normalization/quad_local_b23"
physical="$report/physical"
artifacts="${WBQ_B23_ARTIFACT_ROOT:-/dev/shm/wbq_b23_phase6_10/quad_local_b23}"
placement="$root/reports/groot_normalization/quad_local_b9/physical/b9_placement_execution_report.json"
numeric="$root/reports/groot_normalization/quad_local_b9/physical/b9_placement_numeric_analysis.json"
targeted_audit="$root/reports/groot_normalization/quad_local_b9/physical/b9_targeted_placement_reopen_audit.json"
authorization="$report/b23_global_route_authorization.json"
place_odb="/dev/shm/wbq_b9_phase6_10/quad_local_b9/b9_place.odb"
place_sdc="/dev/shm/wbq_b9_phase6_10/quad_local_b9/b9_place.sdc"
log="$physical/b23_global_route.log"
guide="$artifacts/b23_quad_local.route_guide"
congestion="$artifacts/b23_quad_local.congestion.rpt"
routed_odb="$artifacts/b23_quad_local_global_route.odb"
routed_sdc="$artifacts/b23_quad_local_global_route.sdc"
attempt="$physical/b23_global_route_invocation.json"
manifest="$physical/b23_global_route_execution_report.json"
analysis_json="$report/b23_residual_congestion_analysis.json"
analysis_md="$report/b23_residual_congestion_analysis.md"
tcl="$root/verification/groot_normalization/wbq_quad_local_b23_global_route.tcl"
parser="$root/tools/analyze_variant_residual_congestion.py"
strict_gate="$root/tools/decide_b23_phase6_strict_gate.py"
snapshot_tool="$root/tools/capture_openroad_stage_snapshot.py"
compare_tool="$root/tools/compare_openroad_stage_snapshots.py"
runner="$root/verification/groot_normalization/run_wbq_quad_local_b23_global_route.sh"
runner_service="${WBQ_RUNNER_SERVICE:-wbq-b23-global-route.service}"

frozen_a="$root/reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_wbq_v4_control_global_route.odb"
frozen_b="$root/reports/groot_normalization/quad_local_ab/b_quad_local_global_route.odb"
frozen_b2="$root/reports/groot_normalization/quad_local_b2/b2_quad_local_global_route.odb"

mkdir -p "$physical" "$artifacts"
for path in "$placement" "$numeric" "$targeted_audit" "$authorization" "$place_odb" "$place_sdc" "$tcl" "$parser" "$strict_gate" "$snapshot_tool" "$compare_tool" "$runner" \
  "$frozen_a" "$frozen_b" "$frozen_b2"; do
  test -s "$path"
done
python3 - "$placement" "$authorization" "$place_odb" "$place_sdc" "$runner" "$tcl" "$parser" "$strict_gate" "$snapshot_tool" "$compare_tool" "$targeted_audit" "$numeric" <<'PY'
import hashlib, json, pathlib, sys

def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

placement = json.load(open(sys.argv[1], encoding="utf-8"))
authorization = json.load(open(sys.argv[2], encoding="utf-8"))
targeted_audit = json.load(open(sys.argv[11], encoding="utf-8"))
numeric = json.load(open(sys.argv[12], encoding="utf-8"))
if placement.get("status") != "PASS" or placement.get("placement_legality_and_fence_audit") != "PASS":
    raise SystemExit("B23 placement and independent audit are not PASS")
if "B9_TARGETED_PLACEMENT_REOPEN_AUDIT" not in placement.get("authorizes", []):
    raise SystemExit("sealed B9 placement does not authorize numeric/reopen validation")
if numeric.get("status") != "PASS" or numeric.get("authorizes") != ["B9_TARGETED_PLACEMENT_REOPEN_AUDIT"]:
    raise SystemExit("sealed B9 placement numeric analysis is not PASS")
if authorization.get("decision") != "PASS" or "B23_SINGLE_GLOBAL_ROUTE" not in authorization.get("authorizes", []):
    raise SystemExit("fresh B23 global-route authorization is not PASS")
if targeted_audit.get("status") != "PASS" or "B9_GLOBAL_ROUTE_AUTHORIZATION" not in targeted_audit.get("authorizes", []):
    raise SystemExit("sealed B9 targeted placement reopen audit is not PASS")
for key, text in (("b9_place_odb", sys.argv[3]), ("b9_place_sdc", sys.argv[4])):
    path = pathlib.Path(text)
    if sha(path) != placement["outputs"][key]["sha256"]:
        raise SystemExit(f"sealed B9 placement artifact hash mismatch: {key}")
for key, text in (
    ("route_runner", sys.argv[5]),
    ("route_tcl", sys.argv[6]),
    ("direct_numeric_parser", sys.argv[7]),
    ("strict_phase6_gate", sys.argv[8]),
    ("silence_snapshot_tool", sys.argv[9]),
    ("silence_compare_tool", sys.argv[10]),
):
    path = pathlib.Path(text)
    if sha(path) != authorization["inputs"][key]["sha256"]:
        raise SystemExit(f"B23 route authorization hash mismatch: {key}")
targeted_path = pathlib.Path(sys.argv[11])
if sha(targeted_path) != authorization["inputs"]["targeted_placement_reopen_audit"]["sha256"]:
    raise SystemExit("B23 route authorization hash mismatch: targeted placement reopen audit")
numeric_path = pathlib.Path(sys.argv[12])
if sha(numeric_path) != authorization["inputs"]["placement_numeric_analysis"]["sha256"]:
    raise SystemExit("B23 route authorization hash mismatch: placement numeric analysis")
print("WBQ_B23_SINGLE_GLOBAL_ROUTE_AUTHORIZATION PASS")
PY

# Any one of these files proves that B23 consumed its sole route allowance.
for path in "$attempt" "$manifest" "$log" "$guide" "$congestion" "$routed_odb" "$routed_sdc" \
  "$analysis_json" "$analysis_md"; do
  if [[ -e "$path" ]]; then
    echo "B23 global route has already been attempted; refusing duplicate ($path)" >&2
    exit 4
  fi
done
if pgrep -x openroad >/dev/null; then
  echo "an OpenROAD process already exists; refusing concurrent B23 global route" >&2
  pgrep -a -x openroad >&2 || true
  exit 3
fi
free_kib="$(df -Pk "$artifacts" | awk 'NR==2 {print $4}')"
available_kib="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
if (( free_kib < 20 * 1024 * 1024 )); then
  echo "less than 20 GiB free in B23 artifact storage" >&2
  exit 5
fi
if (( available_kib < 32 * 1024 * 1024 )); then
  echo "less than 32 GiB MemAvailable for B23 global route" >&2
  exit 6
fi

frozen_a_before="$(sha256sum "$frozen_a" | awk '{print $1}')"
frozen_b_before="$(sha256sum "$frozen_b" | awk '{print $1}')"
frozen_b2_before="$(sha256sum "$frozen_b2" | awk '{print $1}')"
[[ "$frozen_a_before" == 964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad ]]
[[ "$frozen_b_before" == ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235 ]]
[[ "$frozen_b2_before" == 2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d ]]

start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
placement_sha="$(sha256sum "$placement" | awk '{print $1}')"
authorization_sha="$(sha256sum "$authorization" | awk '{print $1}')"
targeted_audit_sha="$(sha256sum "$targeted_audit" | awk '{print $1}')"
place_odb_sha="$(sha256sum "$place_odb" | awk '{print $1}')"
place_sdc_sha="$(sha256sum "$place_sdc" | awk '{print $1}')"
runner_sha="$(sha256sum "$runner" | awk '{print $1}')"
tcl_sha="$(sha256sum "$tcl" | awk '{print $1}')"
parser_sha="$(sha256sum "$parser" | awk '{print $1}')"
strict_gate_sha="$(sha256sum "$strict_gate" | awk '{print $1}')"
snapshot_tool_sha="$(sha256sum "$snapshot_tool" | awk '{print $1}')"
compare_tool_sha="$(sha256sum "$compare_tool" | awk '{print $1}')"
python3 - "$attempt" "$start" "$runner_service" "$$" "$placement" "$placement_sha" "$targeted_audit" "$targeted_audit_sha" "$authorization" "$authorization_sha" \
  "$place_odb" "$place_odb_sha" "$place_sdc" "$place_sdc_sha" "$runner" "$runner_sha" "$tcl" "$tcl_sha" \
  "$parser" "$parser_sha" "$strict_gate" "$strict_gate_sha" "$snapshot_tool" "$snapshot_tool_sha" "$compare_tool" "$compare_tool_sha" "$free_kib" "$available_kib" \
  "$frozen_a_before" "$frozen_b_before" "$frozen_b2_before" <<'PY'
import json, sys

(path, start, service, wrapper_pid, placement, placement_sha, targeted_audit, targeted_audit_sha, authorization, authorization_sha,
 odb, odb_sha, sdc, sdc_sha, runner, runner_sha, tcl, tcl_sha, parser, parser_sha,
 strict_gate, strict_gate_sha, snapshot_tool, snapshot_tool_sha, compare_tool, compare_tool_sha,
 free_kib, available_kib, frozen_a, frozen_b, frozen_b2) = sys.argv[1:]
payload = {
    "schema_version": 2,
    "variant": "B23",
    "stage": "single_global_route",
    "status": "STARTED",
    "invocation_count": 1,
    "global_route_invocations": 1,
    "cugr_congestion_iterations": 1,
    "start_utc": start,
    "command": "openroad -exit -no_init -threads 1 -no_splash wbq_quad_local_b23_global_route.tcl",
    "service": service,
    "wrapper_pid": int(wrapper_pid),
    "launcher_pid": None,
    "compute_pid": None,
    "log": None,
    "expected_artifacts": [
        "b23_quad_local.route_guide", "b23_quad_local.congestion.rpt",
        "b23_quad_local_global_route.odb", "b23_quad_local_global_route.sdc",
    ],
    "resources_at_start": {"artifact_free_kib": int(free_kib), "mem_available_kib": int(available_kib)},
    "inputs": {
        "placement_manifest": {"path": placement, "sha256": placement_sha},
        "targeted_placement_reopen_audit": {"path": targeted_audit, "sha256": targeted_audit_sha},
        "route_authorization": {"path": authorization, "sha256": authorization_sha},
        "b9_place_odb": {"path": odb, "sha256": odb_sha},
        "b9_place_sdc": {"path": sdc, "sha256": sdc_sha},
        "route_runner": {"path": runner, "sha256": runner_sha},
        "route_tcl": {"path": tcl, "sha256": tcl_sha},
        "direct_numeric_parser": {"path": parser, "sha256": parser_sha},
        "strict_phase6_gate": {"path": strict_gate, "sha256": strict_gate_sha},
        "silence_snapshot_tool": {"path": snapshot_tool, "sha256": snapshot_tool_sha},
        "silence_compare_tool": {"path": compare_tool, "sha256": compare_tool_sha},
    },
    "protected_hashes_before": {"frozen_A": frozen_a, "B": frozen_b, "B2": frozen_b2},
    "artifact_storage": "B23-only tmpfs; compact hashes and reports persist in the repository",
}
with open(path, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2)
    stream.write("\n")
PY

compute_pid=""
launcher_pid=""
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
  echo "WBQ_B23_GLOBAL_ROUTE_SIGNAL=$termination_signal" >> "$log"
  refresh_compute_pid
  if [[ -n "$compute_pid" ]] && kill -0 "$compute_pid" 2>/dev/null; then
    kill -TERM "$compute_pid"
  fi
}

write_fail_closed_manifest() {
  local exit_code="$1"
  [[ -e "$manifest" ]] && return
  python3 - "$manifest" "$attempt" "$log" "$guide" "$congestion" "$routed_odb" "$routed_sdc" \
    "$analysis_json" "$exit_code" "$termination_signal" <<'PY'
import hashlib, json, pathlib, sys

(manifest, attempt, log, guide, congestion, odb, sdc, analysis, exit_code, signal) = sys.argv[1:]
def item(text):
    path = pathlib.Path(text)
    if not path.exists():
        return {"path": str(path), "exists": False, "bytes": 0, "sha256": None}
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return {"path": str(path), "exists": True, "bytes": path.stat().st_size, "sha256": digest.hexdigest()}

attempt_data = json.load(open(attempt, encoding="utf-8"))
payload = {
    "schema_version": 2,
    "variant": "B23",
    "stage": "single_global_route",
    "status": "FAIL",
    "failure_class": "interrupted" if signal else "tool_error",
    "invocation_count": 1,
    "cugr_congestion_iterations": 1,
    "start_utc": attempt_data["start_utc"],
    "end_utc": __import__("datetime").datetime.now(__import__("datetime").timezone.utc).isoformat(),
    "exit_code": int(exit_code),
    "termination_signal": signal or None,
    "service": attempt_data.get("service"),
    "wrapper_pid": attempt_data.get("wrapper_pid"),
    "launcher_pid": attempt_data.get("launcher_pid"),
    "compute_pid": attempt_data.get("compute_pid"),
    "inputs": attempt_data.get("inputs", {}),
    "outputs": {
        "log": item(log), "guide": item(guide), "congestion_report": item(congestion),
        "routed_odb": item(odb), "routed_sdc": item(sdc), "direct_analysis": item(analysis),
    },
    "protected_hashes_before": attempt_data.get("protected_hashes_before", {}),
    "protected_hashes_after": None,
    "protected_artifacts_preserved": None,
    "authorizes": [],
    "next_stage": None,
}
with open(manifest, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2)
    stream.write("\n")
PY
}

on_exit() {
  local exit_code="$?"
  if (( finalized == 0 )); then
    refresh_compute_pid
    if [[ -n "$compute_pid" ]] && kill -0 "$compute_pid" 2>/dev/null; then
      kill -TERM "$compute_pid" 2>/dev/null || true
    fi
    write_fail_closed_manifest "$exit_code" || true
  fi
}

trap 'on_signal INT' INT
trap 'on_signal TERM' TERM
trap 'on_exit' EXIT

{
  echo "WBQ_B23_GLOBAL_ROUTE_START_UTC=$start"
  echo "WBQ_B23_GLOBAL_ROUTE_INVOCATION_COUNT=1"
  echo "WBQ_B23_CUGR_CONGESTION_ITERATIONS=1"
  echo "WBQ_B23_GLOBAL_ROUTE_SERVICE=$runner_service"
  echo "WBQ_B23_GLOBAL_ROUTE_WRAPPER_PID=$$"
  echo "WBQ_B23_GLOBAL_ROUTE_PLACE_ODB_SHA256=$place_odb_sha"
  echo "WBQ_B23_GLOBAL_ROUTE_PLACE_SDC_SHA256=$place_sdc_sha"
} > "$log"
python3 - "$attempt" "$log" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["log"] = sys.argv[2]
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

export WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd"
export WBQ_B23_PLACE_ODB="$place_odb"
export WBQ_B23_PLACE_SDC="$place_sdc"
export WBQ_B23_ROUTE_OUTPUT_ROOT="$artifacts"
export WBQ_B23_CUGR_CONGESTION_ITERATIONS=1
/usr/bin/time -v "$openroad_exe" -exit -no_init -threads 1 -no_splash "$tcl" >> "$log" 2>&1 &
launcher_pid="$!"
echo "WBQ_B23_GLOBAL_ROUTE_LAUNCHER_PID=$launcher_pid" >> "$log"
python3 - "$attempt" "$launcher_pid" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["launcher_pid"] = int(sys.argv[2])
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
for _ in $(seq 1 120); do
  refresh_compute_pid
  if [[ -n "$compute_pid" ]]; then
    echo "WBQ_B23_GLOBAL_ROUTE_COMPUTE_PID=$compute_pid" >> "$log"
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
end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "WBQ_B23_GLOBAL_ROUTE_EXIT_CODE=$route_rc" >> "$log"
echo "WBQ_B23_GLOBAL_ROUTE_END_UTC=$end" >> "$log"

analysis_rc=1
if [[ "$route_rc" -eq 0 ]] && grep -q "WBQ_B23_SINGLE_GLOBAL_ROUTE PASS" "$log" \
    && [[ -s "$guide" && -e "$congestion" && -s "$routed_odb" && -s "$routed_sdc" ]]; then
  set +e
  python3 "$parser" \
    --variant B23 --pass-token "WBQ_B23_SINGLE_GLOBAL_ROUTE PASS" --cugr-iterations 1 \
    --report "$congestion" --log "$log" --guide "$guide" --odb "$routed_odb" --sdc "$routed_sdc" \
    --invocation "$attempt" --output-json "$analysis_json" --output-md "$analysis_md" \
    --max-hotspots-in-output 500 --max-windows-in-output 0
  analysis_rc=$?
  set -e
fi

frozen_a_after="$(sha256sum "$frozen_a" | awk '{print $1}')"
frozen_b_after="$(sha256sum "$frozen_b" | awk '{print $1}')"
frozen_b2_after="$(sha256sum "$frozen_b2" | awk '{print $1}')"
python3 - "$manifest" "$attempt" "$end" "$route_rc" "$analysis_rc" "$termination_signal" "$log" "$guide" \
  "$congestion" "$routed_odb" "$routed_sdc" "$analysis_json" "$analysis_md" \
  "$frozen_a_after" "$frozen_b_after" "$frozen_b2_after" <<'PY'
import hashlib, json, pathlib, sys

(manifest, attempt, end, route_rc, analysis_rc, signal, log, guide, congestion, odb, sdc,
 analysis, analysis_md, frozen_a, frozen_b, frozen_b2) = sys.argv[1:]
def item(text):
    path = pathlib.Path(text)
    digest = None
    if path.exists():
        value = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
                value.update(chunk)
        digest = value.hexdigest()
    return {"path": str(path), "exists": path.exists(), "bytes": path.stat().st_size if path.exists() else 0, "sha256": digest}

attempt_data = json.load(open(attempt, encoding="utf-8"))
after = {"frozen_A": frozen_a, "B": frozen_b, "B2": frozen_b2}
preserved = after == attempt_data["protected_hashes_before"]
passed = (int(route_rc) == 0 and int(analysis_rc) == 0 and preserved and not signal
          and attempt_data.get("compute_pid") is not None)
payload = {
    "schema_version": 2,
    "variant": "B23",
    "stage": "single_global_route",
    "status": "PASS" if passed else "FAIL",
    "failure_class": None if passed else ("interrupted" if signal else "tool_error"),
    "invocation_count": 1,
    "cugr_congestion_iterations": 1,
    "start_utc": attempt_data["start_utc"],
    "end_utc": end,
    "exit_code": int(route_rc),
    "direct_parser_exit_code": int(analysis_rc),
    "termination_signal": signal or None,
    "service": attempt_data.get("service"),
    "wrapper_pid": attempt_data.get("wrapper_pid"),
    "launcher_pid": attempt_data.get("launcher_pid"),
    "compute_pid": attempt_data.get("compute_pid"),
    "command": attempt_data["command"],
    "inputs": attempt_data["inputs"],
    "protected_hashes_before": attempt_data["protected_hashes_before"],
    "protected_hashes_after": after,
    "protected_artifacts_preserved": preserved,
    "outputs": {
        "log": item(log), "guide": item(guide), "congestion_report": item(congestion),
        "routed_odb": item(odb), "routed_sdc": item(sdc),
        "direct_analysis": item(analysis), "direct_analysis_markdown": item(analysis_md),
    },
    "authorizes": ["B23_STRICT_PHASE6_EVALUATION"] if passed else [],
    "next_stage": "B23_STRICT_PHASE6_EVALUATION" if passed else None,
}
with open(manifest, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2)
    stream.write("\n")
PY

finalized=1
trap - EXIT INT TERM
test "$route_rc" -eq 0
test "$analysis_rc" -eq 0
grep -q '"status": "PASS"' "$manifest"
echo "WBQ_B23_SINGLE_GLOBAL_ROUTE PASS report=$manifest"
