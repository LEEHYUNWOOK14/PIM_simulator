#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"

report="$root/reports/groot_normalization/quad_local_b8"
physical="$report/physical"
artifacts="${WBQ_B8_ARTIFACT_ROOT:-/dev/shm/wbq_b8_phase6_10/quad_local_b8}"
decision="$report/b8_eco_decision.json"
smoke="$physical/b8_smoke_execution_report.json"
authorization="$report/b8_physical_authorization.json"
b7_manifest="$root/reports/groot_normalization/quad_local_b7/physical/b7_placement_execution_report.json"
b7_rudy="/dev/shm/wbq_b7_phase6_10/quad_local_b7/b7_rudy.odb"
b2_sdc="$orfs_flow/results/sky130hd/normalization_hbm_quad_local_b2/base/3_place.sdc"
post_legalize_odb="$artifacts/b8_post_legalize.odb"
b8_odb="$artifacts/b8_place.odb"
b8_sdc="$artifacts/b8_place.sdc"
log="$physical/b8_place.log"
attempt="$physical/b8_place_invocation.json"
manifest="$physical/b8_placement_execution_report.json"
tcl="$root/verification/groot_normalization/wbq_quad_local_b8_drc_place.tcl"
generic_audit="$root/verification/groot_normalization/audit_wbq_quad_local_placement.tcl"
frozen_a="$root/reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_wbq_v4_control_global_route.odb"
frozen_b="$root/reports/groot_normalization/quad_local_ab/b_quad_local_global_route.odb"
frozen_b2="$root/reports/groot_normalization/quad_local_b2/b2_quad_local_global_route.odb"

mkdir -p "$physical" "$artifacts"
for path in "$decision" "$smoke" "$authorization" "$b7_manifest" "$b7_rudy" "$b2_sdc" "$tcl" "$generic_audit" "$frozen_a" "$frozen_b" "$frozen_b2"; do test -s "$path"; done
for path in "$attempt" "$manifest" "$log" "$post_legalize_odb" "$b8_odb" "$b8_sdc"; do
  if [[ -e "$path" ]]; then echo "B8 placement has already been attempted: $path" >&2; exit 4; fi
done
if pgrep -x openroad >/dev/null; then echo "OpenROAD already exists; refusing concurrent B8 placement" >&2; pgrep -a -x openroad >&2; exit 3; fi
free_kib="$(df -Pk "$artifacts" | awk 'NR==2 {print $4}')"
available_kib="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"
if (( free_kib < 15 * 1024 * 1024 )); then echo "less than 15 GiB free in B8 artifact storage" >&2; exit 5; fi
if (( available_kib < 40 * 1024 * 1024 )); then echo "less than 40 GiB MemAvailable for B8 placement" >&2; exit 6; fi

python3 - "$decision" "$smoke" "$authorization" "$b7_manifest" "$b7_rudy" <<'PY'
import hashlib,json,pathlib,sys
def sha(path):
    d=hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda:f.read(8*1024*1024),b''): d.update(chunk)
    return d.hexdigest()
decision=json.load(open(sys.argv[1],encoding='utf-8'))
smoke=json.load(open(sys.argv[2],encoding='utf-8'))
auth=json.load(open(sys.argv[3],encoding='utf-8'))
b7=json.load(open(sys.argv[4],encoding='utf-8'))
rudy=pathlib.Path(sys.argv[5])
if decision.get('decision')!='SELECT_B8_HIGHER_DRC_PENALTY_ECO' or decision.get('authorizes')!=[]:
    raise SystemExit('B8 one-variable decision is not sealed')
if smoke.get('status')!='PASS' or smoke.get('authorizes')!=['B8_PHYSICAL_AUTHORIZATION']:
    raise SystemExit('B8 smoke is not PASS')
if auth.get('decision')!='PASS' or auth.get('authorizes')!=['B8_PLACEMENT']:
    raise SystemExit('B8 placement is not freshly authorized')
for name,item in auth.get('inputs',{}).items():
    path=pathlib.Path(item['path'])
    if not path.is_file() or sha(path)!=item['sha256']:
        raise SystemExit(f'B8 authorization input hash mismatch: {name}')
