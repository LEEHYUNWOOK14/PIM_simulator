#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"

report="$root/reports/groot_normalization/quad_local_b7"
evidence="$report/phase6"
artifact_root="${WBQ_B7_ARTIFACT_ROOT:-/dev/shm/wbq_b7_phase6_10/quad_local_b7}"
phase_root="${WBQ_B7_PHASE6_ROOT:-/dev/shm/wbq_b7_phase6_10/phase6_cts}"
work_home="${WBQ_B7_ORFS_WORK_HOME:-/dev/shm/wbq_b7_phase6_10/orfs}"
orfs_result="$work_home/results/sky130hd/normalization_hbm_quad_local_b7/base"
config="$root/flow/designs/sky130hd/normalization_hbm_quad_local_b7/config.mk"
gate="$report/phase6_decision_gate.json"
authorization="$evidence/b7_phase6_cts_authorization.json"
placement="$report/physical/b7_placement_execution_report.json"
place_odb="$artifact_root/b7_place.odb"
place_sdc="$artifact_root/b7_place.sdc"
cts_odb="$phase_root/b7_phase6_cts.odb"
cts_sdc="$phase_root/b7_phase6_cts.sdc"
log="$evidence/b7_phase6_cts.log"
audit_log="$evidence/b7_phase6_cts_audit.log"
preflight="$evidence/b7_phase6_cts_preflight.json"
attempt="$evidence/b7_phase6_cts_invocation.json"
manifest="$evidence/b7_phase6_cts_execution_report.json"
runner="$root/verification/groot_normalization/run_wbq_b7_phase6_cts.sh"
audit_tcl="$root/verification/groot_normalization/audit_wbq_b7_phase6_cts.tcl"
snapshot_tool="$root/tools/capture_openroad_stage_snapshot.py"
compare_tool="$root/tools/compare_openroad_stage_snapshots.py"
runner_service="${WBQ_RUNNER_SERVICE:-wbq-b7-phase6-cts.service}"

mkdir -p "$evidence" "$phase_root" "$orfs_result"
for path in "$config" "$gate" "$authorization" "$placement" "$place_odb" "$place_sdc" \
  "$runner" "$audit_tcl" "$snapshot_tool" "$compare_tool"; do
  test -s "$path"
done
python3 - "$gate" "$authorization" "$placement" "$place_odb" "$place_sdc" "$config" "$runner" "$audit_tcl" "$snapshot_tool" "$compare_tool" <<'PY'
import hashlib, json, pathlib, sys

def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

gate = json.load(open(sys.argv[1], encoding="utf-8"))
authorization = json.load(open(sys.argv[2], encoding="utf-8"))
placement = json.load(open(sys.argv[3], encoding="utf-8"))
if gate.get("decision") != "PASS" or "B7_PHASE6_CTS" not in gate.get("authorizes", []):
    raise SystemExit("strict Phase 6 gate does not authorize B7 CTS")
if authorization.get("decision") != "PASS" or "B7_PHASE6_CTS_COMPUTE" not in authorization.get("authorizes", []):
    raise SystemExit("fresh B7 CTS authorization is not PASS")
if placement.get("status") != "PASS":
    raise SystemExit("B7 placement is not PASS")
for key, text in (("b7_place_odb", sys.argv[4]), ("b7_place_sdc", sys.argv[5])):
    path = pathlib.Path(text)
    if sha(path) != placement["outputs"][key]["sha256"]:
        raise SystemExit(f"B7 CTS placement input hash mismatch: {key}")
for key, text in (
    ("config", sys.argv[6]), ("runner", sys.argv[7]), ("audit_tcl", sys.argv[8]),
    ("silence_snapshot_tool", sys.argv[9]), ("silence_compare_tool", sys.argv[10]),
):
    path = pathlib.Path(text)
    if sha(path) != authorization["inputs"][key]["sha256"]:
        raise SystemExit(f"B7 CTS authorization hash mismatch: {key}")
print("WBQ_B7_PHASE6_CTS_INPUT_GATE PASS")
PY

for path in "$preflight" "$attempt" "$manifest" "$log" "$audit_log" "$cts_odb" "$cts_sdc" \
  "$orfs_result/4_1_cts.odb" "$orfs_result/4_cts.odb" "$orfs_result/4_cts.sdc"; do
  if [[ -e "$path" ]]; then
    echo "existing B7 Phase 6 CTS artifact prevents a fresh invocation: $path" >&2
    exit 4
  fi
done
if pgrep -x openroad >/dev/null; then
  echo "an OpenROAD process already exists; refusing concurrent B7 Phase 6 CTS" >&2
  pgrep -a -x openroad >&2 || true
  exit 3
