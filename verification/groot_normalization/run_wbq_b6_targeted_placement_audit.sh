#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"

physical="$root/reports/groot_normalization/quad_local_b6/physical"
artifacts="${WBQ_B6_ARTIFACT_ROOT:-/dev/shm/wbq_b6_phase6_10/quad_local_b6}"
placement="$physical/b6_placement_execution_report.json"
odb="$artifacts/b6_place.odb"
sdc="$artifacts/b6_place.sdc"
tcl="$root/verification/groot_normalization/audit_wbq_b6_targeted_placement.tcl"
log="$physical/b6_targeted_placement_reopen_audit.log"
invocation="$physical/b6_targeted_placement_reopen_audit_invocation.json"
report="$physical/b6_targeted_placement_reopen_audit.json"

for path in "$placement" "$odb" "$sdc" "$tcl"; do test -s "$path"; done
python3 - "$placement" "$odb" "$sdc" <<'PY'
import hashlib, json, pathlib, sys
def sha(path):
    digest=hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(8*1024*1024), b''): digest.update(chunk)
    return digest.hexdigest()
placement=json.load(open(sys.argv[1], encoding='utf-8'))
if placement.get('status') != 'PASS' or placement.get('placement_legality_and_fence_audit') != 'PASS':
    raise SystemExit('B6 placement manifest is not PASS')
for key,text in (('b6_place_odb',sys.argv[2]),('b6_place_sdc',sys.argv[3])):
    if sha(pathlib.Path(text)) != placement['outputs'][key]['sha256']:
        raise SystemExit(f'B6 targeted reopen input hash mismatch: {key}')
print('WBQ_B6_TARGETED_REOPEN_INPUT_GATE PASS')
PY
for path in "$log" "$invocation" "$report"; do
  if [[ -e "$path" ]]; then echo "existing B6 targeted reopen audit artifact prevents duplicate: $path" >&2; exit 4; fi
done
if pgrep -x openroad >/dev/null; then
  echo "OpenROAD already exists; refusing concurrent B6 targeted reopen audit" >&2
  pgrep -a -x openroad >&2 || true
  exit 3
fi

start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
placement_sha="$(sha256sum "$placement" | awk '{print $1}')"
odb_sha="$(sha256sum "$odb" | awk '{print $1}')"
sdc_sha="$(sha256sum "$sdc" | awk '{print $1}')"
tcl_sha="$(sha256sum "$tcl" | awk '{print $1}')"
python3 - "$invocation" "$start" "$$" "$placement" "$placement_sha" "$odb" "$odb_sha" "$sdc" "$sdc_sha" "$tcl" "$tcl_sha" <<'PY'
import json,sys
(path,start,wrapper,placement,placement_sha,odb,odb_sha,sdc,sdc_sha,tcl,tcl_sha)=sys.argv[1:]
payload={
  'schema_version':1,'variant':'B6','stage':'targeted_placement_reopen_audit','status':'STARTED',
  'start_utc':start,'invocation_count':1,'wrapper_pid':int(wrapper),'compute_pid':None,
  'inputs':{
    'placement_manifest':{'path':placement,'sha256':placement_sha},
    'b6_place_odb':{'path':odb,'sha256':odb_sha},'b6_place_sdc':{'path':sdc,'sha256':sdc_sha},
    'audit_tcl':{'path':tcl,'sha256':tcl_sha}},
  'required':{'anchors_locked':2,'outside_fence':0,'unplaced':0,'placement_violations':0}}
