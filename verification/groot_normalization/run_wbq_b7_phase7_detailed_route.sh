#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"

b7_report="$root/reports/groot_normalization/quad_local_b7"
phase6="$b7_report/phase6"
evidence="$b7_report/phase7"
input_root="${WBQ_B7_PHASE6_ROUTE_ROOT:-/dev/shm/wbq_b7_phase6_10/phase6_post_cts}"
output_root="${WBQ_B7_PHASE7_ROOT:-/dev/shm/wbq_b7_phase6_10/phase7}"
input_manifest="$phase6/b7_phase6_post_cts_global_route_execution_report.json"
authorization="$evidence/b7_phase7_detailed_route_authorization.json"
input_odb="$input_root/b7_phase6_post_cts_global_route.odb"
input_sdc="$input_root/b7_phase6_post_cts_global_route.sdc"
log="$evidence/b7_phase7_detailed_route.log"
audit_log="$evidence/b7_phase7_detailed_route_audit.log"
preflight="$evidence/b7_phase7_preflight.json"
attempt="$evidence/b7_phase7_detailed_route_invocation.json"
manifest="$evidence/b7_phase7_detailed_route_execution_report.json"
odb="$output_root/b7_phase7_detailed_route.odb"
sdc="$output_root/b7_phase7_detailed_route.sdc"
def="$output_root/b7_phase7_detailed_route.def"
netlist="$output_root/b7_phase7_detailed_route.v"
drc="$output_root/b7_phase7_detailed_route.drc.rpt"
antenna="$output_root/b7_phase7_antenna.rpt"
maze="$output_root/b7_phase7_detailed_route.maze.log"
timing="$output_root/b7_phase7_timing.rpt"
max_slew="$output_root/b7_phase7_max_slew.rpt"
max_capacitance="$output_root/b7_phase7_max_capacitance.rpt"
max_fanout="$output_root/b7_phase7_max_fanout.rpt"
tcl="$root/verification/groot_normalization/wbq_b7_phase7_detailed_route.tcl"
audit_tcl="$root/verification/groot_normalization/audit_wbq_b7_phase7_detailed_route.tcl"
runner="$root/verification/groot_normalization/run_wbq_b7_phase7_detailed_route.sh"
snapshot_tool="$root/tools/capture_openroad_stage_snapshot.py"
compare_tool="$root/tools/compare_openroad_stage_snapshots.py"
runner_service="${WBQ_RUNNER_SERVICE:-wbq-b7-phase7-detailed-route.service}"

mkdir -p "$evidence" "$output_root"
for path in "$input_manifest" "$authorization" "$input_odb" "$input_sdc" "$runner" "$tcl" \
  "$audit_tcl" "$snapshot_tool" "$compare_tool"; do test -s "$path"; done
python3 - "$input_manifest" "$authorization" "$input_odb" "$input_sdc" "$runner" "$tcl" \
  "$audit_tcl" "$snapshot_tool" "$compare_tool" "$output_root" <<'PY'
import hashlib, json, pathlib, shutil, sys
def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
authorization = json.load(open(sys.argv[2], encoding="utf-8"))
if manifest.get("status") != "PASS" or "B7_PHASE7_DETAILED_ROUTE_AUTHORIZATION" not in manifest.get("authorizes", []):
    raise SystemExit("Phase 6 does not authorize B7 Phase 7 authorization")
if authorization.get("decision") != "PASS" or authorization.get("authorizes") != ["B7_PHASE7_DETAILED_ROUTE_COMPUTE"]:
    raise SystemExit("fresh B7 Phase 7 compute authorization is not PASS")
for key, text in (("routed_odb", sys.argv[3]), ("routed_sdc", sys.argv[4])):
    path = pathlib.Path(text)
    if sha(path) != manifest["artifacts"][key]["sha256"]:
        raise SystemExit(f"Phase 7 input hash mismatch: {key}")
for key, text in (("runner", sys.argv[5]), ("route_tcl", sys.argv[6]),
                  ("audit_tcl", sys.argv[7]), ("silence_snapshot_tool", sys.argv[8]),
                  ("silence_compare_tool", sys.argv[9])):
    path = pathlib.Path(text)
    if sha(path) != authorization["inputs"][key]["sha256"]:
        raise SystemExit(f"Phase 7 authorization hash mismatch: {key}")
