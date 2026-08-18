#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"
report="$root/reports/groot_normalization/quad_local_b16"
physical="$report/physical"
artifacts="${WBQ_B16_ARTIFACT_ROOT:-/dev/shm/wbq_b16_phase6_10/quad_local_b16}"
decision="$report/b16_eco_decision.json"
placement="$root/reports/groot_normalization/quad_local_b9/physical/b9_placement_execution_report.json"
odb_in="/dev/shm/wbq_b9_phase6_10/quad_local_b9/b9_place.odb"
sdc_in="/dev/shm/wbq_b9_phase6_10/quad_local_b9/b9_place.sdc"
smoke_odb="$artifacts/b16_route_pin_smoke.odb"
smoke_tcl="$root/verification/groot_normalization/wbq_b16_route_pin_smoke.tcl"
audit_tcl="$root/verification/groot_normalization/audit_wbq_b16_route_pin_smoke.tcl"
log="$physical/b16_route_pin_smoke.log"
invocation="$physical/b16_route_pin_smoke_invocation.json"
manifest="$physical/b16_route_pin_smoke_execution_report.json"
mkdir -p "$physical" "$artifacts"
for path in "$decision" "$placement" "$odb_in" "$sdc_in" "$smoke_tcl" "$audit_tcl"; do test -s "$path"; done
for path in "$smoke_odb" "$log" "$invocation" "$manifest"; do
  [[ ! -e "$path" ]] || { echo "duplicate B16 smoke artifact: $path" >&2; exit 4; }
done
if pgrep -x openroad >/dev/null; then echo "OpenROAD already exists; refusing B16 smoke" >&2; exit 3; fi
python3 - "$decision" "$placement" "$smoke_tcl" "$audit_tcl" <<'PY'
import json, pathlib, sys
d=json.load(open(sys.argv[1])); p=json.load(open(sys.argv[2]))
if d.get("decision") != "SELECT_B16_BUMP_GRID_COLUMNS_ECO" or d.get("authorizes") != []:
    raise SystemExit("B16 decision not fail-closed")
if p.get("status") != "PASS" or p.get("placement_legality_and_fence_audit") != "PASS":
    raise SystemExit("sealed B9 placement not PASS")
if "set columns 23" not in pathlib.Path(sys.argv[3]).read_text() or "columns=23" not in pathlib.Path(sys.argv[4]).read_text():
    raise SystemExit("B16 grid marker missing")
print("WBQ_B16_SMOKE_STATIC_POLICY PASS columns=23")
PY
sha(){ sha256sum "$1" | awk '{print $1}'; }
start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
service="${WBQ_RUNNER_SERVICE:-direct-cli-b16-smoke}"
python3 - "$invocation" "$start" "$$" "$service" "$decision" "$placement" "$smoke_tcl" "$audit_tcl" "$odb_in" "$sdc_in" <<'PY'
import json, sys
path,start,wrapper,service,decision,placement,smoke,audit,odb,sdc=sys.argv[1:]
payload={"schema_version":1,"variant":"B16","stage":"route_pin_grid_smoke","status":"STARTED",
 "start_utc":start,"invocation_count":1,"service":service,"wrapper_pid":int(wrapper),
 "compute_pid":None,"audit_compute_pid":None,"inputs":{"decision":{"path":decision},
 "placement":{"path":placement},"smoke_tcl":{"path":smoke},"audit_tcl":{"path":audit},
 "b9_place_odb":{"path":odb},"b9_place_sdc":{"path":sdc}},"authorizes":[]}
with open(path,"x",encoding="utf-8") as stream: json.dump(payload,stream,indent=2); stream.write("\n")
PY
{
  echo "WBQ_B16_SMOKE_START_UTC=$start"
  echo "WBQ_B16_SMOKE_INVOCATION_COUNT=1"
  echo "WBQ_B16_SMOKE_STATIC_POLICY columns=23"
} > "$log"
compute_pid=""
audit_compute_pid=""
termination_signal=""
on_signal(){
  termination_signal="$1"
  echo "WBQ_B16_SMOKE_SIGNAL=$termination_signal" >> "$log"
  [[ -z "$compute_pid" ]] || kill -TERM "$compute_pid" 2>/dev/null || true
  [[ -z "$audit_compute_pid" ]] || kill -TERM "$audit_compute_pid" 2>/dev/null || true
}
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM
WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd" WBQ_B16_SMOKE_INPUT_ODB="$odb_in" \
WBQ_B16_SMOKE_INPUT_SDC="$sdc_in" WBQ_B16_SMOKE_OUTPUT_ODB="$smoke_odb" \
  "$openroad_exe" -exit -no_init -threads 1 -no_splash "$smoke_tcl" >> "$log" 2>&1 &