with open(path,'x',encoding='utf-8') as stream: json.dump(payload,stream,indent=2); stream.write('\n')
PY
{
  echo "WBQ_B6_TARGETED_REOPEN_START_UTC=$start"
  echo "WBQ_B6_TARGETED_REOPEN_INVOCATION_COUNT=1"
  echo "WBQ_B6_TARGETED_REOPEN_ODB_SHA256=$odb_sha"
  echo "WBQ_B6_TARGETED_REOPEN_SDC_SHA256=$sdc_sha"
  echo "WBQ_B6_TARGETED_REOPEN_TCL_SHA256=$tcl_sha"
} > "$log"
termination_signal=""
compute_pid=""
on_signal() {
  termination_signal="$1"
  echo "WBQ_B6_TARGETED_REOPEN_SIGNAL=$termination_signal" >> "$log"
  if [[ -n "$compute_pid" ]] && kill -0 "$compute_pid" 2>/dev/null; then kill -TERM "$compute_pid"; fi
}
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM
WBQ_B6_PLACE_ODB="$odb" WBQ_B6_PLACE_SDC="$sdc" \
  "$openroad_exe" -exit -no_init -threads 1 -no_splash "$tcl" >> "$log" 2>&1 &
compute_pid="$!"
python3 - "$invocation" "$compute_pid" <<'PY'
import json,pathlib,sys
path=pathlib.Path(sys.argv[1]); value=json.loads(path.read_text()); value['compute_pid']=int(sys.argv[2])
path.write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')
PY
set +e
wait "$compute_pid"
rc=$?
set -e
end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "WBQ_B6_TARGETED_REOPEN_EXIT_CODE=$rc" >> "$log"
echo "WBQ_B6_TARGETED_REOPEN_END_UTC=$end" >> "$log"
python3 - "$report" "$invocation" "$log" "$end" "$rc" "$termination_signal" <<'PY'
import hashlib,json,pathlib,re,sys
(report,invocation,log,end,rc,signal)=sys.argv[1:]
inv=json.load(open(invocation,encoding='utf-8')); text=pathlib.Path(log).read_text(encoding='utf-8',errors='replace')
anchors=re.findall(r'^WBQ_B6_TARGETED_AUDIT_ANCHOR name=\{(.+?)\} origin_dbu=\{(\d+) (\d+)\} orient=\{(\S+)\} status=\{(\S+)\}$',text,re.M)
fence=re.findall(r'^WBQ_B6_TARGETED_AUDIT_FENCES regions=(\d+) grouped=(\d+) outside=(\d+) unplaced=(\d+)$',text,re.M)
violations=re.findall(r'^WBQ_B6_TARGETED_AUDIT_LEGALITY violations=\{(.*)\}$',text,re.M)
passed=(int(rc)==0 and not signal and len(anchors)==2 and all(a[4]=='LOCKED' for a in anchors)
        and bool(fence) and int(fence[-1][0])==4 and int(fence[-1][1])>0 and int(fence[-1][2])==0 and int(fence[-1][3])==0
        and bool(violations) and violations[-1]=='' and 'WBQ_B6_TARGETED_PLACEMENT_REOPEN_AUDIT PASS' in text
        and inv.get('compute_pid') is not None)
def sha(path):
    digest=hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest(); return digest
payload={**inv,'status':'PASS' if passed else 'FAIL','end_utc':end,'exit_code':int(rc),'termination_signal':signal or None,
 'metrics':{'anchors_verified':len(anchors),'anchors':[{'instance':a[0],'origin_dbu':[int(a[1]),int(a[2])],'orientation':a[3],'status':a[4]} for a in anchors],
            'regions':int(fence[-1][0]) if fence else None,'grouped':int(fence[-1][1]) if fence else None,
            'outside_fence':int(fence[-1][2]) if fence else None,'unplaced':int(fence[-1][3]) if fence else None,
            'placement_violations':0 if violations and violations[-1]=='' else None},
 'outputs':{'log':{'path':log,'bytes':pathlib.Path(log).stat().st_size,'sha256':sha(log)}},
 'authorizes':['B6_GLOBAL_ROUTE_AUTHORIZATION'] if passed else [],
 'next_stage':'B6_GLOBAL_ROUTE_AUTHORIZATION' if passed else None}
with open(report,'x',encoding='utf-8') as stream: json.dump(payload,stream,indent=2); stream.write('\n')
PY
trap - INT TERM
test "$rc" -eq 0
grep -q '"status": "PASS"' "$report"
echo "WBQ_B6_TARGETED_PLACEMENT_REOPEN_AUDIT PASS report=$report"