mem_kib = int(next(line.split()[1] for line in pathlib.Path("/proc/meminfo").read_text().splitlines() if line.startswith("MemAvailable:")))
free = shutil.disk_usage(sys.argv[10]).free
if mem_kib < 32 * 1024 * 1024:
    raise SystemExit(f"Phase 7 requires 32 GiB available RAM; found {mem_kib / 1024**2:.2f} GiB")
if free < 12 * 1024**3:
    raise SystemExit(f"Phase 7 requires 12 GiB free disk; found {free / 1024**3:.2f} GiB")
print(f"WBQ_B7_PHASE7_INPUT_GATE PASS available_ram_gib={mem_kib / 1024**2:.2f} free_disk_gib={free / 1024**3:.2f}")
PY

for path in "$preflight" "$attempt" "$manifest" "$log" "$audit_log" "$odb" "$sdc" "$def" \
  "$netlist" "$drc" "$antenna" "$maze" "$timing" "$max_slew" "$max_capacitance" "$max_fanout"; do
  if [[ -e "$path" ]]; then echo "existing B7 Phase 7 artifact prevents overwrite: $path" >&2; exit 4; fi
done
if pgrep -x openroad >/dev/null; then echo "OpenROAD already exists; refusing concurrent Phase 7" >&2; exit 3; fi

manifest_sha="$(sha256sum "$input_manifest" | awk '{print $1}')"
authorization_sha="$(sha256sum "$authorization" | awk '{print $1}')"
odb_sha="$(sha256sum "$input_odb" | awk '{print $1}')"
sdc_sha="$(sha256sum "$input_sdc" | awk '{print $1}')"
runner_sha="$(sha256sum "$runner" | awk '{print $1}')"
tcl_sha="$(sha256sum "$tcl" | awk '{print $1}')"
audit_tcl_sha="$(sha256sum "$audit_tcl" | awk '{print $1}')"
snapshot_tool_sha="$(sha256sum "$snapshot_tool" | awk '{print $1}')"
compare_tool_sha="$(sha256sum "$compare_tool" | awk '{print $1}')"
start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mem_kib="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
free_kib="$(df -Pk "$output_root" | awk 'NR==2 {print $4}')"
python3 - "$preflight" "$attempt" "$start" "$runner_service" "$$" "$input_manifest" "$manifest_sha" \
  "$authorization" "$authorization_sha" "$input_odb" "$odb_sha" "$input_sdc" "$sdc_sha" \
  "$runner" "$runner_sha" "$tcl" "$tcl_sha" "$audit_tcl" "$audit_tcl_sha" \
  "$snapshot_tool" "$snapshot_tool_sha" "$compare_tool" "$compare_tool_sha" "$mem_kib" "$free_kib" <<'PY'
import json, sys
preflight, attempt, start, service, wrapper_pid, manifest, manifest_sha, authorization, authorization_sha, odb, odb_sha, sdc, sdc_sha, runner, runner_sha, tcl, tcl_sha, audit_tcl, audit_tcl_sha, snapshot, snapshot_sha, compare, compare_sha, mem_kib, free_kib = sys.argv[1:]
payload = {"schema_version": 2, "phase": 7, "variant": "B7_PHASE7_DETAILED_ROUTE",
           "status": "PASS", "generated_at_utc": start,
           "service": service, "wrapper_pid": int(wrapper_pid), "launcher_pid": None,
           "compute_pid": None, "audit_compute_pid": None,
           "command": "openroad -threads 16 wbq_b7_phase7_detailed_route.tcl",
           "droute_end_iteration": 64, "required_mem_available_gib": 32,
           "required_free_disk_gib": 12, "actual_mem_available_kib": int(mem_kib),
           "actual_free_disk_kib": int(free_kib),
           "inputs": {"phase6_manifest": {"path": manifest, "sha256": manifest_sha},
                      "phase7_authorization": {"path": authorization, "sha256": authorization_sha},
                      "routed_odb": {"path": odb, "sha256": odb_sha},
                      "routed_sdc": {"path": sdc, "sha256": sdc_sha},
                      "runner": {"path": runner, "sha256": runner_sha},
                      "route_tcl": {"path": tcl, "sha256": tcl_sha},
                      "audit_tcl": {"path": audit_tcl, "sha256": audit_tcl_sha},
                      "silence_snapshot_tool": {"path": snapshot, "sha256": snapshot_sha},
                      "silence_compare_tool": {"path": compare, "sha256": compare_sha}},
           "authorizes": ["B7_PHASE7_DETAILED_ROUTE_COMPUTE"],
           "next_stage": "B7_PHASE7_DETAILED_ROUTE_COMPUTE"}
