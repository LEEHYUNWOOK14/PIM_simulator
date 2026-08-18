#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"

b3_report="$root/reports/groot_normalization/quad_local_b3"
evidence="$b3_report/phase6"
artifact_root="${WBQ_B3_ARTIFACT_ROOT:-/dev/shm/wbq_b3_phase6_10/quad_local_b3}"
phase_root="${WBQ_B3_PHASE6_ROOT:-/dev/shm/wbq_b3_phase6_10/phase6_cts}"
work_home="${WBQ_B3_ORFS_WORK_HOME:-/dev/shm/wbq_b3_phase6_10/orfs}"
orfs_result="$work_home/results/sky130hd/normalization_hbm_quad_local_b3/base"
config="$root/flow/designs/sky130hd/normalization_hbm_quad_local_b3/config.mk"
gate="$b3_report/phase6_decision_gate.json"
placement="$b3_report/physical/b3_placement_execution_report.json"
place_odb="$artifact_root/b3_place.odb"
place_sdc="$artifact_root/b3_place.sdc"
cts_odb="$phase_root/b3_phase6_cts.odb"
cts_sdc="$phase_root/b3_phase6_cts.sdc"
log="$evidence/b3_phase6_cts.log"
audit_log="$evidence/b3_phase6_cts_audit.log"
preflight="$evidence/b3_phase6_cts_preflight.json"
attempt="$evidence/b3_phase6_cts_invocation.json"
manifest="$evidence/b3_phase6_cts_execution_report.json"

mkdir -p "$evidence" "$phase_root" "$orfs_result"
for path in "$config" "$gate" "$placement" "$place_odb" "$place_sdc"; do
  test -s "$path"
done
python3 - "$gate" "$placement" "$place_odb" "$place_sdc" <<'PY'
import hashlib, json, pathlib, sys
def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
gate = json.load(open(sys.argv[1], encoding="utf-8"))
placement = json.load(open(sys.argv[2], encoding="utf-8"))
if gate.get("decision") != "PASS" or "B3_PHASE6_CTS" not in gate.get("authorizes", []):
    raise SystemExit("strict Phase 6 gate does not authorize B3 CTS")
if placement.get("status") != "PASS":
    raise SystemExit("B3 placement is not PASS")
for key, text in (("b3_place_odb", sys.argv[3]), ("b3_place_sdc", sys.argv[4])):
    path = pathlib.Path(text)
    if sha(path) != placement["outputs"][key]["sha256"]:
        raise SystemExit(f"B3 CTS input hash mismatch: {key}")
print("WBQ_B3_PHASE6_CTS_INPUT_GATE PASS")
PY

for path in "$preflight" "$attempt" "$manifest" "$log" "$audit_log" "$cts_odb" "$cts_sdc" \
  "$orfs_result/4_1_cts.odb" "$orfs_result/4_cts.odb" "$orfs_result/4_cts.sdc"; do
  if [[ -e "$path" ]]; then
    echo "existing B3 Phase 6 CTS artifact prevents a fresh invocation: $path" >&2
    exit 4
  fi
done
if pgrep -x openroad >/dev/null; then
  echo "an OpenROAD process already exists; refusing concurrent Phase 6 CTS" >&2
  pgrep -a -x openroad >&2 || true
  exit 3
fi

place_odb_sha="$(sha256sum "$place_odb" | awk '{print $1}')"
place_sdc_sha="$(sha256sum "$place_sdc" | awk '{print $1}')"
gate_sha="$(sha256sum "$gate" | awk '{print $1}')"
placement_sha="$(sha256sum "$placement" | awk '{print $1}')"
start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
free_kib="$(df -Pk "$phase_root" | awk 'NR==2 {print $4}')"
available_kib="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
python3 - "$preflight" "$attempt" "$start" "$gate" "$gate_sha" "$placement" "$placement_sha" "$place_odb" "$place_odb_sha" "$place_sdc" "$place_sdc_sha" "$free_kib" "$available_kib" <<'PY'
import json, sys
(preflight, attempt, start, gate, gate_sha, placement, placement_sha, odb, odb_sha,
 sdc, sdc_sha, free_kib, available_kib) = sys.argv[1:]
