#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"

report="$root/reports/groot_normalization/quad_local_b25"
physical="$report/physical"
result="$orfs_flow/results/sky130hd/normalization_hbm_quad_local_b25/base"
config="$root/flow/designs/sky130hd/normalization_hbm_quad_local_b25/config.mk"
cheap="$report/cheap_gate_manifest.json"
authorization="$report/b25_placement_authorization.json"
floorplan="$result/2_floorplan.odb"
floorplan_sdc="$result/2_1_floorplan.sdc"
place_odb="$result/3_place.odb"
place_sdc="$result/3_place.sdc"
audit_tcl="$root/verification/groot_normalization/audit_wbq_quad_local_placement.tcl"
log="$physical/b25_place.log"
invocation="$physical/b25_place_invocation.json"
manifest="$physical/b25_placement_execution_report.json"
mkdir -p "$physical"

for path in "$config" "$cheap" "$authorization" "$floorplan" "$floorplan_sdc" "$audit_tcl"; do test -s "$path"; done
for path in "$log" "$invocation" "$manifest" "$place_odb" "$place_sdc"; do
  [[ ! -e "$path" ]] || { echo "B25 placement already attempted; refusing duplicate ($path)" >&2; exit 4; }
done
if pgrep -x openroad >/dev/null; then pgrep -a -x openroad >&2; exit 3; fi

python3 - "$cheap" "$authorization" <<'PY'
import hashlib,json,pathlib,sys
cheap=json.load(open(sys.argv[1])); auth=json.load(open(sys.argv[2]))
if cheap.get("overall_result") != "PASS" or "B25_PLACEMENT" not in cheap.get("authorizes",[]): raise SystemExit("B25 cheap gate does not authorize placement")
if auth.get("decision") != "PASS" or auth.get("authorizes") != ["B25_PLACEMENT"]: raise SystemExit("B25 placement authorization is not PASS")
def sha(p):
 h=hashlib.sha256()
 with open(p,'rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return h.hexdigest()
if sha(sys.argv[1]) != auth["inputs"]["cheap_gate"]["sha256"]: raise SystemExit("cheap gate hash mismatch")
for name,item in auth.get("inputs",{}).items():
 p=pathlib.Path(item["path"])
 if not p.is_file() or sha(p)!=item["sha256"]: raise SystemExit(f"authorization input hash mismatch: {name}")
print("WBQ_B25_PLACEMENT_AUTHORIZATION PASS")
PY

start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
service="${WBQ_RUNNER_SERVICE:-direct-cli-b25-placement}"
python3 - "$invocation" "$start" "$service" "$$" "$cheap" "$authorization" "$floorplan" "$floorplan_sdc" "$config" <<'PY'
import hashlib,json,sys
out,start,service,wrapper,*paths=sys.argv[1:]
names=("cheap_gate","authorization","floorplan_odb","floorplan_sdc","config")
def ev(p):
 h=hashlib.sha256()
 with open(p,'rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return {"path":p,"sha256":h.hexdigest()}
d={"schema_version":1,"variant":"B25","stage":"legal_placement","status":"STARTED","invocation_count":1,"start_utc":start,"service":service,"wrapper_pid":int(wrapper),"launcher_pid":None,"compute_pid_initial":None,"inputs":{n:ev(p) for n,p in zip(names,paths)},"authorizes":[]}
with open(out,'x') as f:json.dump(d,f,indent=2);f.write('\n')
PY

{
 echo "WBQ_B25_PLACE_START_UTC=$start"
 echo "WBQ_B25_PLACE_INVOCATION_COUNT=1"
 echo "WBQ_B25_PLACE_SERVICE=$service"
} > "$log"

termination_signal=""
launcher_pid=""
compute_pid=""
audit_compute_pid=""
finalized=0
on_signal(){
  termination_signal="$1"
  [[ -z "$compute_pid" ]] || kill -TERM "$compute_pid" 2>/dev/null || true
  [[ -z "$audit_compute_pid" ]] || kill -TERM "$audit_compute_pid" 2>/dev/null || true
  [[ -z "$launcher_pid" ]] || kill -TERM "$launcher_pid" 2>/dev/null || true
}
write_unexpected_fail(){
  local shell_rc=$?
  if [[ "$finalized" -eq 0 && -s "$invocation" && ! -e "$manifest" ]]; then
    python3 - "$invocation" "$manifest" "$log" "$shell_rc" "$termination_signal" <<'PY'
import hashlib,json,pathlib,sys
inv,out,log,rc,sig=sys.argv[1:];d=json.load(open(inv));p=pathlib.Path(log)
d.update({"status":"FAIL","end_utc":__import__('datetime').datetime.now(__import__('datetime').timezone.utc).isoformat(),"exit_code":int(rc),"termination_signal":sig or None,"failure_class":"interrupted" if sig else "tool_error","outputs":{"log":{"path":log,"sha256":hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else None}},"authorizes":[],"next_stage":None})
with open(out,'x') as f:json.dump(d,f,indent=2);f.write('\n')
PY
  fi
}
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM
trap write_unexpected_fail EXIT
set +e
/usr/bin/time -v make -C "$orfs_flow" DESIGN_CONFIG="$config" STOB_REPO_ROOT="$root" \
  YOSYS_EXE="$yosys_exe" OPENROAD_EXE="$openroad_exe" NUM_CORES="${NUM_CORES:-16}" SKIP_REPORT_METRICS=1 -j1 place \
  >> "$log" 2>&1 &
launcher_pid="$!"
python3 - "$invocation" "$launcher_pid" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);d=json.loads(p.read_text());d['launcher_pid']=int(sys.argv[2]);p.write_text(json.dumps(d,indent=2)+'\n')
PY
sleep 3
compute_pid="$(pgrep -x -n openroad || true)"
python3 - "$invocation" "$compute_pid" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);d=json.loads(p.read_text());d['compute_pid_initial']=int(sys.argv[2]) if sys.argv[2] else None;p.write_text(json.dumps(d,indent=2)+'\n')
PY
wait "$launcher_pid"; rc=$?
set -e

