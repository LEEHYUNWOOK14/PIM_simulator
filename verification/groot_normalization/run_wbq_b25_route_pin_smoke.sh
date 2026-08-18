#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"

report="$root/reports/groot_normalization/quad_local_b25"
physical="$report/physical"
artifacts="${WBQ_B25_ROUTE_ARTIFACT_ROOT:-/dev/shm/wbq_b25_phase6_10/quad_local_b25_route}"
result="$orfs_flow/results/sky130hd/normalization_hbm_quad_local_b25/base"
decision="$report/b25_eco_decision.json"
cheap="$report/cheap_gate_manifest.json"
placement="$physical/b25_placement_execution_report.json"
odb_in="$result/3_place.odb"
sdc_in="$result/3_place.sdc"
smoke_odb="$artifacts/b25_route_pin_smoke.odb"
smoke_tcl="$root/verification/groot_normalization/wbq_b25_route_pin_smoke.tcl"
audit_tcl="$root/verification/groot_normalization/audit_wbq_b25_route_pin_smoke.tcl"
log="$physical/b25_route_pin_smoke.log"
invocation="$physical/b25_route_pin_smoke_invocation.json"
manifest="$physical/b25_route_pin_smoke_execution_report.json"
mkdir -p "$physical" "$artifacts"

for path in "$decision" "$cheap" "$placement" "$odb_in" "$sdc_in" "$smoke_tcl" "$audit_tcl"; do test -s "$path"; done
for path in "$smoke_odb" "$log" "$invocation" "$manifest"; do
  [[ ! -e "$path" ]] || { echo "duplicate B25 smoke artifact: $path" >&2; exit 4; }
done
if pgrep -x openroad >/dev/null; then echo "OpenROAD already exists; refusing B25 smoke" >&2; pgrep -a -x openroad >&2; exit 3; fi
free_kib="$(df -Pk "$artifacts" | awk 'NR==2 {print $4}')"
available_kib="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
(( free_kib >= 8 * 1024 * 1024 )) || { echo "less than 8 GiB free for B25 smoke" >&2; exit 5; }
(( available_kib >= 32 * 1024 * 1024 )) || { echo "less than 32 GiB MemAvailable for B25 smoke" >&2; exit 6; }

python3 - "$decision" "$cheap" "$placement" "$odb_in" "$sdc_in" "$smoke_tcl" "$audit_tcl" <<'PY'
import hashlib,json,pathlib,sys
def sha(path):
 d=hashlib.sha256()
 with path.open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):d.update(b)
 return d.hexdigest()
d=json.load(open(sys.argv[1]));cheap=json.load(open(sys.argv[2]));p=json.load(open(sys.argv[3]))
if d.get('decision')!='SELECT_B25_AGGREGATED_COMPLETION_DESCRIPTOR_ECO':raise SystemExit('B25 structural decision mismatch')
if cheap.get('overall_result')!='PASS' or 'B25_SINGLE_GLOBAL_ROUTE' not in cheap.get('authorizes',[]):raise SystemExit('B25 cheap gate does not authorize route')
if p.get('status')!='PASS' or p.get('placement_legality_and_fence_audit')!='PASS' or p.get('authorizes')!=['B25_SINGLE_GLOBAL_ROUTE']:raise SystemExit('B25 placement does not authorize route')
for key,text in (('b25_place_odb',sys.argv[4]),('b25_place_sdc',sys.argv[5])):
 if sha(pathlib.Path(text))!=p['outputs'][key]['sha256']:raise SystemExit(f'B25 placement output hash mismatch: {key}')
t=pathlib.Path(sys.argv[6]).read_text();a=pathlib.Path(sys.argv[7]).read_text()
if not all(x in t for x in ('set columns 25','set x0 1500.0','set y0 1000.0')) or 'x0=1500.0 y0=1000.0' not in a:raise SystemExit('B25 route grid marker mismatch')
print('WBQ_B25_SMOKE_INPUT_GATE PASS columns=25 x0=1500 y0=1000')
PY