payload = {
    "schema_version": 1, "phase": 6, "variant": "B3_PHASE6_CTS",
    "status": "PASS", "generated_at_utc": start,
    "command": "make -C ORFS WORK_HOME=<B3 tmpfs> ... do-4_1_cts",
    "openroad_compute_invocation_limit": 1,
    "policy": "repository ORFS TritonCTS with -sink_clustering_enable and -repair_clock_nets",
    "resources": {"free_kib": int(free_kib), "mem_available_kib": int(available_kib)},
    "inputs": {
        "strict_phase6_gate": {"path": gate, "sha256": gate_sha},
        "placement_report": {"path": placement, "sha256": placement_sha},
        "placed_odb": {"path": odb, "sha256": odb_sha},
        "placed_sdc": {"path": sdc, "sha256": sdc_sha},
    },
    "authorizes": ["B3_PHASE6_CTS_COMPUTE"], "next_stage": "B3_PHASE6_CTS_COMPUTE",
}
with open(preflight, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2); stream.write("\n")
invocation = {**payload, "status": "STARTED", "invocation_count": 1}
with open(attempt, "x", encoding="utf-8") as stream:
    json.dump(invocation, stream, indent=2); stream.write("\n")
PY

ln -s "$place_odb" "$orfs_result/3_place.odb"
ln -s "$place_sdc" "$orfs_result/3_place.sdc"
{
  echo "WBQ_B3_PHASE6_CTS_START_UTC=$start"
  echo "WBQ_B3_PHASE6_CTS_INVOCATION_COUNT=1"
  echo "WBQ_B3_PHASE6_CTS_GATE_SHA256=$gate_sha"
  echo "WBQ_B3_PHASE6_CTS_PLACEMENT_SHA256=$placement_sha"
  echo "WBQ_B3_PHASE6_CTS_PLACE_ODB_SHA256=$place_odb_sha"
  echo "WBQ_B3_PHASE6_CTS_PLACE_SDC_SHA256=$place_sdc_sha"
  echo "WBQ_B3_PHASE6_CTS_POLICY=ORFS_TRITONCTS_REPAIR_CLOCK_NETS"
  echo "WBQ_B3_PHASE6_CTS_SIGNAL_LAYERS=met1-met5"
  echo "WBQ_B3_PHASE6_CTS_CLOCK_LAYERS=met2-met5"
} > "$log"
set +e
/usr/bin/time -v make -C "$orfs_flow" \
  WORK_HOME="$work_home" DESIGN_CONFIG="$config" STOB_REPO_ROOT="$root" \
  YOSYS_EXE="$yosys_exe" OPENROAD_EXE="$openroad_exe" \
  NUM_CORES="${NUM_CORES:-16}" SKIP_REPORT_METRICS=1 \
  MIN_ROUTING_LAYER=met1 MIN_CLK_ROUTING_LAYER=met2 MAX_ROUTING_LAYER=met5 \
  -j1 do-4_1_cts >> "$log" 2>&1
rc=$?
set -e

if [[ "$rc" -eq 0 && -s "$orfs_result/4_1_cts.odb" && -s "$orfs_result/4_cts.sdc" ]]; then
  mv "$orfs_result/4_1_cts.odb" "$cts_odb"
  mv "$orfs_result/4_cts.sdc" "$cts_sdc"
fi
echo "WBQ_B3_PHASE6_CTS_EXIT_CODE=$rc" >> "$log"