with open(preflight, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2); stream.write("\n")
with open(attempt, "x", encoding="utf-8") as stream:
    json.dump({**payload, "status": "STARTED", "invocation_count": 1}, stream, indent=2); stream.write("\n")
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
  echo "WBQ_B7_PHASE7_SIGNAL=$termination_signal" >> "$log"
  if [[ -n "$compute_pid" ]] && kill -0 "$compute_pid" 2>/dev/null; then
    kill -TERM "$compute_pid"
  elif [[ -n "$audit_compute_pid" ]] && kill -0 "$audit_compute_pid" 2>/dev/null; then
    kill -TERM "$audit_compute_pid"
  fi
}

write_fail_closed_manifest() {
  local exit_code="$1"
  [[ -e "$manifest" ]] && return
  python3 - "$manifest" "$attempt" "$log" "$audit_log" "$odb" "$sdc" "$def" "$netlist" \
    "$drc" "$antenna" "$maze" "$timing" "$max_slew" "$max_capacitance" "$max_fanout" \
    "$exit_code" "$termination_signal" <<'PY'
import hashlib, json, pathlib, sys
(manifest, attempt, log, audit_log, odb, sdc, deffile, netlist, drc, antenna, maze,
 timing, max_slew, max_capacitance, max_fanout, exit_code, signal) = sys.argv[1:]
def item(text):
    path = pathlib.Path(text)
    if not path.exists():
        return {"path": str(path), "exists": False, "bytes": 0, "sha256": None}
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return {"path": str(path), "exists": True, "bytes": path.stat().st_size,
            "sha256": digest.hexdigest()}
attempt_data = json.load(open(attempt, encoding="utf-8"))
payload = {
    "schema_version": 2, "phase": 7, "variant": "B7_PHASE7_DETAILED_ROUTE",
    "status": "FAIL", "verdict": "INVALID_RUN",
    "failure_class": "interrupted" if signal else "tool_error",
    "invocation_count": 1, "start_utc": attempt_data["generated_at_utc"],
    "end_utc": __import__("datetime").datetime.now(__import__("datetime").timezone.utc).isoformat(),
    "exit_code": int(exit_code), "termination_signal": signal or None,
    "service": attempt_data.get("service"), "wrapper_pid": attempt_data.get("wrapper_pid"),
    "launcher_pid": attempt_data.get("launcher_pid"), "compute_pid": attempt_data.get("compute_pid"),
    "audit_compute_pid": attempt_data.get("audit_compute_pid"), "inputs": attempt_data.get("inputs", {}),
    "artifacts": {"detailed_odb": item(odb), "detailed_sdc": item(sdc),
                  "detailed_def": item(deffile), "detailed_netlist": item(netlist),
                  "drc_report": item(drc), "antenna_report": item(antenna),
                  "maze_log": item(maze), "timing_report": item(timing),
                  "max_slew_report": item(max_slew), "max_capacitance_report": item(max_capacitance),
                  "max_fanout_report": item(max_fanout), "run_log": item(log),
                  "audit_log": item(audit_log)},
    "authorizes": [], "next_stage": None,
}
with open(manifest, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2); stream.write("\n")
PY
}

on_exit() {
  local exit_code="$?"
  if (( finalized == 0 )); then
    if [[ -n "$compute_pid" ]] && kill -0 "$compute_pid" 2>/dev/null; then
      kill -TERM "$compute_pid" 2>/dev/null || true
    fi
    if [[ -n "$audit_compute_pid" ]] && kill -0 "$audit_compute_pid" 2>/dev/null; then
      kill -TERM "$audit_compute_pid" 2>/dev/null || true
    fi
    write_fail_closed_manifest "$exit_code" || true
  fi
}

trap 'on_signal INT' INT
trap 'on_signal TERM' TERM
trap 'on_exit' EXIT

