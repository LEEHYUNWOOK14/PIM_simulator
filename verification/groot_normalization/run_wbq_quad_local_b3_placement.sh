#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"

report="$root/reports/groot_normalization/quad_local_b3"
physical="$report/physical"
artifacts="${WBQ_B3_ARTIFACT_ROOT:-/dev/shm/wbq_b3_phase6_10/quad_local_b3}"
cheap="$report/cheap_gate_manifest.json"
authorization="$report/b3_physical_authorization.json"
b2_result="$orfs_flow/results/sky130hd/normalization_hbm_quad_local_b2/base"
b2_odb="$b2_result/3_place.odb"
b2_sdc="$b2_result/3_place.sdc"
b3_odb="$artifacts/b3_place.odb"
b3_sdc="$artifacts/b3_place.sdc"
log="$physical/b3_place.log"
attempt="$physical/b3_place_invocation.json"
manifest="$physical/b3_placement_execution_report.json"
tcl="$root/verification/groot_normalization/wbq_quad_local_b3_incremental_place.tcl"

mkdir -p "$physical" "$artifacts"
for path in "$cheap" "$authorization" "$b2_odb" "$b2_sdc"; do
  test -s "$path"
done

python3 - "$cheap" "$authorization" <<'PY'
import json, sys
cheap = json.load(open(sys.argv[1], encoding="utf-8"))
auth = json.load(open(sys.argv[2], encoding="utf-8"))
if cheap.get("overall_result") != "PASS" or len(cheap.get("gates", [])) != 9:
    raise SystemExit("B3 cheap gate is not 9/9 PASS")
if auth.get("decision") != "PASS" or "B3_PLACEMENT" not in auth.get("authorizes", []):
    raise SystemExit("B3 placement is not explicitly authorized")
print("WBQ_B3_PLACEMENT_AUTHORIZATION PASS")
PY

# A B3 physical attempt is single-shot.  Even a failed invocation leaves this
# marker behind so the same variant cannot silently be retried.
if [[ -e "$attempt" || -e "$log" || -e "$b3_odb" || -e "$b3_sdc" ]]; then
  echo "B3 placement has already been attempted; refusing duplicate" >&2
  exit 4
fi
if pgrep -x openroad >/dev/null; then
  echo "an OpenROAD process already exists; refusing concurrent B3 placement" >&2
  pgrep -a -x openroad >&2 || true
  exit 3
fi

start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cheap_sha="$(sha256sum "$cheap" | awk '{print $1}')"
auth_sha="$(sha256sum "$authorization" | awk '{print $1}')"
b2_odb_sha="$(sha256sum "$b2_odb" | awk '{print $1}')"
b2_sdc_sha="$(sha256sum "$b2_sdc" | awk '{print $1}')"
python3 - "$attempt" "$start" "$cheap_sha" "$auth_sha" "$b2_odb" "$b2_odb_sha" "$b2_sdc" "$b2_sdc_sha" <<'PY'
import json, sys
path, start, cheap_sha, auth_sha, b2_odb, b2_odb_sha, b2_sdc, b2_sdc_sha = sys.argv[1:]
payload = {
    "schema_version": 1,
    "variant": "B3",
    "stage": "incremental_placement",
    "invocation_count": 1,
    "start_utc": start,
    "status": "STARTED",
    "artifact_storage": "variant-only tmpfs; volatile; hashes and evidence manifests are persisted in the repository",
    "cheap_gate_sha256": cheap_sha,
    "authorization_sha256": auth_sha,
    "immutable_inputs": {
        "b2_place_odb": {"path": b2_odb, "sha256": b2_odb_sha},
        "b2_place_sdc": {"path": b2_sdc, "sha256": b2_sdc_sha},
    },
}
with open(path, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2)
    stream.write("\n")
PY

{
  echo "WBQ_B3_PLACE_START_UTC=$start"
  echo "WBQ_B3_PLACE_INVOCATION_COUNT=1"
  echo "WBQ_B3_PLACE_B2_ODB_SHA256=$b2_odb_sha"
  echo "WBQ_B3_PLACE_B2_SDC_SHA256=$b2_sdc_sha"
} > "$log"
export WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd"
export WBQ_B2_PLACE_ODB="$b2_odb"
export WBQ_B2_PLACE_SDC="$b2_sdc"
export WBQ_B3_PLACE_ODB="$b3_odb"
export WBQ_B3_PLACE_SDC="$b3_sdc"
set +e
/usr/bin/time -v "$openroad_exe" -exit -no_init -threads "${NUM_CORES:-16}" -no_splash "$tcl" >> "$log" 2>&1
rc=$?
set -e
echo "WBQ_B3_PLACE_EXIT_CODE=$rc" >> "$log"

if [[ "$rc" -eq 0 && -s "$b3_odb" && -s "$b3_sdc" ]]; then
  WBQ_QUAD_PLACE_ODB="$b3_odb" WBQ_QUAD_PLACE_SDC="$b3_sdc" \
    "$openroad_exe" -no_init -exit \
    "$root/verification/groot_normalization/audit_wbq_quad_local_placement.tcl" \
    >> "$log" 2>&1 || rc=$?
fi
if ! grep -q "WBQ_QUAD_LOCAL_PLACEMENT_AUDIT PASS" "$log"; then
  rc=1
fi
end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "WBQ_B3_PLACE_END_UTC=$end" >> "$log"
if [[ "$rc" -eq 0 ]]; then
  echo "WBQ_B3_PLACEMENT PASS odb=$b3_odb" | tee -a "$log"
fi

b3_odb_sha=""
b3_sdc_sha=""
[[ -s "$b3_odb" ]] && b3_odb_sha="$(sha256sum "$b3_odb" | awk '{print $1}')"
[[ -s "$b3_sdc" ]] && b3_sdc_sha="$(sha256sum "$b3_sdc" | awk '{print $1}')"
python3 - "$attempt" "$manifest" "$end" "$rc" "$b3_odb" "$b3_odb_sha" "$b3_sdc" "$b3_sdc_sha" "$log" <<'PY'
import hashlib, json, pathlib, sys
attempt, manifest, end, rc, odb, odb_sha, sdc, sdc_sha, log = sys.argv[1:]
data = json.load(open(attempt, encoding="utf-8"))
passed = int(rc) == 0 and bool(odb_sha) and bool(sdc_sha)
data.update({
    "end_utc": end,
    "exit_code": int(rc),
    "status": "PASS" if passed else "FAIL",
    "outputs": {
        "b3_place_odb": {"path": odb, "sha256": odb_sha},
        "b3_place_sdc": {"path": sdc, "sha256": sdc_sha},
        "log": {"path": log, "sha256": hashlib.sha256(pathlib.Path(log).read_bytes()).hexdigest()},
    },
    "placement_legality_and_fence_audit": "PASS" if passed else "FAIL",
    "authorizes": ["B3_SINGLE_GLOBAL_ROUTE"] if passed else [],
    "next_stage": "B3_SINGLE_GLOBAL_ROUTE" if passed else None,
})
with open(manifest, "x", encoding="utf-8") as stream:
    json.dump(data, stream, indent=2)
    stream.write("\n")
with open(attempt, "w", encoding="utf-8") as stream:
    json.dump(data, stream, indent=2)
    stream.write("\n")
PY

test "$rc" -eq 0
echo "B3 placement report: $manifest"
