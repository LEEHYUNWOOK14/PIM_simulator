#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"

report="$root/reports/groot_normalization/quad_local_b9"
physical="$report/physical"
artifacts="${WBQ_B9_ARTIFACT_ROOT:-/dev/shm/wbq_b9_phase6_10/quad_local_b9}"
decision="$report/b9_eco_decision.json"
b7_manifest="$root/reports/groot_normalization/quad_local_b7/physical/b7_placement_execution_report.json"
b7_rudy="/dev/shm/wbq_b7_phase6_10/quad_local_b7/b7_rudy.odb"
b2_sdc="$orfs_flow/results/sky130hd/normalization_hbm_quad_local_b2/base/3_place.sdc"
smoke_odb="$artifacts/b9_smoke.odb"
smoke_tcl="$root/verification/groot_normalization/wbq_quad_local_b9_anchor_smoke.tcl"
audit_tcl="$root/verification/groot_normalization/audit_wbq_b9_anchor_smoke.tcl"
placement_tcl="$root/verification/groot_normalization/wbq_quad_local_b9_anchor_place.tcl"
log="$physical/b9_smoke.log"
invocation="$physical/b9_smoke_invocation.json"
manifest="$physical/b9_smoke_execution_report.json"
frozen_a="$root/reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_wbq_v4_control_global_route.odb"
frozen_b="$root/reports/groot_normalization/quad_local_ab/b_quad_local_global_route.odb"
frozen_b2="$root/reports/groot_normalization/quad_local_b2/b2_quad_local_global_route.odb"

mkdir -p "$physical" "$artifacts"
for path in "$decision" "$b7_manifest" "$b7_rudy" "$b2_sdc" "$smoke_tcl" "$audit_tcl" "$placement_tcl" "$frozen_a" "$frozen_b" "$frozen_b2"; do test -s "$path"; done
for path in "$smoke_odb" "$log" "$invocation" "$manifest"; do
  if [[ -e "$path" ]]; then echo "existing B9 smoke artifact prevents duplicate: $path" >&2; exit 4; fi
done
if pgrep -x openroad >/dev/null; then echo "OpenROAD already exists; refusing concurrent B9 smoke" >&2; pgrep -a -x openroad >&2; exit 3; fi
free_kib="$(df -Pk "$artifacts" | awk 'NR==2 {print $4}')"
if (( free_kib < 6 * 1024 * 1024 )); then echo "less than 6 GiB free for B9 smoke checkpoint" >&2; exit 5; fi

python3 - "$decision" "$b7_manifest" "$b7_rudy" "$placement_tcl" <<'PY'
import hashlib,json,pathlib,re,sys
decision=json.load(open(sys.argv[1],encoding='utf-8'))
b7=json.load(open(sys.argv[2],encoding='utf-8'))
rudy=pathlib.Path(sys.argv[3]); text=pathlib.Path(sys.argv[4]).read_text()
d=hashlib.sha256()
with rudy.open('rb') as f:
    for chunk in iter(lambda:f.read(8*1024*1024),b''): d.update(chunk)
if decision.get('decision')!='SELECT_B9_SEVEN_ADDITIONAL_ANCHORS_ECO' or decision.get('authorizes')!=[]:
    raise SystemExit('B9 recovery decision is not fail-closed')
if b7.get('status')!='FAIL' or b7.get('global_route_invocations')!=0:
    raise SystemExit('B7 failure is not sealed pre-route')
if d.hexdigest()!=b7.get('checkpoints',{}).get('post_rudy',{}).get('sha256'):
    raise SystemExit('B7 RUDY checkpoint hash mismatch')
if text.count('detailed_placement \\\n')!=1 or '-drc_penalty 100' not in text or 'anchor_targets=9 added_targets=7' not in text:
    raise SystemExit('B9 placement source lacks the nine-anchor policy')
if 'global_placement' in text or '-drc_penalty 20' in text or '-use_diamond_legalizer' in text:
    raise SystemExit('B9 placement source retains a failed or forbidden policy')
print('WBQ_B9_SMOKE_STATIC_POLICY PASS anchor_targets=9 drc_penalty=100')
PY