fi
free_kib="$(df -Pk "$phase_root" | awk 'NR==2 {print $4}')"
available_kib="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
if (( free_kib < 16 * 1024 * 1024 )); then
  echo "less than 16 GiB free in B7 Phase 6 storage" >&2
  exit 5
fi
if (( available_kib < 32 * 1024 * 1024 )); then
  echo "less than 32 GiB MemAvailable for B7 CTS" >&2
  exit 6
fi

start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
gate_sha="$(sha256sum "$gate" | awk '{print $1}')"
authorization_sha="$(sha256sum "$authorization" | awk '{print $1}')"
placement_sha="$(sha256sum "$placement" | awk '{print $1}')"
place_odb_sha="$(sha256sum "$place_odb" | awk '{print $1}')"
place_sdc_sha="$(sha256sum "$place_sdc" | awk '{print $1}')"
config_sha="$(sha256sum "$config" | awk '{print $1}')"
runner_sha="$(sha256sum "$runner" | awk '{print $1}')"
audit_tcl_sha="$(sha256sum "$audit_tcl" | awk '{print $1}')"
snapshot_tool_sha="$(sha256sum "$snapshot_tool" | awk '{print $1}')"
compare_tool_sha="$(sha256sum "$compare_tool" | awk '{print $1}')"
python3 - "$preflight" "$attempt" "$start" "$runner_service" "$$" "$gate" "$gate_sha" "$authorization" "$authorization_sha" \
  "$placement" "$placement_sha" "$place_odb" "$place_odb_sha" "$place_sdc" "$place_sdc_sha" "$config" "$config_sha" \
  "$runner" "$runner_sha" "$audit_tcl" "$audit_tcl_sha" "$snapshot_tool" "$snapshot_tool_sha" "$compare_tool" "$compare_tool_sha" \
  "$free_kib" "$available_kib" <<'PY'
import json, sys

(preflight, attempt, start, service, wrapper_pid, gate, gate_sha, authorization, authorization_sha,
 placement, placement_sha, odb, odb_sha, sdc, sdc_sha, config, config_sha, runner, runner_sha,
 audit_tcl, audit_tcl_sha, snapshot_tool, snapshot_tool_sha, compare_tool, compare_tool_sha,
 free_kib, available_kib) = sys.argv[1:]
payload = {
    "schema_version": 2,
    "phase": 6,
    "variant": "B7_PHASE6_CTS",
    "status": "STARTED",
    "generated_at_utc": start,
    "service": service,
    "wrapper_pid": int(wrapper_pid),
    "launcher_pid": None,
    "compute_pid": None,
    "audit_compute_pid": None,
    "command": "make -C ORFS WORK_HOME=<B7 tmpfs> DESIGN_CONFIG=<B7 config> -j1 do-4_1_cts",
    "openroad_compute_invocation_limit": 1,
    "audit_invocation_limit": 1,
    "policy": "repository ORFS TritonCTS with sink clustering and repair_clock_nets",
    "resources": {"free_kib": int(free_kib), "mem_available_kib": int(available_kib)},
    "inputs": {
        "strict_phase6_gate": {"path": gate, "sha256": gate_sha},
        "cts_authorization": {"path": authorization, "sha256": authorization_sha},
        "placement_report": {"path": placement, "sha256": placement_sha},
        "placed_odb": {"path": odb, "sha256": odb_sha},
        "placed_sdc": {"path": sdc, "sha256": sdc_sha},
        "config": {"path": config, "sha256": config_sha},
        "runner": {"path": runner, "sha256": runner_sha},
        "audit_tcl": {"path": audit_tcl, "sha256": audit_tcl_sha},
        "silence_snapshot_tool": {"path": snapshot_tool, "sha256": snapshot_tool_sha},
        "silence_compare_tool": {"path": compare_tool, "sha256": compare_tool_sha},
    },
    "expected_artifacts": ["b7_phase6_cts.odb", "b7_phase6_cts.sdc"],
    "authorizes": ["B7_PHASE6_CTS_COMPUTE"],
    "next_stage": "B7_PHASE6_CTS_COMPUTE",
}
with open(preflight, "x", encoding="utf-8") as stream:
    json.dump({**payload, "status": "PASS"}, stream, indent=2)
    stream.write("\n")
with open(attempt, "x", encoding="utf-8") as stream:
    json.dump({**payload, "invocation_count": 1}, stream, indent=2)
    stream.write("\n")
PY