audit_rc=1
if [[ "$rc" -eq 0 && -s "$cts_odb" && -s "$cts_sdc" ]]; then
  {
    echo "WBQ_B3_PHASE6_CTS_AUDIT_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "WBQ_B3_PHASE6_CTS_AUDIT_ODB_SHA256=$(sha256sum "$cts_odb" | awk '{print $1}')"
    echo "WBQ_B3_PHASE6_CTS_AUDIT_SDC_SHA256=$(sha256sum "$cts_sdc" | awk '{print $1}')"
  } > "$audit_log"
  set +e
  WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd" WBQ_CTS_ODB="$cts_odb" WBQ_CTS_SDC="$cts_sdc" \
    "$openroad_exe" -exit -no_init -threads 1 -no_splash \
    "$root/verification/groot_normalization/audit_wbq_b3_phase6_cts.tcl" \
    >> "$audit_log" 2>&1
  audit_rc=$?
  set -e
  echo "WBQ_B3_PHASE6_CTS_AUDIT_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$audit_log"
fi
end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "WBQ_B3_PHASE6_CTS_END_UTC=$end" >> "$log"

python3 - "$manifest" "$attempt" "$end" "$rc" "$audit_rc" "$log" "$audit_log" "$cts_odb" "$cts_sdc" <<'PY'
import hashlib, json, pathlib, re, sys
(manifest, attempt, end, rc, audit_rc, log, audit_log, odb, sdc) = sys.argv[1:]
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
run_text = pathlib.Path(log).read_text(encoding="utf-8", errors="replace")
audit_text = pathlib.Path(audit_log).read_text(encoding="utf-8", errors="replace") if pathlib.Path(audit_log).exists() else ""
one = lambda pattern, text: (re.findall(pattern, text, flags=re.MULTILINE) or [None])[-1]
buffers = one(r"\[INFO CTS-0018\]\s+Created (\d+) clock buffers", run_text)
nets = one(r"\[INFO CTS-0015\]\s+Created (\d+) clock nets", run_text)
sinks = one(r"\[INFO CTS-0010\]\s+Clock net .* has (\d+) sinks", run_text)
clock_nets = one(r"^WBQ_B3_PHASE6_CTS_AUDIT_CLOCK_NET_COUNT (\d+)$", audit_text)
passed = (int(rc) == 0 and int(audit_rc) == 0 and "WBQ_B3_PHASE6_CTS_AUDIT PASS" in audit_text
          and all(value is not None and int(value) > 0 for value in (buffers, nets, sinks, clock_nets)))
attempt_data = json.load(open(attempt, encoding="utf-8"))
payload = {
    "schema_version": 1, "phase": 6, "variant": "B3_PHASE6_CTS",
    "status": "PASS" if passed else "FAIL", "invocation_count": 1,
    "start_utc": attempt_data["generated_at_utc"], "end_utc": end,
    "exit_code": int(rc), "audit_exit_code": int(audit_rc),
    "policy": attempt_data["policy"], "inputs": attempt_data["inputs"],
    "metrics": {"initial_clock_sinks": int(sinks) if sinks else None,
                "created_clock_buffers": int(buffers) if buffers else None,
                "created_clock_nets": int(nets) if nets else None,
                "database_clock_nets": int(clock_nets) if clock_nets else None,
                "placement_violations": 0 if "AUDIT_VIOLATIONS {}" in audit_text else None},
    "artifacts": {"cts_odb": item(odb), "cts_sdc": item(sdc),
                  "run_log": item(log), "audit_log": item(audit_log)},
    "authorizes": ["B3_PHASE6_POST_CTS_GLOBAL_ROUTE"] if passed else [],
    "next_stage": "B3_PHASE6_POST_CTS_GLOBAL_ROUTE" if passed else None,
    "claim_boundary": "CTS-completed placed research checkpoint; not manufacturing signoff.",
}
with open(manifest, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2); stream.write("\n")
PY

test "$rc" -eq 0
test "$audit_rc" -eq 0
grep -q '"status": "PASS"' "$manifest"
echo "WBQ_B3_PHASE6_CTS PASS report=$manifest"
