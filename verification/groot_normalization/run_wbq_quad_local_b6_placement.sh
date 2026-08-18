#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"

report="$root/reports/groot_normalization/quad_local_b6"
physical="$report/physical"
artifacts="${WBQ_B6_ARTIFACT_ROOT:-/dev/shm/wbq_b6_phase6_10/quad_local_b6}"
decision="$report/b6_eco_decision.json"
authorization="$report/b6_physical_authorization.json"
b2_result="$orfs_flow/results/sky130hd/normalization_hbm_quad_local_b2/base"
b2_odb="$b2_result/3_place.odb"
b2_sdc="$b2_result/3_place.sdc"
rudy_odb="$artifacts/b6_rudy.odb"
post_legalize_odb="$artifacts/b6_post_legalize.odb"
b6_odb="$artifacts/b6_place.odb"
b6_sdc="$artifacts/b6_place.sdc"
log="$physical/b6_place.log"
attempt="$physical/b6_place_invocation.json"
manifest="$physical/b6_placement_execution_report.json"
tcl="$root/verification/groot_normalization/wbq_quad_local_b6_targeted_place.tcl"
frozen_a="$root/reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_wbq_v4_control_global_route.odb"
frozen_b="$root/reports/groot_normalization/quad_local_ab/b_quad_local_global_route.odb"
frozen_b2="$root/reports/groot_normalization/quad_local_b2/b2_quad_local_global_route.odb"

mkdir -p "$physical" "$artifacts"
for path in "$decision" "$authorization" "$b2_odb" "$b2_sdc" "$frozen_a" "$frozen_b" "$frozen_b2"; do test -s "$path"; done
python3 - "$decision" "$authorization" <<'PY'
import json, sys
decision=json.load(open(sys.argv[1], encoding="utf-8"))
auth=json.load(open(sys.argv[2], encoding="utf-8"))
if decision.get("decision") != "SELECT_B6_TARGETED_ANCHOR_LOCK_ECO":
    raise SystemExit("B6 ECO is not selected")
if auth.get("decision") != "PASS" or "B6_PLACEMENT" not in auth.get("authorizes", []):
    raise SystemExit("B6 placement is not authorized")
print("WBQ_B6_PLACEMENT_AUTHORIZATION PASS")
PY

for path in "$attempt" "$manifest" "$log" "$rudy_odb" "$post_legalize_odb" "$b6_odb" "$b6_sdc"; do
  if [[ -e "$path" ]]; then echo "B6 placement has already been attempted: $path" >&2; exit 4; fi
done
if pgrep -x openroad >/dev/null; then echo "OpenROAD already exists; refusing concurrent B6 placement" >&2; pgrep -a -x openroad >&2; exit 3; fi
free_kib="$(df -Pk "$artifacts" | awk 'NR==2 {print $4}')"
if (( free_kib < 20 * 1024 * 1024 )); then echo "less than 20 GiB free in B6 artifact storage" >&2; exit 5; fi

start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
decision_sha="$(sha256sum "$decision" | awk '{print $1}')"
auth_sha="$(sha256sum "$authorization" | awk '{print $1}')"
b2_odb_sha="$(sha256sum "$b2_odb" | awk '{print $1}')"
b2_sdc_sha="$(sha256sum "$b2_sdc" | awk '{print $1}')"
frozen_a_before="$(sha256sum "$frozen_a" | awk '{print $1}')"
frozen_b_before="$(sha256sum "$frozen_b" | awk '{print $1}')"
frozen_b2_before="$(sha256sum "$frozen_b2" | awk '{print $1}')"
[[ "$frozen_a_before" == 964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad ]]
[[ "$frozen_b_before" == ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235 ]]
[[ "$frozen_b2_before" == 2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d ]]

python3 - "$attempt" "$start" "$decision_sha" "$auth_sha" "$b2_odb" "$b2_odb_sha" "$b2_sdc" "$b2_sdc_sha" "$frozen_a_before" "$frozen_b_before" "$frozen_b2_before" <<'PY'
import json, sys
(path,start,decision_sha,auth_sha,b2_odb,b2_odb_sha,b2_sdc,b2_sdc_sha,fa,fb,fb2)=sys.argv[1:]
payload={"schema_version":1,"variant":"B6","stage":"targeted_anchor_lock_placement","status":"STARTED","invocation_count":1,"global_route_invocations":0,"start_utc":start,
"policy":{"full_design_diamond":False,"locked_anchor_targets":2,"post_rudy_checkpoint":True,"post_legalize_checkpoint":True},
"decision_sha256":decision_sha,"authorization_sha256":auth_sha,
"immutable_inputs":{"b2_place_odb":{"path":b2_odb,"sha256":b2_odb_sha},"b2_place_sdc":{"path":b2_sdc,"sha256":b2_sdc_sha}},
"protected_hashes_before":{"frozen_A":fa,"B":fb,"B2":fb2}}
with open(path,"x",encoding="utf-8") as f: json.dump(payload,f,indent=2); f.write("\n")
PY

