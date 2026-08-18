#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"

report="$root/reports/groot_normalization/quad_local_b5"
physical="$report/physical"
artifacts="${WBQ_B5_ARTIFACT_ROOT:-/dev/shm/wbq_b5_phase6_10/quad_local_b5}"
cheap="$report/cheap_gate_manifest.json"
authorization="$report/b5_physical_authorization.json"
b2_result="$orfs_flow/results/sky130hd/normalization_hbm_quad_local_b2/base"
b2_odb="$b2_result/3_place.odb"
b2_sdc="$b2_result/3_place.sdc"
frozen_a="$root/reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_wbq_v4_control_global_route.odb"
frozen_b="$root/reports/groot_normalization/quad_local_ab/b_quad_local_global_route.odb"
frozen_b2="$root/reports/groot_normalization/quad_local_b2/b2_quad_local_global_route.odb"
b5_odb="$artifacts/b5_place.odb"
b5_sdc="$artifacts/b5_place.sdc"
log="$physical/b5_place.log"
attempt="$physical/b5_place_invocation.json"
manifest="$physical/b5_placement_execution_report.json"
tcl="$root/verification/groot_normalization/wbq_quad_local_b5_routability_place.tcl"

mkdir -p "$physical" "$artifacts"
for path in "$cheap" "$authorization" "$b2_odb" "$b2_sdc" "$frozen_a" "$frozen_b" "$frozen_b2"; do
  test -s "$path"
done

python3 - "$cheap" "$authorization" <<'PY'
import json, sys
cheap = json.load(open(sys.argv[1], encoding="utf-8"))
auth = json.load(open(sys.argv[2], encoding="utf-8"))
if cheap.get("overall_result") != "PASS" or len(cheap.get("gates", [])) != 9:
    raise SystemExit("B5 cheap gate is not 9/9 PASS")
if auth.get("decision") != "PASS" or "B5_PLACEMENT" not in auth.get("authorizes", []):
    raise SystemExit("B5 placement is not explicitly authorized")
print("WBQ_B5_PLACEMENT_AUTHORIZATION PASS")
PY

# Placement compute is single-shot.  Keep all evidence, including a failure.
if [[ -e "$attempt" || -e "$log" || -e "$b5_odb" || -e "$b5_sdc" ]]; then
  echo "B5 placement has already been attempted; refusing duplicate" >&2
  exit 4
fi
if pgrep -x openroad >/dev/null; then
  echo "an OpenROAD process already exists; refusing concurrent B5 placement" >&2
  pgrep -a -x openroad >&2 || true
  exit 3
fi

start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cheap_sha="$(sha256sum "$cheap" | awk '{print $1}')"
auth_sha="$(sha256sum "$authorization" | awk '{print $1}')"
b2_odb_sha="$(sha256sum "$b2_odb" | awk '{print $1}')"
b2_sdc_sha="$(sha256sum "$b2_sdc" | awk '{print $1}')"
frozen_a_before="$(sha256sum "$frozen_a" | awk '{print $1}')"
frozen_b_before="$(sha256sum "$frozen_b" | awk '{print $1}')"
frozen_b2_before="$(sha256sum "$frozen_b2" | awk '{print $1}')"
[[ "$frozen_a_before" == 964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad ]]
[[ "$frozen_b_before" == ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235 ]]
[[ "$frozen_b2_before" == 2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d ]]

python3 - "$attempt" "$start" "$cheap_sha" "$auth_sha" "$b2_odb" "$b2_odb_sha" "$b2_sdc" "$b2_sdc_sha" \
  "$frozen_a" "$frozen_a_before" "$frozen_b" "$frozen_b_before" "$frozen_b2" "$frozen_b2_before" <<'PY'
import json, sys
(path, start, cheap_sha, auth_sha, b2_odb, b2_odb_sha, b2_sdc, b2_sdc_sha,
 frozen_a, frozen_a_sha, frozen_b, frozen_b_sha, frozen_b2, frozen_b2_sha) = sys.argv[1:]
payload = {
    "schema_version": 1,
    "variant": "B5",
    "stage": "rudy_routability_driven_placement_with_diamond_legalizer",
    "invocation_count": 1,
    "audit_invocation_count": 0,
    "start_utc": start,
    "status": "STARTED",
    "global_route_invocations": 0,
    "routability_estimator": "RUDY",
    "legalizer": "diamond",
    "artifact_storage": "variant-only tmpfs; volatile; hashes and evidence manifests are persisted in the repository",
    "cheap_gate_sha256": cheap_sha,
    "authorization_sha256": auth_sha,
    "immutable_inputs": {
        "b2_place_odb": {"path": b2_odb, "sha256": b2_odb_sha},
        "b2_place_sdc": {"path": b2_sdc, "sha256": b2_sdc_sha},
    },
    "protected_artifacts_before": {
        "frozen_a_routed_odb": {"path": frozen_a, "sha256": frozen_a_sha},
        "frozen_b_routed_odb": {"path": frozen_b, "sha256": frozen_b_sha},
        "frozen_b2_routed_odb": {"path": frozen_b2, "sha256": frozen_b2_sha},
    },
}
with open(path, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2); stream.write("\n")
PY

