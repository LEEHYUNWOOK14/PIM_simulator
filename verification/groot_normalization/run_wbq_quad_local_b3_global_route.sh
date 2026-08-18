#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"

report="$root/reports/groot_normalization/quad_local_b3"
physical="$report/physical"
artifacts="${WBQ_B3_ARTIFACT_ROOT:-/dev/shm/wbq_b3_phase6_10/quad_local_b3}"
placement="$physical/b3_placement_execution_report.json"
place_odb="$artifacts/b3_place.odb"
place_sdc="$artifacts/b3_place.sdc"
log="$physical/b3_global_route.log"
guide="$artifacts/b3_quad_local.route_guide"
congestion="$artifacts/b3_quad_local.congestion.rpt"
routed_odb="$artifacts/b3_quad_local_global_route.odb"
routed_sdc="$artifacts/b3_quad_local_global_route.sdc"
attempt="$physical/b3_global_route_invocation.json"
manifest="$physical/b3_global_route_execution_report.json"
analysis_json="$report/b3_residual_congestion_analysis.json"
analysis_md="$report/b3_residual_congestion_analysis.md"
tcl="$root/verification/groot_normalization/wbq_quad_local_b3_global_route.tcl"

mkdir -p "$physical" "$artifacts"
for path in "$placement" "$place_odb" "$place_sdc"; do
  test -s "$path"
done
python3 - "$placement" "$place_odb" "$place_sdc" <<'PY'
import hashlib, json, pathlib, sys
report = json.load(open(sys.argv[1], encoding="utf-8"))
if report.get("status") != "PASS" or report.get("placement_legality_and_fence_audit") != "PASS":
    raise SystemExit("B3 placement gate is not PASS")
if "B3_SINGLE_GLOBAL_ROUTE" not in report.get("authorizes", []):
    raise SystemExit("B3 placement does not authorize one global-route invocation")
for key, path_text in (("b3_place_odb", sys.argv[2]), ("b3_place_sdc", sys.argv[3])):
    path = pathlib.Path(path_text)
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    actual = digest.hexdigest()
    if actual != report["outputs"][key]["sha256"]:
        raise SystemExit(f"B3 placement artifact hash mismatch: {key}")
print("WBQ_B3_SINGLE_GLOBAL_ROUTE_AUTHORIZATION PASS")
PY

# The marker and every route output are immutable evidence that this variant
# has consumed its sole global-route allowance, even when OpenROAD fails.
for path in "$attempt" "$manifest" "$log" "$guide" "$congestion" "$routed_odb" "$routed_sdc" "$analysis_json" "$analysis_md"; do
  if [[ -e "$path" ]]; then
    echo "B3 global route has already been attempted; refusing duplicate ($path)" >&2
    exit 4
  fi
done
if pgrep -x openroad >/dev/null; then
  echo "an OpenROAD process already exists; refusing concurrent B3 global route" >&2
  pgrep -a -x openroad >&2 || true
  exit 3
fi
free_kib="$(df -Pk "$artifacts" | awk 'NR==2 {print $4}')"
if (( free_kib < 8 * 1024 * 1024 )); then
  echo "less than 8 GiB free; refusing to start the single B3 route attempt" >&2
  exit 5
fi

frozen_a="$root/reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_wbq_v4_control_global_route.odb"
frozen_b="$root/reports/groot_normalization/quad_local_ab/b_quad_local_global_route.odb"
frozen_b2="$root/reports/groot_normalization/quad_local_b2/b2_quad_local_global_route.odb"
frozen_a_sha="$(sha256sum "$frozen_a" | awk '{print $1}')"
frozen_b_sha="$(sha256sum "$frozen_b" | awk '{print $1}')"
frozen_b2_sha="$(sha256sum "$frozen_b2" | awk '{print $1}')"
[[ "$frozen_a_sha" == 964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad ]]
[[ "$frozen_b_sha" == ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235 ]]
[[ "$frozen_b2_sha" == 2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d ]]

start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
place_manifest_sha="$(sha256sum "$placement" | awk '{print $1}')"
place_odb_sha="$(sha256sum "$place_odb" | awk '{print $1}')"
place_sdc_sha="$(sha256sum "$place_sdc" | awk '{print $1}')"
python3 - "$attempt" "$start" "$placement" "$place_manifest_sha" "$place_odb" "$place_odb_sha" "$place_sdc" "$place_sdc_sha" "$frozen_a_sha" "$frozen_b_sha" "$frozen_b2_sha" <<'PY'
import json, sys
(path, start, placement, placement_sha, odb, odb_sha, sdc, sdc_sha,
 frozen_a_sha, frozen_b_sha, frozen_b2_sha) = sys.argv[1:]