audit_rc=1
if [[ "$rc" -eq 0 && -s "$place_odb" && -s "$place_sdc" ]]; then
  WBQ_QUAD_PLACE_ODB="$place_odb" WBQ_QUAD_PLACE_SDC="$place_sdc" \
    "$openroad_exe" -no_init -exit -threads 1 "$audit_tcl" >> "$log" 2>&1 &
  audit_compute_pid="$!"
  python3 - "$invocation" "$audit_compute_pid" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);d=json.loads(p.read_text());d['audit_compute_pid']=int(sys.argv[2]);p.write_text(json.dumps(d,indent=2)+'\n')
PY
  set +e; wait "$audit_compute_pid"; audit_rc=$?; set -e
fi
end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
python3 - "$invocation" "$manifest" "$end" "$rc" "$audit_rc" "$termination_signal" "$place_odb" "$place_sdc" "$log" <<'PY'
import hashlib,json,pathlib,sys
inv,out,end,rc,arc,sig,odb,sdc,log=sys.argv[1:]
d=json.load(open(inv)); passed=int(rc)==0 and int(arc)==0 and not sig and pathlib.Path(odb).is_file() and pathlib.Path(sdc).is_file() and 'WBQ_QUAD_LOCAL_PLACEMENT_AUDIT PASS' in pathlib.Path(log).read_text(errors='replace')
def ev(p):
 q=pathlib.Path(p)
 if not q.is_file():return {"path":p,"sha256":None}
 h=hashlib.sha256()
 with q.open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return {"path":p,"sha256":h.hexdigest()}
d.update({"status":"PASS" if passed else "FAIL","end_utc":end,"exit_code":int(rc),"audit_exit_code":int(arc),"termination_signal":sig or None,"outputs":{"b25_place_odb":ev(odb),"b25_place_sdc":ev(sdc),"log":ev(log)},"placement_legality_and_fence_audit":"PASS" if passed else "FAIL","authorizes":["B25_SINGLE_GLOBAL_ROUTE"] if passed else [],"next_stage":"B25_SINGLE_GLOBAL_ROUTE" if passed else None})
with open(out,'x') as f:json.dump(d,f,indent=2);f.write('\n')
pathlib.Path(inv).write_text(json.dumps(d,indent=2)+'\n')
print('WBQ_B25_PLACEMENT '+('PASS' if passed else 'FAIL'))
raise SystemExit(0 if passed else 1)
PY
finalized=1
trap - EXIT INT TERM
test "$rc" -eq 0; test "$audit_rc" -eq 0; grep -q '"status": "PASS"' "$manifest"
echo "WBQ_B25_PLACEMENT PASS report=$manifest"