compute_pid=""
audit_compute_pid=""
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
  echo "WBQ_B7_PHASE6_CTS_SIGNAL=$termination_signal" >> "$log"
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
  python3 - "$manifest" "$attempt" "$log" "$audit_log" "$cts_odb" "$cts_sdc" "$exit_code" "$termination_signal" <<'PY'
import hashlib, json, pathlib, sys

(manifest, attempt, log, audit_log, odb, sdc, exit_code, signal) = sys.argv[1:]
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
    "schema_version": 2, "phase": 6, "variant": "B7_PHASE6_CTS", "status": "FAIL",
    "failure_class": "interrupted" if signal else "tool_error", "invocation_count": 1,
    "start_utc": attempt_data["generated_at_utc"],
    "end_utc": __import__("datetime").datetime.now(__import__("datetime").timezone.utc).isoformat(),
    "exit_code": int(exit_code), "termination_signal": signal or None,
    "service": attempt_data.get("service"), "wrapper_pid": attempt_data.get("wrapper_pid"),
    "launcher_pid": attempt_data.get("launcher_pid"), "compute_pid": attempt_data.get("compute_pid"),
    "audit_compute_pid": attempt_data.get("audit_compute_pid"), "inputs": attempt_data.get("inputs", {}),
    "artifacts": {"cts_odb": item(odb), "cts_sdc": item(sdc), "run_log": item(log), "audit_log": item(audit_log)},
    "authorizes": [], "next_stage": None,
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

ln -s "$place_odb" "$orfs_result/3_place.odb"
ln -s "$place_sdc" "$orfs_result/3_place.sdc"
{
  echo "WBQ_B7_PHASE6_CTS_START_UTC=$start"
  echo "WBQ_B7_PHASE6_CTS_INVOCATION_COUNT=1"
  echo "WBQ_B7_PHASE6_CTS_SERVICE=$runner_service"
  echo "WBQ_B7_PHASE6_CTS_WRAPPER_PID=$$"
  echo "WBQ_B7_PHASE6_CTS_GATE_SHA256=$gate_sha"
  echo "WBQ_B7_PHASE6_CTS_AUTHORIZATION_SHA256=$authorization_sha"
  echo "WBQ_B7_PHASE6_CTS_PLACEMENT_SHA256=$placement_sha"
  echo "WBQ_B7_PHASE6_CTS_PLACE_ODB_SHA256=$place_odb_sha"
  echo "WBQ_B7_PHASE6_CTS_PLACE_SDC_SHA256=$place_sdc_sha"
  echo "WBQ_B7_PHASE6_CTS_POLICY=ORFS_TRITONCTS_REPAIR_CLOCK_NETS"
  echo "WBQ_B7_PHASE6_CTS_SIGNAL_LAYERS=met1-met5"
  echo "WBQ_B7_PHASE6_CTS_CLOCK_LAYERS=met2-met5"
} > "$log"

/usr/bin/time -v make -C "$orfs_flow" \
  WORK_HOME="$work_home" DESIGN_CONFIG="$config" STOB_REPO_ROOT="$root" \
  YOSYS_EXE="$yosys_exe" OPENROAD_EXE="$openroad_exe" \
  NUM_CORES="${NUM_CORES:-16}" SKIP_REPORT_METRICS=1 \
  MIN_ROUTING_LAYER=met1 MIN_CLK_ROUTING_LAYER=met2 MAX_ROUTING_LAYER=met5 \
  -j1 do-4_1_cts >> "$log" 2>&1 &
launcher_pid="$!"
python3 - "$attempt" "$launcher_pid" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1]); data = json.loads(path.read_text(encoding="utf-8"))
data["launcher_pid"] = int(sys.argv[2]); path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

for _ in $(seq 1 120); do
  refresh_compute_pid
  if [[ -n "$compute_pid" ]]; then
    echo "WBQ_B7_PHASE6_CTS_COMPUTE_PID=$compute_pid" >> "$log"
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
rc=$?
set -e
compute_pid=""
echo "WBQ_B7_PHASE6_CTS_EXIT_CODE=$rc" >> "$log"
if [[ "$rc" -eq 0 && -s "$orfs_result/4_1_cts.odb" && -s "$orfs_result/4_cts.sdc" ]]; then
  mv "$orfs_result/4_1_cts.odb" "$cts_odb"
  mv "$orfs_result/4_cts.sdc" "$cts_sdc"
fi

