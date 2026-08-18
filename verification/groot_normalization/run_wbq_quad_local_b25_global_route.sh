#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"

report="$root/reports/groot_normalization/quad_local_b25"
physical="$report/physical"
artifacts="${WBQ_B25_ROUTE_ARTIFACT_ROOT:-/dev/shm/wbq_b25_phase6_10/quad_local_b25_route}"
result="$orfs_flow/results/sky130hd/normalization_hbm_quad_local_b25/base"
placement="$physical/b25_placement_execution_report.json"
smoke="$physical/b25_route_pin_smoke_execution_report.json"
authorization="$report/b25_global_route_authorization.json"
place_odb="$result/3_place.odb"
place_sdc="$result/3_place.sdc"
log="$physical/b25_global_route.log"
guide="$artifacts/b25_quad_local.route_guide"
congestion="$artifacts/b25_quad_local.congestion.rpt"
routed_odb="$artifacts/b25_quad_local_global_route.odb"
routed_sdc="$artifacts/b25_quad_local_global_route.sdc"
attempt="$physical/b25_global_route_invocation.json"
manifest="$physical/b25_global_route_execution_report.json"
analysis_json="$report/b25_residual_congestion_analysis.json"
analysis_md="$report/b25_residual_congestion_analysis.md"
tcl="$root/verification/groot_normalization/wbq_quad_local_b25_global_route.tcl"
parser="$root/tools/analyze_variant_residual_congestion.py"
strict_gate="$root/tools/decide_b25_phase6_strict_gate.py"
snapshot_tool="$root/tools/capture_openroad_stage_snapshot.py"
compare_tool="$root/tools/compare_openroad_stage_snapshots.py"
monitor_tool="$root/tools/monitor_openroad_service.py"
runner="$root/verification/groot_normalization/run_wbq_quad_local_b25_global_route.sh"
runner_service="${WBQ_RUNNER_SERVICE:-wbq-b25-global-route.service}"
frozen_a="$root/reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_wbq_v4_control_global_route.odb"
frozen_b="$root/reports/groot_normalization/quad_local_ab/b_quad_local_global_route.odb"
frozen_b2="$root/reports/groot_normalization/quad_local_b2/b2_quad_local_global_route.odb"
mkdir -p "$physical" "$artifacts"

for path in "$placement" "$smoke" "$authorization" "$place_odb" "$place_sdc" "$tcl" "$parser" "$strict_gate" "$snapshot_tool" "$compare_tool" "$monitor_tool" "$runner" "$frozen_a" "$frozen_b" "$frozen_b2"; do test -s "$path"; done
for path in "$attempt" "$manifest" "$log" "$guide" "$congestion" "$routed_odb" "$routed_sdc" "$analysis_json" "$analysis_md"; do
  [[ ! -e "$path" ]] || { echo "B25 global route already attempted; refusing duplicate ($path)" >&2; exit 4; }
done
if pgrep -x openroad >/dev/null; then echo "OpenROAD exists; refusing concurrent B25 route" >&2; pgrep -a -x openroad >&2; exit 3; fi
free_kib="$(df -Pk "$artifacts" | awk 'NR==2 {print $4}')"
available_kib="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
(( free_kib >= 20 * 1024 * 1024 )) || { echo "less than 20 GiB free for B25 route" >&2; exit 5; }
(( available_kib >= 32 * 1024 * 1024 )) || { echo "less than 32 GiB MemAvailable for B25 route" >&2; exit 6; }

python3 - "$placement" "$smoke" "$authorization" "$place_odb" "$place_sdc" "$runner" "$tcl" "$parser" "$strict_gate" "$snapshot_tool" "$compare_tool" "$monitor_tool" <<'PY'
import hashlib,json,pathlib,sys
def sha(path):
 d=hashlib.sha256()
 with path.open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):d.update(b)
 return d.hexdigest()
p=json.load(open(sys.argv[1]));smoke=json.load(open(sys.argv[2]));auth=json.load(open(sys.argv[3]))
if p.get('status')!='PASS' or p.get('authorizes')!=['B25_SINGLE_GLOBAL_ROUTE']:raise SystemExit('B25 placement is not PASS')
if smoke.get('status')!='PASS' or smoke.get('authorizes')!=['B25_GLOBAL_ROUTE_AUTHORIZATION']:raise SystemExit('B25 smoke is not PASS')
if auth.get('decision')!='PASS' or auth.get('authorizes')!=['B25_SINGLE_GLOBAL_ROUTE']:raise SystemExit('B25 route authorization is not PASS')
for key,text in (('b25_place_odb',sys.argv[4]),('b25_place_sdc',sys.argv[5])):
 if sha(pathlib.Path(text))!=p['outputs'][key]['sha256'] or sha(pathlib.Path(text))!=auth['inputs'][key]['sha256']:raise SystemExit(f'B25 place hash mismatch: {key}')