{
  echo "WBQ_B7_PHASE7_START_UTC=$start"
  echo "WBQ_B7_PHASE7_INVOCATION_COUNT=1"
  echo "WBQ_B7_PHASE7_SERVICE=$runner_service"
  echo "WBQ_B7_PHASE7_WRAPPER_PID=$$"
  echo "WBQ_B7_PHASE7_INPUT_MANIFEST_SHA256=$manifest_sha"
  echo "WBQ_B7_PHASE7_AUTHORIZATION_SHA256=$authorization_sha"
  echo "WBQ_B7_PHASE7_INPUT_ODB_SHA256=$odb_sha"
  echo "WBQ_B7_PHASE7_INPUT_SDC_SHA256=$sdc_sha"
  echo "WBQ_B7_PHASE7_SIGNAL_LAYERS=met1-met5"
  echo "WBQ_B7_PHASE7_CLOCK_LAYERS=met2-met5"
  echo "WBQ_B7_PHASE7_END_ITERATION=64"
} > "$log"
export WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd"
export WBQ_GRT_ODB="$input_odb"
export WBQ_GRT_SDC="$input_sdc"
export WBQ_DRT_OUTPUT_ROOT="$output_root"
/usr/bin/time -v "$openroad_exe" -exit -no_init -threads "${NUM_CORES:-16}" -no_splash "$tcl" >> "$log" 2>&1 &
launcher_pid="$!"
echo "WBQ_B7_PHASE7_LAUNCHER_PID=$launcher_pid" >> "$log"
python3 - "$attempt" "$launcher_pid" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1]); data = json.loads(path.read_text(encoding="utf-8"))
data["launcher_pid"] = int(sys.argv[2]); path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
for _ in $(seq 1 120); do
  refresh_compute_pid
  if [[ -n "$compute_pid" ]]; then
    echo "WBQ_B7_PHASE7_COMPUTE_PID=$compute_pid" >> "$log"
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
echo "WBQ_B7_PHASE7_EXIT_CODE=$route_rc" >> "$log"
echo "WBQ_B7_PHASE7_ROUTE_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$log"

audit_rc=1
if [[ "$route_rc" -eq 0 && -s "$odb" && -s "$sdc" ]]; then
  {
    echo "WBQ_B7_PHASE7_AUDIT_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "WBQ_B7_PHASE7_AUDIT_ODB_SHA256=$(sha256sum "$odb" | awk '{print $1}')"
    echo "WBQ_B7_PHASE7_AUDIT_SDC_SHA256=$(sha256sum "$sdc" | awk '{print $1}')"
  } > "$audit_log"
  WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd" WBQ_DRT_ODB="$odb" WBQ_DRT_SDC="$sdc" \
    "$openroad_exe" -exit -no_init -threads 1 -no_splash \
    "$audit_tcl" >> "$audit_log" 2>&1 &
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
  echo "WBQ_B7_PHASE7_AUDIT_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$audit_log"
fi
end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

python3 - "$manifest" "$attempt" "$end" "$route_rc" "$audit_rc" "$log" "$audit_log" "$odb" "$sdc" "$def" "$netlist" "$drc" "$antenna" "$maze" "$timing" "$max_slew" "$max_capacitance" "$max_fanout" <<'PY'
import hashlib, json, pathlib, re, sys
(manifest, attempt, end, route_rc, audit_rc, log, audit_log, odb, sdc, deffile,
 netlist, drc, antenna, maze, timing, max_slew, max_capacitance, max_fanout) = sys.argv[1:]
def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
def item(text):
    path = pathlib.Path(text)
    return {"path": str(path), "bytes": path.stat().st_size if path.exists() else 0,
            "sha256": sha(path) if path.exists() else None}
run = pathlib.Path(log).read_text(encoding="utf-8", errors="replace")
audit = pathlib.Path(audit_log).read_text(encoding="utf-8", errors="replace") if pathlib.Path(audit_log).exists() else ""
one = lambda pattern, text: (re.findall(pattern, text, flags=re.MULTILINE) or [None])[-1]
drc_count = one(r"Number of violations\s*=\s*(\d+)", run)
clock_nets = one(r"^WBQ_B7_PHASE7_AUDIT_CLOCK_NET_COUNT (\d+)$", audit)
signal_wires = one(r"^WBQ_B7_PHASE7_AUDIT_SIGNAL_WIRE_COUNT (\d+)$", audit)
antenna_text = pathlib.Path(antenna).read_text(encoding="utf-8", errors="replace") if pathlib.Path(antenna).exists() else ""
antenna_nets = one(r"(?:violating nets|antenna violations?)\D+(\d+)", antenna_text)
timing_text = pathlib.Path(timing).read_text(encoding="utf-8", errors="replace") if pathlib.Path(timing).exists() else ""
worst_slack = one(r"^worst slack\s+([-+0-9.eE]+)\s*$", timing_text)
tns = one(r"^tns\s+([-+0-9.eE]+)\s*$", timing_text)
wns = one(r"^wns\s+([-+0-9.eE]+)\s*$", timing_text)
def violation_rows(path):
    text = pathlib.Path(path).read_text(encoding="utf-8", errors="replace") if pathlib.Path(path).exists() else ""
    return sum(1 for line in text.splitlines() if re.search(r"\s-\d+(?:\.\d+)?\s*$", line))