audit_rc=1
if [[ "$rc" -eq 0 && -s "$cts_odb" && -s "$cts_sdc" ]]; then
  {
    echo "WBQ_B7_PHASE6_CTS_AUDIT_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "WBQ_B7_PHASE6_CTS_AUDIT_ODB_SHA256=$(sha256sum "$cts_odb" | awk '{print $1}')"
    echo "WBQ_B7_PHASE6_CTS_AUDIT_SDC_SHA256=$(sha256sum "$cts_sdc" | awk '{print $1}')"
  } > "$audit_log"
  WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd" WBQ_CTS_ODB="$cts_odb" WBQ_CTS_SDC="$cts_sdc" \
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
  echo "WBQ_B7_PHASE6_CTS_AUDIT_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$audit_log"
fi
end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "WBQ_B7_PHASE6_CTS_END_UTC=$end" >> "$log"

python3 - "$manifest" "$attempt" "$end" "$rc" "$audit_rc" "$termination_signal" "$log" "$audit_log" "$cts_odb" "$cts_sdc" <<'PY'
import hashlib, json, pathlib, re, sys

(manifest, attempt, end, rc, audit_rc, signal, log, audit_log, odb, sdc) = sys.argv[1:]
def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
def item(text):
    path = pathlib.Path(text)
    return {"path": str(path), "exists": path.exists(), "bytes": path.stat().st_size if path.exists() else 0,
            "sha256": sha(path) if path.exists() else None}
run_text = pathlib.Path(log).read_text(encoding="utf-8", errors="replace")
audit_text = pathlib.Path(audit_log).read_text(encoding="utf-8", errors="replace") if pathlib.Path(audit_log).exists() else ""
one = lambda pattern, text: (re.findall(pattern, text, flags=re.MULTILINE) or [None])[-1]
buffers = one(r"\[INFO CTS-0018\]\s+Created (\d+) clock buffers", run_text)
nets = one(r"\[INFO CTS-0015\]\s+Created (\d+) clock nets", run_text)
sinks = one(r"\[INFO CTS-0010\]\s+Clock net .* has (\d+) sinks", run_text)
clock_nets = one(r"^WBQ_B7_PHASE6_CTS_AUDIT_CLOCK_NET_COUNT (\d+)$", audit_text)
attempt_data = json.load(open(attempt, encoding="utf-8"))
passed = (int(rc) == 0 and int(audit_rc) == 0 and not signal
          and "WBQ_B7_PHASE6_CTS_AUDIT PASS" in audit_text
          and attempt_data.get("compute_pid") is not None and attempt_data.get("audit_compute_pid") is not None
          and all(value is not None and int(value) > 0 for value in (buffers, nets, sinks, clock_nets)))
payload = {
    "schema_version": 2, "phase": 6, "variant": "B7_PHASE6_CTS",
    "status": "PASS" if passed else "FAIL", "failure_class": None if passed else ("interrupted" if signal else "tool_error"),
    "invocation_count": 1, "audit_invocation_count": 1 if pathlib.Path(audit_log).exists() else 0,
    "start_utc": attempt_data["generated_at_utc"], "end_utc": end,
    "exit_code": int(rc), "audit_exit_code": int(audit_rc), "termination_signal": signal or None,
    "service": attempt_data.get("service"), "wrapper_pid": attempt_data.get("wrapper_pid"),
    "launcher_pid": attempt_data.get("launcher_pid"), "compute_pid": attempt_data.get("compute_pid"),
    "audit_compute_pid": attempt_data.get("audit_compute_pid"), "policy": attempt_data["policy"],
    "inputs": attempt_data["inputs"],
    "metrics": {
        "initial_clock_sinks": int(sinks) if sinks else None,
        "created_clock_buffers": int(buffers) if buffers else None,
        "created_clock_nets": int(nets) if nets else None,
        "database_clock_nets": int(clock_nets) if clock_nets else None,
        "placement_violations": 0 if "AUDIT_VIOLATIONS {}" in audit_text else None,
    },
    "artifacts": {"cts_odb": item(odb), "cts_sdc": item(sdc), "run_log": item(log), "audit_log": item(audit_log)},
    "authorizes": ["B7_PHASE6_POST_CTS_GLOBAL_ROUTE_AUTHORIZATION"] if passed else [],
    "next_stage": "B7_PHASE6_POST_CTS_GLOBAL_ROUTE_AUTHORIZATION" if passed else None,
    "claim_boundary": "CTS-completed placed research checkpoint; not manufacturing signoff.",
}
with open(manifest, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2)
    stream.write("\n")
PY

finalized=1
trap - EXIT INT TERM
test "$rc" -eq 0
test "$audit_rc" -eq 0
grep -q '"status": "PASS"' "$manifest"
echo "WBQ_B7_PHASE6_CTS PASS report=$manifest"