for key,text in (('route_runner',sys.argv[6]),('route_tcl',sys.argv[7]),('direct_numeric_parser',sys.argv[8]),('strict_phase6_gate',sys.argv[9]),('silence_snapshot_tool',sys.argv[10]),('silence_compare_tool',sys.argv[11]),('heartbeat_monitor',sys.argv[12])):
 if sha(pathlib.Path(text))!=auth['inputs'][key]['sha256']:raise SystemExit(f'B25 authorization hash mismatch: {key}')
if sha(pathlib.Path(sys.argv[1]))!=auth['inputs']['placement_execution_report']['sha256'] or sha(pathlib.Path(sys.argv[2]))!=auth['inputs']['route_pin_smoke_report']['sha256']:raise SystemExit('B25 report hash mismatch')
print('WBQ_B25_SINGLE_GLOBAL_ROUTE_AUTHORIZATION PASS')
PY

sha(){ sha256sum "$1" | awk '{print $1}'; }
frozen_a_before="$(sha "$frozen_a")"; frozen_b_before="$(sha "$frozen_b")"; frozen_b2_before="$(sha "$frozen_b2")"
[[ "$frozen_a_before" == 964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad ]]
[[ "$frozen_b_before" == ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235 ]]
[[ "$frozen_b2_before" == 2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d ]]
start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
python3 - "$attempt" "$start" "$runner_service" "$$" "$placement" "$smoke" "$authorization" "$place_odb" "$place_sdc" "$runner" "$tcl" "$parser" "$strict_gate" "$snapshot_tool" "$compare_tool" "$monitor_tool" "$free_kib" "$available_kib" "$frozen_a_before" "$frozen_b_before" "$frozen_b2_before" <<'PY'
import hashlib,json,sys
out,start,service,wrapper,*rest=sys.argv[1:];paths=rest[:12];free_kib,mem_kib,fa,fb,fb2=rest[12:]
names=('placement_manifest','route_pin_smoke_report','route_authorization','b25_place_odb','b25_place_sdc','route_runner','route_tcl','direct_numeric_parser','strict_phase6_gate','silence_snapshot_tool','silence_compare_tool','heartbeat_monitor')
def ev(p):
 h=hashlib.sha256()
 with open(p,'rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return {'path':p,'sha256':h.hexdigest()}
d={'schema_version':2,'variant':'B25','stage':'single_global_route','status':'STARTED','start_utc':start,'invocation_count':1,'global_route_invocations':1,'cugr_congestion_iterations':1,'service':service,'wrapper_pid':int(wrapper),'launcher_pid':None,'compute_pid':None,'command':'openroad -exit -no_init -threads 1 -no_splash wbq_quad_local_b25_global_route.tcl','resources_at_start':{'artifact_free_kib':int(free_kib),'mem_available_kib':int(mem_kib)},'inputs':{n:ev(p) for n,p in zip(names,paths)},'protected_hashes_before':{'frozen_A':fa,'B':fb,'B2':fb2},'authorizes':[]}
with open(out,'x') as f:json.dump(d,f,indent=2);f.write('\n')
PY
{
  echo "WBQ_B25_GLOBAL_ROUTE_START_UTC=$start"
  echo "WBQ_B25_GLOBAL_ROUTE_INVOCATION_COUNT=1"
  echo "WBQ_B25_CUGR_CONGESTION_ITERATIONS=1"
  echo "WBQ_B25_GLOBAL_ROUTE_SERVICE=$runner_service"
} > "$log"

compute_pid=""; termination_signal=""; finalized=0
on_signal(){ termination_signal="$1"; [[ -z "$compute_pid" ]] || kill -TERM "$compute_pid" 2>/dev/null || true; }
write_fail_closed_manifest(){
  local shell_rc=$?
  if [[ "$finalized" -eq 0 && -s "$attempt" && ! -e "$manifest" ]]; then
    python3 - "$attempt" "$manifest" "$log" "$shell_rc" "$termination_signal" <<'PY'
import hashlib,json,pathlib,sys
inv,out,log,rc,sig=sys.argv[1:];d=json.load(open(inv));p=pathlib.Path(log)
d.update({'status':'FAIL','end_utc':__import__('datetime').datetime.now(__import__('datetime').timezone.utc).isoformat(),'exit_code':int(rc),'termination_signal':sig or None,'failure_class':'interrupted' if sig else 'tool_error','outputs':{'log':{'path':log,'sha256':hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else None}},'authorizes':[],'next_stage':None})
with open(out,'x') as f:json.dump(d,f,indent=2);f.write('\n')
PY
  fi
}
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM
trap write_fail_closed_manifest EXIT

export WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd"
export WBQ_B25_PLACE_ODB="$place_odb" WBQ_B25_PLACE_SDC="$place_sdc"
export WBQ_B25_ROUTE_OUTPUT_ROOT="$artifacts" WBQ_B25_CUGR_CONGESTION_ITERATIONS=1
"$openroad_exe" -exit -no_init -threads 1 -no_splash "$tcl" >> "$log" 2>&1 &
compute_pid="$!"
python3 - "$attempt" "$compute_pid" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);d=json.loads(p.read_text());d['launcher_pid']=int(sys.argv[2]);d['compute_pid']=int(sys.argv[2]);p.write_text(json.dumps(d,indent=2)+'\n')
PY
set +e; wait "$compute_pid"; route_rc=$?; set -e
end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "WBQ_B25_GLOBAL_ROUTE_EXIT_CODE=$route_rc" >> "$log"

