#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"

report="$root/reports/groot_normalization/quad_local_b7"
physical="$report/physical"
artifacts="${WBQ_B7_ARTIFACT_ROOT:-/dev/shm/wbq_b7_phase6_10/quad_local_b7}"
decision="$report/b7_eco_decision.json"
b2_result="$orfs_flow/results/sky130hd/normalization_hbm_quad_local_b2/base"
b2_odb="$b2_result/3_place.odb"
b2_sdc="$b2_result/3_place.sdc"
smoke_odb="$artifacts/b7_smoke.odb"
smoke_tcl="$root/verification/groot_normalization/wbq_quad_local_b7_phi_smoke.tcl"
audit_tcl="$root/verification/groot_normalization/audit_wbq_b7_phi_smoke.tcl"
placement_tcl="$root/verification/groot_normalization/wbq_quad_local_b7_phi_place.tcl"
log="$physical/b7_smoke.log"
invocation="$physical/b7_smoke_invocation.json"
manifest="$physical/b7_smoke_execution_report.json"
frozen_a="$root/reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_wbq_v4_control_global_route.odb"
frozen_b="$root/reports/groot_normalization/quad_local_ab/b_quad_local_global_route.odb"
frozen_b2="$root/reports/groot_normalization/quad_local_b2/b2_quad_local_global_route.odb"

mkdir -p "$physical" "$artifacts"
for path in "$decision" "$b2_odb" "$b2_sdc" "$smoke_tcl" "$audit_tcl" "$placement_tcl" "$frozen_a" "$frozen_b" "$frozen_b2"; do test -s "$path"; done
for path in "$smoke_odb" "$log" "$invocation" "$manifest"; do
  if [[ -e "$path" ]]; then echo "existing B7 smoke artifact prevents duplicate: $path" >&2; exit 4; fi
done
if pgrep -x openroad >/dev/null; then echo "OpenROAD already exists; refusing concurrent B7 smoke" >&2; pgrep -a -x openroad >&2; exit 3; fi
free_kib="$(df -Pk "$artifacts" | awk 'NR==2 {print $4}')"
if (( free_kib < 6 * 1024 * 1024 )); then echo "less than 6 GiB free for B7 smoke checkpoint" >&2; exit 5; fi

python3 - "$decision" "$placement_tcl" <<'PY'
import json,re,sys
decision=json.load(open(sys.argv[1],encoding='utf-8'))
text=open(sys.argv[2],encoding='utf-8').read()
if decision.get('decision') != 'SELECT_B7_LOWER_MAX_PHI_ECO' or decision.get('authorizes') != []:
    raise SystemExit('B7 recovery decision is not fail-closed')
if text.count('global_placement \\\n') != 1 or '-min_phi_coef 0.95 -max_phi_coef 1.01' not in text:
    raise SystemExit('B7 placement source does not contain the one-variable phi policy')
if '-max_phi_coef 1.05' in text or '-use_diamond_legalizer' in text:
    raise SystemExit('B7 placement source retains a failed policy')
print('WBQ_B7_SMOKE_STATIC_POLICY PASS max_phi_coef=1.01')
PY

start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
runner_service="${WBQ_RUNNER_SERVICE:-direct-cli}"
sha() { sha256sum "$1" | awk '{print $1}'; }
decision_sha="$(sha "$decision")"; b2_odb_sha="$(sha "$b2_odb")"; b2_sdc_sha="$(sha "$b2_sdc")"
smoke_tcl_sha="$(sha "$smoke_tcl")"; audit_tcl_sha="$(sha "$audit_tcl")"; placement_tcl_sha="$(sha "$placement_tcl")"
fa="$(sha "$frozen_a")"; fb="$(sha "$frozen_b")"; fb2="$(sha "$frozen_b2")"
[[ "$fa" == 964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad ]]
[[ "$fb" == ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235 ]]
[[ "$fb2" == 2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d ]]

python3 - "$invocation" "$start" "$$" "$runner_service" "$decision" "$decision_sha" "$b2_odb" "$b2_odb_sha" "$b2_sdc" "$b2_sdc_sha" "$smoke_tcl" "$smoke_tcl_sha" "$audit_tcl" "$audit_tcl_sha" "$placement_tcl" "$placement_tcl_sha" "$fa" "$fb" "$fb2" <<'PY'
import json,sys
(path,start,wrapper,service,decision,decision_sha,odb,odb_sha,sdc,sdc_sha,smoke,smoke_sha,audit,audit_sha,place,place_sha,fa,fb,fb2)=sys.argv[1:]
payload={'schema_version':1,'variant':'B7','stage':'input_reopen_checkpoint_smoke','status':'STARTED','start_utc':start,
 'invocation_count':1,'service':service,'wrapper_pid':int(wrapper),'compute_pid':None,'audit_compute_pid':None,
 'inputs':{'decision':{'path':decision,'sha256':decision_sha},'b2_place_odb':{'path':odb,'sha256':odb_sha},
 'b2_place_sdc':{'path':sdc,'sha256':sdc_sha},'smoke_tcl':{'path':smoke,'sha256':smoke_sha},
 'audit_tcl':{'path':audit,'sha256':audit_sha},'placement_tcl':{'path':place,'sha256':place_sha}},
 'protected_hashes_before':{'frozen_A':fa,'B':fb,'B2':fb2},'authorizes':[]}