sha() { sha256sum "$1" | awk '{print $1}'; }
start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; runner_service="${WBQ_RUNNER_SERVICE:-direct-cli-b9-smoke}"
decision_sha="$(sha "$decision")"; b7_manifest_sha="$(sha "$b7_manifest")"; b7_rudy_sha="$(sha "$b7_rudy")"; b2_sdc_sha="$(sha "$b2_sdc")"
smoke_tcl_sha="$(sha "$smoke_tcl")"; audit_tcl_sha="$(sha "$audit_tcl")"; placement_tcl_sha="$(sha "$placement_tcl")"
fa="$(sha "$frozen_a")"; fb="$(sha "$frozen_b")"; fb2="$(sha "$frozen_b2")"
[[ "$fa" == 964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad ]]
[[ "$fb" == ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235 ]]
[[ "$fb2" == 2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d ]]

python3 - "$invocation" "$start" "$$" "$runner_service" "$decision" "$decision_sha" "$b7_manifest" "$b7_manifest_sha" "$b7_rudy" "$b7_rudy_sha" "$b2_sdc" "$b2_sdc_sha" "$smoke_tcl" "$smoke_tcl_sha" "$audit_tcl" "$audit_tcl_sha" "$placement_tcl" "$placement_tcl_sha" "$fa" "$fb" "$fb2" <<'PY'
import json,sys
(path,start,wrapper,service,decision,decision_sha,b7,b7_sha,rudy,rudy_sha,sdc,sdc_sha,smoke,smoke_sha,audit,audit_sha,place,place_sha,fa,fb,fb2)=sys.argv[1:]
p={'schema_version':1,'variant':'B9','stage':'b7_rudy_reopen_checkpoint_smoke','status':'STARTED','start_utc':start,
 'invocation_count':1,'service':service,'wrapper_pid':int(wrapper),'compute_pid':None,'audit_compute_pid':None,
 'inputs':{'decision':{'path':decision,'sha256':decision_sha},'b7_placement_report':{'path':b7,'sha256':b7_sha},
 'b7_rudy_odb':{'path':rudy,'sha256':rudy_sha},'b2_place_sdc':{'path':sdc,'sha256':sdc_sha},
 'smoke_tcl':{'path':smoke,'sha256':smoke_sha},'audit_tcl':{'path':audit,'sha256':audit_sha},'placement_tcl':{'path':place,'sha256':place_sha}},
 'protected_hashes_before':{'frozen_A':fa,'B':fb,'B2':fb2},'authorizes':[]}
with open(path,'x',encoding='utf-8') as f: json.dump(p,f,indent=2); f.write('\n')
PY
{
  echo "WBQ_B9_SMOKE_START_UTC=$start"
  echo "WBQ_B9_SMOKE_INVOCATION_COUNT=1"
  echo "WBQ_B9_SMOKE_SERVICE=$runner_service"
  echo "WBQ_B9_SMOKE_WRAPPER_PID=$$"
  echo "WBQ_B9_SMOKE_STATIC_POLICY anchor_targets=9 drc_penalty=100"
} > "$log"

compute_pid=""; audit_compute_pid=""; termination_signal=""
on_signal() {
  termination_signal="$1"; echo "WBQ_B9_SMOKE_SIGNAL=$termination_signal" >> "$log"
  if [[ -n "$compute_pid" ]] && kill -0 "$compute_pid" 2>/dev/null; then kill -TERM "$compute_pid"; fi
  if [[ -n "$audit_compute_pid" ]] && kill -0 "$audit_compute_pid" 2>/dev/null; then kill -TERM "$audit_compute_pid"; fi
}
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM
export WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd" WBQ_B7_RUDY_ODB="$b7_rudy" WBQ_B2_PLACE_SDC="$b2_sdc" WBQ_B9_SMOKE_ODB="$smoke_odb"
"$openroad_exe" -exit -no_init -threads 1 -no_splash "$smoke_tcl" >> "$log" 2>&1 &
compute_pid="$!"
python3 - "$invocation" "$compute_pid" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d['compute_pid']=int(sys.argv[2]); p.write_text(json.dumps(d,indent=2)+'\n')
PY
set +e; wait "$compute_pid"; rc=$?; set -e
audit_rc=1
if [[ "$rc" -eq 0 && -s "$smoke_odb" ]]; then
  "$openroad_exe" -exit -no_init -threads 1 -no_splash "$audit_tcl" >> "$log" 2>&1 &
  audit_compute_pid="$!"
  python3 - "$invocation" "$audit_compute_pid" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d['audit_compute_pid']=int(sys.argv[2]); p.write_text(json.dumps(d,indent=2)+'\n')