analysis_rc=1
if [[ "$route_rc" -eq 0 ]] && grep -q "WBQ_B25_SINGLE_GLOBAL_ROUTE PASS" "$log" && [[ -s "$guide" && -e "$congestion" && -s "$routed_odb" && -s "$routed_sdc" ]]; then
  set +e
  python3 "$parser" --variant B25 --pass-token "WBQ_B25_SINGLE_GLOBAL_ROUTE PASS" --cugr-iterations 1 \
    --report "$congestion" --log "$log" --guide "$guide" --odb "$routed_odb" --sdc "$routed_sdc" \
    --invocation "$attempt" --output-json "$analysis_json" --output-md "$analysis_md" \
    --max-hotspots-in-output 500 --max-windows-in-output 0
  analysis_rc=$?
  set -e
fi
frozen_a_after="$(sha "$frozen_a")"; frozen_b_after="$(sha "$frozen_b")"; frozen_b2_after="$(sha "$frozen_b2")"
python3 - "$manifest" "$attempt" "$end" "$route_rc" "$analysis_rc" "$termination_signal" "$log" "$guide" "$congestion" "$routed_odb" "$routed_sdc" "$analysis_json" "$analysis_md" "$frozen_a_after" "$frozen_b_after" "$frozen_b2_after" <<'PY'
import hashlib,json,pathlib,sys
out,inv,end,rrc,arc,sig,log,guide,congestion,odb,sdc,analysis,analysis_md,fa,fb,fb2=sys.argv[1:];d=json.load(open(inv));text=pathlib.Path(log).read_text(errors='replace')
def ev(p):
 q=pathlib.Path(p)
 if not q.is_file():return {'path':p,'exists':False,'bytes':0,'sha256':None}
 h=hashlib.sha256()
 with q.open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return {'path':p,'exists':True,'bytes':q.stat().st_size,'sha256':h.hexdigest()}
after={'frozen_A':fa,'B':fb,'B2':fb2};preserved=after==d['protected_hashes_before']
outputs={'log':ev(log),'route_guide':ev(guide),'congestion_report':ev(congestion),'routed_odb':ev(odb),'routed_sdc':ev(sdc),'numeric_analysis':ev(analysis),'numeric_analysis_md':ev(analysis_md)}
passed=int(rrc)==0 and int(arc)==0 and not sig and d.get('compute_pid') and 'WBQ_B25_SINGLE_GLOBAL_ROUTE PASS' in text and all(v['exists'] for k,v in outputs.items() if k!='congestion_report') and outputs['congestion_report']['exists'] and preserved
d.update({'status':'PASS' if passed else 'FAIL','end_utc':end,'exit_code':int(rrc),'analysis_exit_code':int(arc),'termination_signal':sig or None,'failure_class':None if passed else ('interrupted' if sig else 'tool_error'),'protected_hashes_after':after,'protected_artifacts_preserved':preserved,'outputs':outputs,'authorizes':['B25_STRICT_PHASE6_EVALUATION'] if passed else [],'next_stage':'B25_STRICT_PHASE6_EVALUATION' if passed else None})
with open(out,'x') as f:json.dump(d,f,indent=2);f.write('\n')
pathlib.Path(inv).write_text(json.dumps(d,indent=2)+'\n')
PY
finalized=1
trap - EXIT INT TERM
test "$route_rc" -eq 0; test "$analysis_rc" -eq 0; grep -q '"status": "PASS"' "$manifest"
echo "WBQ_B25_SINGLE_GLOBAL_ROUTE PASS report=$manifest"