compute_pid="$!"
python3 - "$invocation" "$compute_pid" <<'PY'
import json, pathlib, sys
path=pathlib.Path(sys.argv[1]); data=json.loads(path.read_text()); data["compute_pid"]=int(sys.argv[2])
path.write_text(json.dumps(data,indent=2)+"\n")
PY
set +e
wait "$compute_pid"
rc=$?
set -e
audit_rc=1
if [[ "$rc" -eq 0 && -s "$smoke_odb" ]]; then
  WBQ_B16_SMOKE_OUTPUT_ODB="$smoke_odb" "$openroad_exe" -exit -no_init -threads 1 -no_splash "$audit_tcl" >> "$log" 2>&1 &
  audit_compute_pid="$!"
  python3 - "$invocation" "$audit_compute_pid" <<'PY'
import json, pathlib, sys
path=pathlib.Path(sys.argv[1]); data=json.loads(path.read_text()); data["audit_compute_pid"]=int(sys.argv[2])
path.write_text(json.dumps(data,indent=2)+"\n")
PY
  set +e
  wait "$audit_compute_pid"
  audit_rc=$?
  set -e
fi
end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "WBQ_B16_SMOKE_EXIT_CODE=$rc" >> "$log"
echo "WBQ_B16_SMOKE_AUDIT_EXIT_CODE=$audit_rc" >> "$log"
echo "WBQ_B16_SMOKE_END_UTC=$end" >> "$log"
smoke_sha=""
[[ -s "$smoke_odb" ]] && smoke_sha="$(sha "$smoke_odb")"
python3 - "$manifest" "$invocation" "$log" "$smoke_odb" "$smoke_sha" "$rc" "$audit_rc" "$termination_signal" "$end" <<'PY'
import hashlib, json, pathlib, sys
out,inv,log,odb,odb_sha,rc,arc,signal,end=sys.argv[1:]
data=json.load(open(inv,encoding="utf-8")); text=pathlib.Path(log).read_text(errors="replace")
passed=(int(rc)==0 and int(arc)==0 and not signal and bool(odb_sha)
        and "WBQ_B16_SMOKE_INPUT_REOPEN_AND_CHECKPOINT PASS bump_terms=565 columns=23" in text
        and "WBQ_B16_SMOKE_INDEPENDENT_REOPEN PASS bump_terms=565 columns=23" in text)
data.update({"status":"PASS" if passed else "FAIL","end_utc":end,"exit_code":int(rc),
 "audit_exit_code":int(arc),"termination_signal":signal or None,
 "checks":{"input_reopen":"PASS" if "INPUT_REOPEN" in text else "FAIL",
 "checkpoint_write":"PASS" if odb_sha else "FAIL",
 "independent_checkpoint_reopen":"PASS" if "INDEPENDENT_REOPEN" in text else "FAIL"},
 "outputs":{"smoke_odb":{"path":odb,"sha256":odb_sha},
 "log":{"path":log,"sha256":hashlib.sha256(pathlib.Path(log).read_bytes()).hexdigest()}},
 "authorizes":["B16_ROUTE_AUTHORIZATION"] if passed else [],
 "next_stage":"B16_ROUTE_AUTHORIZATION" if passed else None})
with open(out,"x",encoding="utf-8") as stream: json.dump(data,stream,indent=2); stream.write("\n")
PY
trap - INT TERM
test "$rc" -eq 0
test "$audit_rc" -eq 0
grep -q '"status": "PASS"' "$manifest"
echo "WBQ_B16_ROUTE_PIN_SMOKE PASS report=$manifest"