start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
service="${WBQ_RUNNER_SERVICE:-direct-cli-b25-smoke}"
python3 - "$invocation" "$start" "$service" "$$" "$decision" "$cheap" "$placement" "$odb_in" "$sdc_in" "$smoke_tcl" "$audit_tcl" "$free_kib" "$available_kib" <<'PY'
import hashlib,json,sys
out,start,service,wrapper,*rest=sys.argv[1:];paths=rest[:7];free_kib,mem_kib=rest[7:]
names=('decision','cheap_gate','placement_manifest','b25_place_odb','b25_place_sdc','smoke_tcl','audit_tcl')
def ev(p):
 h=hashlib.sha256()
 with open(p,'rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return {'path':p,'sha256':h.hexdigest()}
d={'schema_version':1,'variant':'B25','stage':'route_pin_grid_smoke','status':'STARTED','start_utc':start,'invocation_count':1,'service':service,'wrapper_pid':int(wrapper),'compute_pid':None,'audit_compute_pid':None,'resources_at_start':{'artifact_free_kib':int(free_kib),'mem_available_kib':int(mem_kib)},'policy':{'columns':25,'pitch_um':300.0,'x0_um':1500.0,'y0_um':1000.0},'inputs':{n:ev(p) for n,p in zip(names,paths)},'authorizes':[]}
with open(out,'x') as f:json.dump(d,f,indent=2);f.write('\n')
PY
{
  echo "WBQ_B25_SMOKE_START_UTC=$start"
  echo "WBQ_B25_SMOKE_INVOCATION_COUNT=1"
  echo "WBQ_B25_SMOKE_POLICY columns=25 x0=1500.0 y0=1000.0"
} > "$log"

compute_pid=""; audit_compute_pid=""; termination_signal=""; finalized=0
on_signal(){
  termination_signal="$1"
  [[ -z "$compute_pid" ]] || kill -TERM "$compute_pid" 2>/dev/null || true
  [[ -z "$audit_compute_pid" ]] || kill -TERM "$audit_compute_pid" 2>/dev/null || true
}
write_unexpected_fail(){
  local shell_rc=$?
  if [[ "$finalized" -eq 0 && -s "$invocation" && ! -e "$manifest" ]]; then
    python3 - "$invocation" "$manifest" "$log" "$shell_rc" "$termination_signal" <<'PY'
import hashlib,json,pathlib,sys
inv,out,log,rc,sig=sys.argv[1:];d=json.load(open(inv));p=pathlib.Path(log)
d.update({'status':'FAIL','end_utc':__import__('datetime').datetime.now(__import__('datetime').timezone.utc).isoformat(),'exit_code':int(rc),'termination_signal':sig or None,'failure_class':'interrupted' if sig else 'tool_error','outputs':{'log':{'path':log,'sha256':hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else None}},'authorizes':[],'next_stage':None})
with open(out,'x') as f:json.dump(d,f,indent=2);f.write('\n')
PY
  fi
}
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM
trap write_unexpected_fail EXIT

WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd" WBQ_B25_SMOKE_INPUT_ODB="$odb_in" \
WBQ_B25_SMOKE_INPUT_SDC="$sdc_in" WBQ_B25_SMOKE_OUTPUT_ODB="$smoke_odb" \
  "$openroad_exe" -exit -no_init -threads 1 -no_splash "$smoke_tcl" >> "$log" 2>&1 &
compute_pid="$!"
python3 - "$invocation" "$compute_pid" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);d=json.loads(p.read_text());d['compute_pid']=int(sys.argv[2]);p.write_text(json.dumps(d,indent=2)+'\n')
PY
set +e; wait "$compute_pid"; rc=$?; set -e

audit_rc=1
if [[ "$rc" -eq 0 && -s "$smoke_odb" ]]; then
  WBQ_B25_SMOKE_OUTPUT_ODB="$smoke_odb" "$openroad_exe" -exit -no_init -threads 1 -no_splash "$audit_tcl" >> "$log" 2>&1 &
  audit_compute_pid="$!"
  python3 - "$invocation" "$audit_compute_pid" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);d=json.loads(p.read_text());d['audit_compute_pid']=int(sys.argv[2]);p.write_text(json.dumps(d,indent=2)+'\n')
PY
  set +e; wait "$audit_compute_pid"; audit_rc=$?; set -e
fi
end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
python3 - "$manifest" "$invocation" "$log" "$smoke_odb" "$rc" "$audit_rc" "$termination_signal" "$end" <<'PY'
import hashlib,json,pathlib,sys
out,inv,log,odb,rc,arc,sig,end=sys.argv[1:];d=json.load(open(inv));text=pathlib.Path(log).read_text(errors='replace')
def ev(p):
 q=pathlib.Path(p)
 if not q.is_file():return {'path':p,'bytes':0,'sha256':None}
 h=hashlib.sha256()
 with q.open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return {'path':p,'bytes':q.stat().st_size,'sha256':h.hexdigest()}
passed=int(rc)==0 and int(arc)==0 and not sig and d.get('compute_pid') and d.get('audit_compute_pid') and 'WBQ_B25_SMOKE_INPUT_REOPEN_AND_CHECKPOINT PASS bump_terms=565 columns=25 x0=1500.0 y0=1000.0' in text and 'WBQ_B25_SMOKE_INDEPENDENT_REOPEN PASS bump_terms=565 columns=25 x0=1500.0 y0=1000.0' in text
d.update({'status':'PASS' if passed else 'FAIL','end_utc':end,'exit_code':int(rc),'audit_exit_code':int(arc),'termination_signal':sig or None,'checks':{'input_reopen_and_checkpoint':'PASS' if 'INPUT_REOPEN_AND_CHECKPOINT PASS' in text else 'FAIL','independent_checkpoint_reopen':'PASS' if 'INDEPENDENT_REOPEN PASS' in text else 'FAIL'},'outputs':{'smoke_odb':ev(odb),'log':ev(log)},'authorizes':['B25_GLOBAL_ROUTE_AUTHORIZATION'] if passed else [],'next_stage':'B25_GLOBAL_ROUTE_AUTHORIZATION' if passed else None})
with open(out,'x') as f:json.dump(d,f,indent=2);f.write('\n')
PY
finalized=1
trap - EXIT INT TERM
test "$rc" -eq 0; test "$audit_rc" -eq 0; grep -q '"status": "PASS"' "$manifest"
echo "WBQ_B25_ROUTE_PIN_SMOKE PASS report=$manifest"