if b7.get('status')!='FAIL' or sha(rudy)!=b7.get('checkpoints',{}).get('post_rudy',{}).get('sha256'):
    raise SystemExit('B7 RUDY checkpoint is not sealed')
print('WBQ_B8_PLACEMENT_INPUT_GATE PASS drc_penalty=100')
PY

sha() { sha256sum "$1" | awk '{print $1}'; }
start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; runner_service="${WBQ_RUNNER_SERVICE:-direct-cli}"
decision_sha="$(sha "$decision")"; smoke_sha="$(sha "$smoke")"; auth_sha="$(sha "$authorization")"; b7_manifest_sha="$(sha "$b7_manifest")"
b7_rudy_sha="$(sha "$b7_rudy")"; b2_sdc_sha="$(sha "$b2_sdc")"; tcl_sha="$(sha "$tcl")"; audit_tcl_sha="$(sha "$generic_audit")"
fa="$(sha "$frozen_a")"; fb="$(sha "$frozen_b")"; fb2="$(sha "$frozen_b2")"
[[ "$fa" == 964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad ]]
[[ "$fb" == ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235 ]]
[[ "$fb2" == 2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d ]]
swap_total_kib="$(awk '/SwapTotal:/ {print $2}' /proc/meminfo)"

python3 - "$attempt" "$start" "$$" "$runner_service" "$decision" "$decision_sha" "$smoke" "$smoke_sha" "$authorization" "$auth_sha" "$b7_manifest" "$b7_manifest_sha" "$b7_rudy" "$b7_rudy_sha" "$b2_sdc" "$b2_sdc_sha" "$tcl" "$tcl_sha" "$generic_audit" "$audit_tcl_sha" "$free_kib" "$available_kib" "$swap_total_kib" "$fa" "$fb" "$fb2" <<'PY'
import json,sys
(path,start,wrapper,service,decision,decision_sha,smoke,smoke_sha,auth,auth_sha,b7,b7_sha,rudy,rudy_sha,sdc,sdc_sha,tcl,tcl_sha,audit,audit_sha,free_kib,mem_kib,swap_kib,fa,fb,fb2)=sys.argv[1:]
p={'schema_version':1,'variant':'B8','stage':'higher_drc_penalty_placement','status':'STARTED','start_utc':start,
 'invocation_count':1,'global_route_invocations':0,'service':service,'wrapper_pid':int(wrapper),'launcher_pid':None,'compute_pid':None,'audit_compute_pid':None,
 'policy':{'single_independent_change':'drc_penalty','drc_penalty_before':20,'drc_penalty_after':100,'full_design_diamond':False,
 'locked_anchor_targets':2,'offender_targets':7,'sealed_b7_rudy_checkpoint':True,'post_legalize_checkpoint':True},
 'resources_before':{'artifact_free_kib':int(free_kib),'mem_available_kib':int(mem_kib),'swap_total_kib':int(swap_kib)},
 'inputs':{'decision':{'path':decision,'sha256':decision_sha},'smoke':{'path':smoke,'sha256':smoke_sha},'authorization':{'path':auth,'sha256':auth_sha},
 'b7_placement_report':{'path':b7,'sha256':b7_sha},'b7_rudy_odb':{'path':rudy,'sha256':rudy_sha},'b2_place_sdc':{'path':sdc,'sha256':sdc_sha},
 'placement_tcl':{'path':tcl,'sha256':tcl_sha},'generic_audit_tcl':{'path':audit,'sha256':audit_sha}},
 'protected_hashes_before':{'frozen_A':fa,'B':fb,'B2':fb2},'authorizes':[]}
with open(path,'x',encoding='utf-8') as f: json.dump(p,f,indent=2); f.write('\n')
PY
{
  echo "WBQ_B8_PLACE_START_UTC=$start"
  echo "WBQ_B8_PLACE_INVOCATION_COUNT=1"
  echo "WBQ_B8_PLACE_GLOBAL_ROUTE_INVOCATIONS=0"
  echo "WBQ_B8_PLACE_SERVICE=$runner_service"
  echo "WBQ_B8_PLACE_WRAPPER_PID=$$"
  echo "WBQ_B8_PLACE_SINGLE_CHANGE=drc_penalty"
  echo "WBQ_B8_PLACE_DRC_PENALTY=100"
} > "$log"