with open(path,'x',encoding='utf-8') as f: json.dump(payload,f,indent=2); f.write('\n')
PY
{
  echo "WBQ_B7_SMOKE_START_UTC=$start"
  echo "WBQ_B7_SMOKE_INVOCATION_COUNT=1"
  echo "WBQ_B7_SMOKE_SERVICE=$runner_service"
  echo "WBQ_B7_SMOKE_WRAPPER_PID=$$"
  echo "WBQ_B7_SMOKE_STATIC_POLICY max_phi_coef=1.01"
} > "$log"

compute_pid=""; audit_compute_pid=""; termination_signal=""
on_signal() {
  termination_signal="$1"
  echo "WBQ_B7_SMOKE_SIGNAL=$termination_signal" >> "$log"
  if [[ -n "$compute_pid" ]] && kill -0 "$compute_pid" 2>/dev/null; then kill -TERM "$compute_pid"; fi
  if [[ -n "$audit_compute_pid" ]] && kill -0 "$audit_compute_pid" 2>/dev/null; then kill -TERM "$audit_compute_pid"; fi
}
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM

export WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd"
export WBQ_B2_PLACE_ODB="$b2_odb" WBQ_B2_PLACE_SDC="$b2_sdc" WBQ_B7_SMOKE_ODB="$smoke_odb"
"$openroad_exe" -exit -no_init -threads 1 -no_splash "$smoke_tcl" >> "$log" 2>&1 &
compute_pid="$!"
python3 - "$invocation" "$compute_pid" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d['compute_pid']=int(sys.argv[2]); p.write_text(json.dumps(d,indent=2)+'\n')
PY
set +e; wait "$compute_pid"; rc=$?; set -e
echo "WBQ_B7_SMOKE_WRITE_EXIT_CODE=$rc" >> "$log"
if [[ "$rc" -eq 0 && -s "$smoke_odb" ]]; then
  "$openroad_exe" -exit -no_init -threads 1 -no_splash "$audit_tcl" >> "$log" 2>&1 &
  audit_compute_pid="$!"
  python3 - "$invocation" "$audit_compute_pid" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d['audit_compute_pid']=int(sys.argv[2]); p.write_text(json.dumps(d,indent=2)+'\n')
PY
  set +e; wait "$audit_compute_pid"; audit_rc=$?; set -e
else
  audit_rc=1
fi
echo "WBQ_B7_SMOKE_REOPEN_EXIT_CODE=$audit_rc" >> "$log"
end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; echo "WBQ_B7_SMOKE_END_UTC=$end" >> "$log"
smoke_odb_sha="$([[ -s "$smoke_odb" ]] && sha "$smoke_odb" || true)"
fa_after="$(sha "$frozen_a")"; fb_after="$(sha "$frozen_b")"; fb2_after="$(sha "$frozen_b2")"

python3 - "$manifest" "$invocation" "$log" "$smoke_odb" "$smoke_odb_sha" "$end" "$rc" "$audit_rc" "$termination_signal" "$fa_after" "$fb_after" "$fb2_after" <<'PY'
import hashlib,json,pathlib,sys
(out,inv_path,log_path,odb,odb_sha,end,rc,audit_rc,signal,fa,fb,fb2)=sys.argv[1:]
inv=json.load(open(inv_path,encoding='utf-8')); text=pathlib.Path(log_path).read_text(errors='replace')
after={'frozen_A':fa,'B':fb,'B2':fb2}; preserved=after==inv['protected_hashes_before']
passed=(int(rc)==0 and int(audit_rc)==0 and not signal and bool(odb_sha) and preserved
 and 'WBQ_B7_SMOKE_INPUT_REOPEN_AND_CHECKPOINT PASS' in text
 and 'WBQ_B7_SMOKE_INDEPENDENT_REOPEN PASS anchors=2' in text
 and inv.get('compute_pid') and inv.get('audit_compute_pid'))
payload={**inv,'status':'PASS' if passed else 'FAIL','end_utc':end,'exit_code':int(rc),'audit_exit_code':int(audit_rc),
 'termination_signal':signal or None,'protected_hashes_after':after,'protected_artifacts_preserved':preserved,
 'outputs':{'smoke_odb':{'path':odb,'sha256':odb_sha},'log':{'path':log_path,'sha256':hashlib.sha256(pathlib.Path(log_path).read_bytes()).hexdigest()}},
 'checks':{'syntax_and_static_policy':'PASS','input_reopen':'PASS' if 'WBQ_B7_SMOKE_INPUT_REOPEN_AND_CHECKPOINT PASS' in text else 'FAIL',
 'target_objects':'PASS' if text.count('WBQ_B7_SMOKE_ANCHOR name=')==2 else 'FAIL','checkpoint_write':'PASS' if odb_sha else 'FAIL',
 'independent_checkpoint_reopen':'PASS' if 'WBQ_B7_SMOKE_INDEPENDENT_REOPEN PASS anchors=2' in text else 'FAIL'},
 'authorizes':['B7_PHYSICAL_AUTHORIZATION'] if passed else [],'next_stage':'B7_PHYSICAL_AUTHORIZATION' if passed else None}
with open(out,'x',encoding='utf-8') as f: json.dump(payload,f,indent=2); f.write('\n')
with open(inv_path,'w',encoding='utf-8') as f: json.dump(payload,f,indent=2); f.write('\n')
PY
trap - INT TERM
test "$rc" -eq 0; test "$audit_rc" -eq 0; grep -q '"status": "PASS"' "$manifest"
echo "WBQ_B7_SMOKE PASS report=$manifest"