{
  echo "WBQ_B6_PLACE_START_UTC=$start"
  echo "WBQ_B6_PLACE_INVOCATION_COUNT=1"
  echo "WBQ_B6_PLACE_GLOBAL_ROUTE_INVOCATIONS=0"
  echo "WBQ_B6_PLACE_FULL_DESIGN_DIAMOND=0"
  echo "WBQ_B6_PLACE_LOCKED_ANCHOR_TARGETS=2"
} > "$log"

export WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd"
export WBQ_B2_PLACE_ODB="$b2_odb"
export WBQ_B2_PLACE_SDC="$b2_sdc"
export WBQ_B6_RUDY_ODB="$rudy_odb"
export WBQ_B6_POST_LEGALIZE_ODB="$post_legalize_odb"
export WBQ_B6_PLACE_ODB="$b6_odb"
export WBQ_B6_PLACE_SDC="$b6_sdc"
set +e
/usr/bin/time -v "$openroad_exe" -exit -no_init -threads "${NUM_CORES:-16}" -no_splash "$tcl" >> "$log" 2>&1
rc=$?
set -e
echo "WBQ_B6_PLACE_EXIT_CODE=$rc" >> "$log"

audit_count=0
if [[ "$rc" -eq 0 && -s "$b6_odb" && -s "$b6_sdc" ]]; then
  audit_count=1
  WBQ_QUAD_PLACE_ODB="$b6_odb" WBQ_QUAD_PLACE_SDC="$b6_sdc" \
    "$openroad_exe" -no_init -exit "$root/verification/groot_normalization/audit_wbq_quad_local_placement.tcl" >> "$log" 2>&1 || rc=$?
fi
if ! grep -q "WBQ_QUAD_LOCAL_PLACEMENT_AUDIT PASS" "$log"; then rc=1; fi
end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "WBQ_B6_PLACE_AUDIT_INVOCATION_COUNT=$audit_count" >> "$log"
echo "WBQ_B6_PLACE_END_UTC=$end" >> "$log"

item_sha() { [[ -s "$1" ]] && sha256sum "$1" | awk '{print $1}' || true; }
rudy_sha="$(item_sha "$rudy_odb")"
post_sha="$(item_sha "$post_legalize_odb")"
b6_odb_sha="$(item_sha "$b6_odb")"
b6_sdc_sha="$(item_sha "$b6_sdc")"
frozen_a_after="$(sha256sum "$frozen_a" | awk '{print $1}')"
frozen_b_after="$(sha256sum "$frozen_b" | awk '{print $1}')"
frozen_b2_after="$(sha256sum "$frozen_b2" | awk '{print $1}')"
[[ "$frozen_a_after" == "$frozen_a_before" && "$frozen_b_after" == "$frozen_b_before" && "$frozen_b2_after" == "$frozen_b2_before" ]] || rc=1

python3 - "$attempt" "$manifest" "$end" "$rc" "$audit_count" "$rudy_odb" "$rudy_sha" "$post_legalize_odb" "$post_sha" "$b6_odb" "$b6_odb_sha" "$b6_sdc" "$b6_sdc_sha" "$log" "$frozen_a_after" "$frozen_b_after" "$frozen_b2_after" <<'PY'
import hashlib,json,pathlib,sys
(attempt,manifest,end,rc,audit,rudy,rudy_sha,post,post_sha,odb,odb_sha,sdc,sdc_sha,log,fa,fb,fb2)=sys.argv[1:]
data=json.load(open(attempt,encoding="utf-8")); before=data["protected_hashes_before"]
after={"frozen_A":fa,"B":fb,"B2":fb2}; preserved=after==before
passed=int(rc)==0 and bool(odb_sha) and bool(sdc_sha) and preserved
data.update({"end_utc":end,"exit_code":int(rc),"audit_invocation_count":int(audit),"status":"PASS" if passed else "FAIL",
"checkpoints":{"post_rudy":{"path":rudy,"sha256":rudy_sha},"post_legalize":{"path":post,"sha256":post_sha}},
"outputs":{"b6_place_odb":{"path":odb,"sha256":odb_sha},"b6_place_sdc":{"path":sdc,"sha256":sdc_sha},"log":{"path":log,"sha256":hashlib.sha256(pathlib.Path(log).read_bytes()).hexdigest()}},
"placement_legality_and_fence_audit":"PASS" if passed else "FAIL","protected_hashes_after":after,"protected_artifacts_preserved":preserved,
"authorizes":["B6_SINGLE_GLOBAL_ROUTE"] if passed else [],"next_stage":"B6_SINGLE_GLOBAL_ROUTE" if passed else None})
with open(manifest,"x",encoding="utf-8") as f: json.dump(data,f,indent=2); f.write("\n")
with open(attempt,"w",encoding="utf-8") as f: json.dump(data,f,indent=2); f.write("\n")
PY

test "$rc" -eq 0
echo "WBQ_B6_PLACEMENT PASS report=$manifest"