outputs_complete = all(pathlib.Path(path).is_file() and pathlib.Path(path).stat().st_size > 0
                       for path in (odb, sdc, deffile, netlist, timing)) and all(
                       pathlib.Path(path).is_file() for path in (drc, antenna, maze, max_slew,
                                                                 max_capacitance, max_fanout))
attempt_data = json.load(open(attempt, encoding="utf-8"))
passed = (int(route_rc) == 0 and int(audit_rc) == 0 and outputs_complete and drc_count is not None
          and worst_slack is not None
          and clock_nets is not None and int(clock_nets) > 0
          and signal_wires is not None and int(signal_wires) > 0
          and attempt_data.get("compute_pid") is not None
          and attempt_data.get("audit_compute_pid") is not None
          and "WBQ_B7_PHASE7_DETAILED_ROUTE_AUDIT PASS" in audit)
payload = {"schema_version": 2, "phase": 7, "variant": "B7_PHASE7_DETAILED_ROUTE",
           "status": "PASS" if passed else "FAIL",
           "verdict": "PASS_RESEARCH_DETAILED_ROUTE" if passed else "INVALID_RUN",
           "manufacturing_signoff": False, "invocation_count": 1,
           "start_utc": attempt_data["generated_at_utc"], "end_utc": end,
           "exit_code": int(route_rc), "audit_exit_code": int(audit_rc),
           "service": attempt_data.get("service"),
           "wrapper_pid": attempt_data.get("wrapper_pid"),
           "launcher_pid": attempt_data.get("launcher_pid"),
           "compute_pid": attempt_data.get("compute_pid"),
           "audit_compute_pid": attempt_data.get("audit_compute_pid"),
           "inputs": attempt_data["inputs"],
           "metrics": {"detailed_route_end_iteration": 64,
                       "final_drc_violations": int(drc_count) if drc_count else None,
                       "antenna_violating_nets": int(antenna_nets) if antenna_nets else None,
                       "worst_slack_ns": float(worst_slack) if worst_slack else None,
                       "total_negative_slack_ns": float(tns) if tns else None,
                       "worst_negative_slack_ns": float(wns) if wns else None,
                       "max_slew_violation_rows": violation_rows(max_slew),
                       "max_capacitance_violation_rows": violation_rows(max_capacitance),
                       "max_fanout_violation_rows": violation_rows(max_fanout),
                       "clock_nets": int(clock_nets) if clock_nets else None,
                       "signal_nets_with_wire": int(signal_wires) if signal_wires else None},
           "artifacts": {"detailed_odb": item(odb), "detailed_sdc": item(sdc),
                         "detailed_def": item(deffile), "detailed_netlist": item(netlist),
                         "drc_report": item(drc), "antenna_report": item(antenna),
                         "maze_log": item(maze), "timing_report": item(timing),
                         "max_slew_report": item(max_slew),
                         "max_capacitance_report": item(max_capacitance),
                         "max_fanout_report": item(max_fanout),
                         "run_log": item(log), "audit_log": item(audit_log)},
           "authorizes": ["B7_PHASE7_RTL_GDS_STREAMOUT"] if passed else [],
           "next_stage": "B7_PHASE7_RTL_GDS_STREAMOUT" if passed else None,
           "claim_boundary": "Terminal detailed-route research artifact; reported DRC/antenna results are not waived and no manufacturing signoff is claimed."}
with open(manifest, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2); stream.write("\n")
PY

finalized=1
trap - EXIT INT TERM
test "$route_rc" -eq 0
test "$audit_rc" -eq 0
grep -q '"status": "PASS"' "$manifest"
echo "WBQ_B7_PHASE7_DETAILED_ROUTE PASS report=$manifest"