launcher_pid=""; compute_pid=""; audit_compute_pid=""; termination_signal=""; finalized=0
on_signal() {
  termination_signal="$1"; echo "WBQ_B8_PLACE_SIGNAL=$termination_signal" >> "$log"
  if [[ -n "$compute_pid" ]] && kill -0 "$compute_pid" 2>/dev/null; then kill -TERM "$compute_pid"; fi
  if [[ -n "$audit_compute_pid" ]] && kill -0 "$audit_compute_pid" 2>/dev/null; then kill -TERM "$audit_compute_pid"; fi
}
write_unexpected_fail() {
  local shell_rc=$?
  if [[ "$finalized" -eq 0 && -s "$attempt" && ! -e "$manifest" ]]; then
    python3 - "$attempt" "$manifest" "$log" "$shell_rc" "$termination_signal" <<'PY'
import hashlib,json,pathlib,sys
attempt,out,log,rc,signal=sys.argv[1:]; p=json.load(open(attempt,encoding='utf-8'))
p.update({'status':'FAIL','end_utc':__import__('datetime').datetime.now(__import__('datetime').timezone.utc).isoformat(),
 'exit_code':int(rc),'termination_signal':signal or None,'failure_class':'interrupted' if signal else 'tool_error','authorizes':[],'next_stage':None,
 'outputs':{'log':{'path':log,'sha256':hashlib.sha256(pathlib.Path(log).read_bytes()).hexdigest()}}})
with open(out,'x',encoding='utf-8') as f: json.dump(p,f,indent=2); f.write('\n')
PY
  fi
}
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM
trap write_unexpected_fail EXIT

export WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd" WBQ_B7_RUDY_ODB="$b7_rudy" WBQ_B2_PLACE_SDC="$b2_sdc"
export WBQ_B8_POST_LEGALIZE_ODB="$post_legalize_odb" WBQ_B8_PLACE_ODB="$b8_odb" WBQ_B8_PLACE_SDC="$b8_sdc"
/usr/bin/time -v "$openroad_exe" -exit -no_init -threads "${NUM_CORES:-16}" -no_splash "$tcl" >> "$log" 2>&1 &
launcher_pid="$!"
for _ in $(seq 1 100); do
  compute_pid="$(pgrep -P "$launcher_pid" -x openroad | head -n 1 || true)"
  [[ -n "$compute_pid" ]] && break
  kill -0 "$launcher_pid" 2>/dev/null || break
  sleep 0.1
done
if [[ -z "$compute_pid" ]]; then echo "WBQ_B8_PLACE_COMPUTE_PID_DISCOVERY_FAIL" >> "$log"; kill -TERM "$launcher_pid" 2>/dev/null || true; fi
python3 - "$attempt" "$launcher_pid" "${compute_pid:-0}" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d['launcher_pid']=int(sys.argv[2]); d['compute_pid']=int(sys.argv[3]) or None; p.write_text(json.dumps(d,indent=2)+'\n')
PY
echo "WBQ_B8_PLACE_LAUNCHER_PID=$launcher_pid" >> "$log"; echo "WBQ_B8_PLACE_COMPUTE_PID=${compute_pid:-NONE}" >> "$log"
set +e; wait "$launcher_pid"; rc=$?; set -e
echo "WBQ_B8_PLACE_EXIT_CODE=$rc" >> "$log"

audit_rc=1
if [[ "$rc" -eq 0 && -s "$b8_odb" && -s "$b8_sdc" ]]; then
  WBQ_QUAD_PLACE_ODB="$b8_odb" WBQ_QUAD_PLACE_SDC="$b8_sdc" \
    "$openroad_exe" -exit -no_init -threads 1 -no_splash "$generic_audit" >> "$log" 2>&1 &
  audit_compute_pid="$!"
  python3 - "$attempt" "$audit_compute_pid" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d['audit_compute_pid']=int(sys.argv[2]); p.write_text(json.dumps(d,indent=2)+'\n')