{
  echo "WBQ_B5_PLACE_START_UTC=$start"
  echo "WBQ_B5_PLACE_INVOCATION_COUNT=1"
  echo "WBQ_B5_PLACE_GLOBAL_ROUTE_INVOCATIONS=0"
  echo "WBQ_B5_PLACE_ESTIMATOR=RUDY"
  echo "WBQ_B5_PLACE_LEGALIZER=diamond"
  echo "WBQ_B5_PLACE_B2_ODB_SHA256=$b2_odb_sha"
  echo "WBQ_B5_PLACE_B2_SDC_SHA256=$b2_sdc_sha"
} > "$log"
export WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd"
export WBQ_B2_PLACE_ODB="$b2_odb"
export WBQ_B2_PLACE_SDC="$b2_sdc"
export WBQ_B5_PLACE_ODB="$b5_odb"
export WBQ_B5_PLACE_SDC="$b5_sdc"
set +e
/usr/bin/time -v "$openroad_exe" -exit -no_init -threads "${NUM_CORES:-16}" -no_splash "$tcl" >> "$log" 2>&1
rc=$?
set -e
echo "WBQ_B5_PLACE_EXIT_CODE=$rc" >> "$log"

audit_invocations=0
if [[ "$rc" -eq 0 && -s "$b5_odb" && -s "$b5_sdc" ]]; then
  audit_invocations=1
  WBQ_QUAD_PLACE_ODB="$b5_odb" WBQ_QUAD_PLACE_SDC="$b5_sdc" \
    "$openroad_exe" -no_init -exit \
    "$root/verification/groot_normalization/audit_wbq_quad_local_placement.tcl" \
    >> "$log" 2>&1 || rc=$?
fi
if ! grep -q "WBQ_QUAD_LOCAL_PLACEMENT_AUDIT PASS" "$log"; then rc=1; fi
end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "WBQ_B5_PLACE_AUDIT_INVOCATION_COUNT=$audit_invocations" >> "$log"
echo "WBQ_B5_PLACE_END_UTC=$end" >> "$log"
if [[ "$rc" -eq 0 ]]; then echo "WBQ_B5_PLACEMENT PASS odb=$b5_odb" | tee -a "$log"; fi

b5_odb_sha=""; b5_sdc_sha=""
[[ -s "$b5_odb" ]] && b5_odb_sha="$(sha256sum "$b5_odb" | awk '{print $1}')"
[[ -s "$b5_sdc" ]] && b5_sdc_sha="$(sha256sum "$b5_sdc" | awk '{print $1}')"
frozen_a_after="$(sha256sum "$frozen_a" | awk '{print $1}')"
frozen_b_after="$(sha256sum "$frozen_b" | awk '{print $1}')"
frozen_b2_after="$(sha256sum "$frozen_b2" | awk '{print $1}')"
if [[ "$frozen_a_after" != "$frozen_a_before" || "$frozen_b_after" != "$frozen_b_before" || "$frozen_b2_after" != "$frozen_b2_before" ]]; then rc=1; fi

python3 - "$attempt" "$manifest" "$end" "$rc" "$audit_invocations" "$b5_odb" "$b5_odb_sha" "$b5_sdc" "$b5_sdc_sha" "$log" \
  "$frozen_a_after" "$frozen_b_after" "$frozen_b2_after" <<'PY'
import hashlib, json, pathlib, sys
(attempt, manifest, end, rc, audit_count, odb, odb_sha, sdc, sdc_sha, log,
 frozen_a, frozen_b, frozen_b2) = sys.argv[1:]
data = json.load(open(attempt, encoding="utf-8"))
before = data["protected_artifacts_before"]
preserved = (
    before["frozen_a_routed_odb"]["sha256"] == frozen_a
    and before["frozen_b_routed_odb"]["sha256"] == frozen_b
    and before["frozen_b2_routed_odb"]["sha256"] == frozen_b2
)
passed = int(rc) == 0 and bool(odb_sha) and bool(sdc_sha) and preserved
data.update({
    "end_utc": end,
    "exit_code": int(rc),
    "audit_invocation_count": int(audit_count),
    "status": "PASS" if passed else "FAIL",
    "outputs": {
        "b5_place_odb": {"path": odb, "sha256": odb_sha},
        "b5_place_sdc": {"path": sdc, "sha256": sdc_sha},
        "log": {"path": log, "sha256": hashlib.sha256(pathlib.Path(log).read_bytes()).hexdigest()},
    },
    "placement_legality_and_fence_audit": "PASS" if passed else "FAIL",
    "protected_artifacts_after": {
        "frozen_a_routed_odb": {"path": before["frozen_a_routed_odb"]["path"], "sha256": frozen_a},
        "frozen_b_routed_odb": {"path": before["frozen_b_routed_odb"]["path"], "sha256": frozen_b},
        "frozen_b2_routed_odb": {"path": before["frozen_b2_routed_odb"]["path"], "sha256": frozen_b2},
    },
    "protected_artifacts_preserved": preserved,
    "authorizes": ["B5_SINGLE_GLOBAL_ROUTE"] if passed else [],
    "next_stage": "B5_SINGLE_GLOBAL_ROUTE" if passed else None,
})
with open(manifest, "x", encoding="utf-8") as stream:
    json.dump(data, stream, indent=2); stream.write("\n")
with open(attempt, "w", encoding="utf-8") as stream:
    json.dump(data, stream, indent=2); stream.write("\n")
PY

test "$rc" -eq 0
echo "B5 placement report: $manifest"
