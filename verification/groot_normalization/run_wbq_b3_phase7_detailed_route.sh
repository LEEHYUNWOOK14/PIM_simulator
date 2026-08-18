#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"

b3_report="$root/reports/groot_normalization/quad_local_b3"
phase6="$b3_report/phase6"
evidence="$b3_report/phase7"
input_root="${WBQ_B3_PHASE6_ROUTE_ROOT:-/dev/shm/wbq_b3_phase6_10/phase6_post_cts}"
output_root="${WBQ_B3_PHASE7_ROOT:-/dev/shm/wbq_b3_phase6_10/phase7}"
input_manifest="$phase6/b3_phase6_post_cts_global_route_execution_report.json"
input_odb="$input_root/b3_phase6_post_cts_global_route.odb"
input_sdc="$input_root/b3_phase6_post_cts_global_route.sdc"
log="$evidence/b3_phase7_detailed_route.log"
audit_log="$evidence/b3_phase7_detailed_route_audit.log"
preflight="$evidence/b3_phase7_preflight.json"
attempt="$evidence/b3_phase7_detailed_route_invocation.json"
manifest="$evidence/b3_phase7_detailed_route_execution_report.json"
odb="$output_root/b3_phase7_detailed_route.odb"
sdc="$output_root/b3_phase7_detailed_route.sdc"
def="$output_root/b3_phase7_detailed_route.def"
netlist="$output_root/b3_phase7_detailed_route.v"
drc="$output_root/b3_phase7_detailed_route.drc.rpt"
antenna="$output_root/b3_phase7_antenna.rpt"
maze="$output_root/b3_phase7_detailed_route.maze.log"
tcl="$root/verification/groot_normalization/wbq_b3_phase7_detailed_route.tcl"

mkdir -p "$evidence" "$output_root"
for path in "$input_manifest" "$input_odb" "$input_sdc" "$tcl"; do test -s "$path"; done
python3 - "$input_manifest" "$input_odb" "$input_sdc" "$output_root" <<'PY'
import hashlib, json, pathlib, shutil, sys
def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
if manifest.get("status") != "PASS" or "B3_PHASE7_DETAILED_ROUTE" not in manifest.get("authorizes", []):
    raise SystemExit("Phase 6 does not authorize B3 Phase 7 detailed route")
for key, text in (("routed_odb", sys.argv[2]), ("routed_sdc", sys.argv[3])):
    path = pathlib.Path(text)
    if sha(path) != manifest["artifacts"][key]["sha256"]:
        raise SystemExit(f"Phase 7 input hash mismatch: {key}")
mem_kib = int(next(line.split()[1] for line in pathlib.Path("/proc/meminfo").read_text().splitlines() if line.startswith("MemAvailable:")))
free = shutil.disk_usage(sys.argv[4]).free
if mem_kib < 32 * 1024 * 1024:
    raise SystemExit(f"Phase 7 requires 32 GiB available RAM; found {mem_kib / 1024**2:.2f} GiB")
if free < 40 * 1024**3:
    raise SystemExit(f"Phase 7 requires 40 GiB free disk; found {free / 1024**3:.2f} GiB")
print(f"WBQ_B3_PHASE7_INPUT_GATE PASS available_ram_gib={mem_kib / 1024**2:.2f} free_disk_gib={free / 1024**3:.2f}")
PY

for path in "$preflight" "$attempt" "$manifest" "$log" "$audit_log" "$odb" "$sdc" "$def" \
  "$netlist" "$drc" "$antenna" "$maze"; do
  if [[ -e "$path" ]]; then echo "existing B3 Phase 7 artifact prevents overwrite: $path" >&2; exit 4; fi
done
if pgrep -x openroad >/dev/null; then echo "OpenROAD already exists; refusing concurrent Phase 7" >&2; exit 3; fi

manifest_sha="$(sha256sum "$input_manifest" | awk '{print $1}')"
odb_sha="$(sha256sum "$input_odb" | awk '{print $1}')"
sdc_sha="$(sha256sum "$input_sdc" | awk '{print $1}')"
start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mem_kib="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
free_kib="$(df -Pk "$output_root" | awk 'NR==2 {print $4}')"
python3 - "$preflight" "$attempt" "$start" "$input_manifest" "$manifest_sha" "$input_odb" "$odb_sha" "$input_sdc" "$sdc_sha" "$mem_kib" "$free_kib" <<'PY'
import json, sys
preflight, attempt, start, manifest, manifest_sha, odb, odb_sha, sdc, sdc_sha, mem_kib, free_kib = sys.argv[1:]
payload = {"schema_version": 1, "phase": 7, "variant": "B3_PHASE7_DETAILED_ROUTE",
           "status": "PASS", "generated_at_utc": start,
           "command": "openroad -threads 16 wbq_b3_phase7_detailed_route.tcl",
           "droute_end_iteration": 64, "required_mem_available_gib": 32,
           "required_free_disk_gib": 40, "actual_mem_available_kib": int(mem_kib),
           "actual_free_disk_kib": int(free_kib),
           "inputs": {"phase6_manifest": {"path": manifest, "sha256": manifest_sha},
                      "routed_odb": {"path": odb, "sha256": odb_sha},
                      "routed_sdc": {"path": sdc, "sha256": sdc_sha}},
           "authorizes": ["B3_PHASE7_DETAILED_ROUTE_COMPUTE"],
           "next_stage": "B3_PHASE7_DETAILED_ROUTE_COMPUTE"}
with open(preflight, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2); stream.write("\n")
with open(attempt, "x", encoding="utf-8") as stream:
    json.dump({**payload, "status": "STARTED", "invocation_count": 1}, stream, indent=2); stream.write("\n")
PY