PY
  set +e; wait "$audit_compute_pid"; audit_rc=$?; set -e
fi
echo "WBQ_B8_PLACE_AUDIT_EXIT_CODE=$audit_rc" >> "$log"
end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; echo "WBQ_B8_PLACE_END_UTC=$end" >> "$log"
item_sha() { [[ -s "$1" ]] && sha "$1" || true; }
post_sha="$(item_sha "$post_legalize_odb")"; odb_sha="$(item_sha "$b8_odb")"; sdc_sha="$(item_sha "$b8_sdc")"
fa_after="$(sha "$frozen_a")"; fb_after="$(sha "$frozen_b")"; fb2_after="$(sha "$frozen_b2")"
free_after_kib="$(df -Pk "$artifacts" | awk 'NR==2 {print $4}')"; mem_after_kib="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"

python3 - "$manifest" "$attempt" "$log" "$end" "$rc" "$audit_rc" "$termination_signal" "$post_legalize_odb" "$post_sha" "$b8_odb" "$odb_sha" "$b8_sdc" "$sdc_sha" "$fa_after" "$fb_after" "$fb2_after" "$free_after_kib" "$mem_after_kib" <<'PY'
import hashlib,json,pathlib,sys
(out,attempt,log,end,rc,audit_rc,signal,post,post_sha,odb,odb_sha,sdc,sdc_sha,fa,fb,fb2,free_kib,mem_kib)=sys.argv[1:]
p=json.load(open(attempt,encoding='utf-8')); text=pathlib.Path(log).read_text(errors='replace')
after={'frozen_A':fa,'B':fb,'B2':fb2}; preserved=after==p['protected_hashes_before']
passed=(int(rc)==0 and int(audit_rc)==0 and not signal and bool(post_sha) and bool(odb_sha) and bool(sdc_sha) and preserved
 and p.get('compute_pid') and p.get('audit_compute_pid') and 'WBQ_B8_DRC_RECOVERY_POLICY max_displacement={1000 1000} site_window=100 row_window=20 drc_penalty=100 full_design_diamond=0' in text
 and 'WBQ_B8_HIGHER_DRC_PLACE PASS' in text and 'WBQ_QUAD_LOCAL_PLACEMENT_AUDIT PASS' in text and 'DPL-0033' not in text)
if passed: failure=None
elif signal: failure='interrupted'
elif 'DPL-0033' in text or 'Overlap check failed' in text: failure='design_legality_failure'
elif int(rc)!=0: failure='tool_error'
else: failure='design_fail'
p.update({'status':'PASS' if passed else 'FAIL','end_utc':end,'exit_code':int(rc),'audit_exit_code':int(audit_rc),'termination_signal':signal or None,
 'failure_class':failure,'protected_hashes_after':after,'protected_artifacts_preserved':preserved,
 'resources_after':{'artifact_free_kib':int(free_kib),'mem_available_kib':int(mem_kib)},
 'checkpoints':{'post_legalize':{'path':post,'sha256':post_sha}},
 'outputs':{'b8_place_odb':{'path':odb,'sha256':odb_sha},'b8_place_sdc':{'path':sdc,'sha256':sdc_sha},
 'log':{'path':log,'sha256':hashlib.sha256(pathlib.Path(log).read_bytes()).hexdigest()}},
 'runtime_policy_marker':'PASS' if 'drc_penalty=100 full_design_diamond=0' in text else 'FAIL',
 'placement_legality_and_fence_audit':'PASS' if passed else 'FAIL',
 'authorizes':['B8_TARGETED_PLACEMENT_REOPEN_AUDIT'] if passed else [],
 'next_stage':'B8_TARGETED_PLACEMENT_REOPEN_AUDIT' if passed else None})
with open(out,'x',encoding='utf-8') as f: json.dump(p,f,indent=2); f.write('\n')
with open(attempt,'w',encoding='utf-8') as f: json.dump(p,f,indent=2); f.write('\n')
PY
finalized=1
trap - EXIT INT TERM
test "$rc" -eq 0; test "$audit_rc" -eq 0; grep -q '"status": "PASS"' "$manifest"
echo "WBQ_B8_PLACEMENT PASS report=$manifest"