payload = {
    "schema_version": 1,
    "variant": "B3",
    "stage": "global_route",
    "status_at_creation": "STARTED",
    "invocation_count": 1,
    "cugr_congestion_iterations": 10,
    "start_utc": start,
    "command": "openroad -exit -no_init -threads 1 -no_splash wbq_quad_local_b3_global_route.tcl",
    "artifact_storage": "variant-only tmpfs; volatile; hashes and evidence manifests are persisted in the repository",
    "inputs": {
        "placement_manifest": {"path": placement, "sha256": placement_sha},
        "b3_place_odb": {"path": odb, "sha256": odb_sha},
        "b3_place_sdc": {"path": sdc, "sha256": sdc_sha},
    },
    "protected_hashes_before": {"frozen_A": frozen_a_sha, "B": frozen_b_sha, "B2": frozen_b2_sha},
}
with open(path, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2)
    stream.write("\n")
PY

{
  echo "WBQ_B3_GLOBAL_ROUTE_START_UTC=$start"
  echo "WBQ_B3_GLOBAL_ROUTE_INVOCATION_COUNT=1"
  echo "WBQ_B3_CUGR_CONGESTION_ITERATIONS=10"
  echo "WBQ_B3_GLOBAL_ROUTE_PLACE_ODB_SHA256=$place_odb_sha"
  echo "WBQ_B3_GLOBAL_ROUTE_PLACE_SDC_SHA256=$place_sdc_sha"
} > "$log"
export WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd"
export WBQ_B3_PLACE_ODB="$place_odb"
export WBQ_B3_PLACE_SDC="$place_sdc"
export WBQ_B3_ROUTE_OUTPUT_ROOT="$artifacts"
export WBQ_B3_CUGR_CONGESTION_ITERATIONS=10
set +e
/usr/bin/time -v "$openroad_exe" -exit -no_init -threads 1 -no_splash "$tcl" >> "$log" 2>&1
route_rc=$?
set -e
end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "WBQ_B3_GLOBAL_ROUTE_EXIT_CODE=$route_rc" >> "$log"
echo "WBQ_B3_GLOBAL_ROUTE_END_UTC=$end" >> "$log"

analysis_rc=1
if [[ "$route_rc" -eq 0 ]] && grep -q "WBQ_B3_SINGLE_GLOBAL_ROUTE PASS" "$log" \
    && [[ -s "$guide" && -e "$congestion" && -s "$routed_odb" && -s "$routed_sdc" ]]; then
  set +e
  python3 tools/analyze_variant_residual_congestion.py \
    --variant B3 --report "$congestion" --log "$log" --guide "$guide" \
    --odb "$routed_odb" --sdc "$routed_sdc" --invocation "$attempt" \
    --output-json "$analysis_json" --output-md "$analysis_md"
  analysis_rc=$?
  set -e
fi

python3 - "$manifest" "$attempt" "$end" "$route_rc" "$analysis_rc" "$log" "$guide" "$congestion" "$routed_odb" "$routed_sdc" "$analysis_json" <<'PY'
import hashlib, json, pathlib, sys
(manifest, attempt, end, route_rc, analysis_rc, log, guide, congestion,
 odb, sdc, analysis) = sys.argv[1:]
def item(path_text):
    path = pathlib.Path(path_text)
    digest = None
    if path.exists():
        value = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
                value.update(chunk)
        digest = value.hexdigest()
    return {
        "path": str(path),
        "exists": path.exists(),
        "bytes": path.stat().st_size if path.exists() else 0,
        "sha256": digest,
    }
attempt_data = json.load(open(attempt, encoding="utf-8"))
passed = int(route_rc) == 0 and int(analysis_rc) == 0
payload = {
    "schema_version": 1,
    "variant": "B3",
    "stage": "global_route",
    "status": "PASS" if passed else "FAIL",
    "invocation_count": 1,
    "cugr_congestion_iterations": 10,
    "start_utc": attempt_data["start_utc"],
    "end_utc": end,
    "exit_code": int(route_rc),
    "direct_parser_exit_code": int(analysis_rc),
    "command": attempt_data["command"],
    "inputs": attempt_data["inputs"],
    "protected_hashes_before": attempt_data["protected_hashes_before"],
    "outputs": {
        "log": item(log), "guide": item(guide), "congestion_report": item(congestion),
        "routed_odb": item(odb), "routed_sdc": item(sdc), "direct_analysis": item(analysis),
    },
    "authorizes": ["B3_STRICT_PHASE6_EVALUATION"] if passed else [],
    "next_stage": "B3_STRICT_PHASE6_EVALUATION" if passed else None,
}
with open(manifest, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2)
    stream.write("\n")
PY

test "$route_rc" -eq 0
test "$analysis_rc" -eq 0
echo "B3 single global-route report: $manifest"