{
  echo "WBQ_B3_PHASE7_START_UTC=$start"
  echo "WBQ_B3_PHASE7_INVOCATION_COUNT=1"
  echo "WBQ_B3_PHASE7_INPUT_MANIFEST_SHA256=$manifest_sha"
  echo "WBQ_B3_PHASE7_INPUT_ODB_SHA256=$odb_sha"
  echo "WBQ_B3_PHASE7_INPUT_SDC_SHA256=$sdc_sha"
  echo "WBQ_B3_PHASE7_SIGNAL_LAYERS=met1-met5"
  echo "WBQ_B3_PHASE7_CLOCK_LAYERS=met2-met5"
  echo "WBQ_B3_PHASE7_END_ITERATION=64"
} > "$log"
export WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd"
export WBQ_GRT_ODB="$input_odb"
export WBQ_GRT_SDC="$input_sdc"
export WBQ_DRT_OUTPUT_ROOT="$output_root"
set +e
/usr/bin/time -v "$openroad_exe" -exit -no_init -threads "${NUM_CORES:-16}" -no_splash "$tcl" >> "$log" 2>&1
route_rc=$?
set -e
echo "WBQ_B3_PHASE7_EXIT_CODE=$route_rc" >> "$log"
echo "WBQ_B3_PHASE7_ROUTE_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$log"

audit_rc=1
if [[ "$route_rc" -eq 0 && -s "$odb" && -s "$sdc" ]]; then
  {
    echo "WBQ_B3_PHASE7_AUDIT_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "WBQ_B3_PHASE7_AUDIT_ODB_SHA256=$(sha256sum "$odb" | awk '{print $1}')"
    echo "WBQ_B3_PHASE7_AUDIT_SDC_SHA256=$(sha256sum "$sdc" | awk '{print $1}')"
  } > "$audit_log"
  set +e
  WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd" WBQ_DRT_ODB="$odb" WBQ_DRT_SDC="$sdc" \
    "$openroad_exe" -exit -no_init -threads 1 -no_splash \
    "$root/verification/groot_normalization/audit_wbq_b3_phase7_detailed_route.tcl" \
    >> "$audit_log" 2>&1
  audit_rc=$?
  set -e
  echo "WBQ_B3_PHASE7_AUDIT_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$audit_log"
fi
end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

python3 - "$manifest" "$attempt" "$end" "$route_rc" "$audit_rc" "$log" "$audit_log" "$odb" "$sdc" "$def" "$netlist" "$drc" "$antenna" "$maze" <<'PY'
import hashlib, json, pathlib, re, sys
(manifest, attempt, end, route_rc, audit_rc, log, audit_log, odb, sdc, deffile,
 netlist, drc, antenna, maze) = sys.argv[1:]
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
clock_nets = one(r"^WBQ_B3_PHASE7_AUDIT_CLOCK_NET_COUNT (\d+)$", audit)
signal_wires = one(r"^WBQ_B3_PHASE7_AUDIT_SIGNAL_WIRE_COUNT (\d+)$", audit)
antenna_text = pathlib.Path(antenna).read_text(encoding="utf-8", errors="replace") if pathlib.Path(antenna).exists() else ""
antenna_nets = one(r"(?:violating nets|antenna violations?)\D+(\d+)", antenna_text)
outputs_complete = all(pathlib.Path(path).is_file() and pathlib.Path(path).stat().st_size > 0
                       for path in (odb, sdc, deffile, netlist)) and all(
                       pathlib.Path(path).is_file() for path in (drc, antenna, maze))
passed = (int(route_rc) == 0 and int(audit_rc) == 0 and outputs_complete and drc_count is not None
          and clock_nets is not None and int(clock_nets) > 0
          and signal_wires is not None and int(signal_wires) > 0
          and "WBQ_B3_PHASE7_DETAILED_ROUTE_AUDIT PASS" in audit)
attempt_data = json.load(open(attempt, encoding="utf-8"))
payload = {"schema_version": 1, "phase": 7, "variant": "B3_PHASE7_DETAILED_ROUTE",
           "status": "PASS" if passed else "FAIL",
           "verdict": "PASS_RESEARCH_DETAILED_ROUTE" if passed else "INVALID_RUN",
           "manufacturing_signoff": False, "invocation_count": 1,
           "start_utc": attempt_data["generated_at_utc"], "end_utc": end,
           "exit_code": int(route_rc), "audit_exit_code": int(audit_rc),
           "inputs": attempt_data["inputs"],
           "metrics": {"detailed_route_end_iteration": 64,
                       "final_drc_violations": int(drc_count) if drc_count else None,
                       "antenna_violating_nets": int(antenna_nets) if antenna_nets else None,
                       "clock_nets": int(clock_nets) if clock_nets else None,
                       "signal_nets_with_wire": int(signal_wires) if signal_wires else None},
           "artifacts": {"detailed_odb": item(odb), "detailed_sdc": item(sdc),
                         "detailed_def": item(deffile), "detailed_netlist": item(netlist),
                         "drc_report": item(drc), "antenna_report": item(antenna),
                         "maze_log": item(maze), "run_log": item(log), "audit_log": item(audit_log)},
           "authorizes": ["B3_PHASE7_RTL_GDS_STREAMOUT"] if passed else [],
           "next_stage": "B3_PHASE7_RTL_GDS_STREAMOUT" if passed else None,
           "claim_boundary": "Terminal detailed-route research artifact; reported DRC/antenna results are not waived and no manufacturing signoff is claimed."}
with open(manifest, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2); stream.write("\n")
PY

test "$route_rc" -eq 0
test "$audit_rc" -eq 0
grep -q '"status": "PASS"' "$manifest"
echo "WBQ_B3_PHASE7_DETAILED_ROUTE PASS report=$manifest"