PY
  set +e; wait "$audit_compute_pid"; audit_rc=$?; set -e
fi
end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; echo "WBQ_B9_SMOKE_EXIT_CODE=$rc" >> "$log"; echo "WBQ_B9_SMOKE_AUDIT_EXIT_CODE=$audit_rc" >> "$log"; echo "WBQ_B9_SMOKE_END_UTC=$end" >> "$log"
smoke_sha=""; [[ -s "$smoke_odb" ]] && smoke_sha="$(sha "$smoke_odb")"
fa_after="$(sha "$frozen_a")"; fb_after="$(sha "$frozen_b")"; fb2_after="$(sha "$frozen_b2")"

python3 - "$manifest" "$invocation" "$log" "$end" "$rc" "$audit_rc" "$termination_signal" "$smoke_odb" "$smoke_sha" "$fa_after" "$fb_after" "$fb2_after" <<'PY'
import hashlib,json,pathlib,sys
(out,inv,log,end,rc,audit_rc,signal,odb,odb_sha,fa,fb,fb2)=sys.argv[1:]
p=json.load(open(inv,encoding='utf-8')); text=pathlib.Path(log).read_text(errors='replace')
after={'frozen_A':fa,'B':fb,'B2':fb2}; preserved=after==p['protected_hashes_before']
passed=(int(rc)==0 and int(audit_rc)==0 and not signal and bool(odb_sha) and preserved and p.get('compute_pid') and p.get('audit_compute_pid')
 and 'WBQ_B9_SMOKE_INPUT_REOPEN_AND_CHECKPOINT PASS anchors=9 offenders=7' in text
 and 'WBQ_B9_SMOKE_INDEPENDENT_REOPEN PASS anchors=9 offenders=7 fences=4' in text)
p.update({'status':'PASS' if passed else 'FAIL','end_utc':end,'exit_code':int(rc),'audit_exit_code':int(audit_rc),
 'termination_signal':signal or None,'protected_hashes_after':after,'protected_artifacts_preserved':preserved,
 'outputs':{'smoke_odb':{'path':odb,'sha256':odb_sha},'log':{'path':log,'sha256':hashlib.sha256(pathlib.Path(log).read_bytes()).hexdigest()}},
 'checks':{'syntax_and_static_policy':'PASS','input_reopen':'PASS' if 'WBQ_B9_SMOKE_INPUT_REOPEN_AND_CHECKPOINT PASS' in text else 'FAIL',
 'target_objects':'PASS' if text.count('WBQ_B9_SMOKE_OFFENDER name=')==7 and text.count('WBQ_B9_SMOKE_ANCHOR name=')==9 else 'FAIL',
 'checkpoint_write':'PASS' if odb_sha else 'FAIL','independent_checkpoint_reopen':'PASS' if 'WBQ_B9_SMOKE_INDEPENDENT_REOPEN PASS' in text else 'FAIL'},
 'authorizes':['B9_PHYSICAL_AUTHORIZATION'] if passed else [],'next_stage':'B9_PHYSICAL_AUTHORIZATION' if passed else None})
with open(out,'x',encoding='utf-8') as f: json.dump(p,f,indent=2); f.write('\n')
with open(inv,'w',encoding='utf-8') as f: json.dump(p,f,indent=2); f.write('\n')
PY
trap - INT TERM
test "$rc" -eq 0; test "$audit_rc" -eq 0; grep -q '"status": "PASS"' "$manifest"
echo "WBQ_B9_SMOKE PASS report=$manifest"
