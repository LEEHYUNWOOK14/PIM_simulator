#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"

b3_report="$root/reports/groot_normalization/quad_local_b3"
evidence="$b3_report/phase6"
cts_root="${WBQ_B3_PHASE6_ROOT:-/dev/shm/wbq_b3_phase6_10/phase6_cts}"
route_root="${WBQ_B3_PHASE6_ROUTE_ROOT:-/dev/shm/wbq_b3_phase6_10/phase6_post_cts}"
cts_manifest="$evidence/b3_phase6_cts_execution_report.json"
cts_odb="$cts_root/b3_phase6_cts.odb"
cts_sdc="$cts_root/b3_phase6_cts.sdc"
log="$evidence/b3_phase6_post_cts_global_route.log"
audit_log="$evidence/b3_phase6_post_cts_route_audit.log"
preflight="$evidence/b3_phase6_post_cts_preflight.json"
attempt="$evidence/b3_phase6_post_cts_global_route_invocation.json"
manifest="$evidence/b3_phase6_post_cts_global_route_execution_report.json"
guide="$route_root/b3_phase6_post_cts.route_guide"
congestion="$route_root/b3_phase6_post_cts.congestion.rpt"
routed_odb="$route_root/b3_phase6_post_cts_global_route.odb"
routed_sdc="$route_root/b3_phase6_post_cts_global_route.sdc"
analysis_json="$evidence/b3_phase6_post_cts_congestion_analysis.json"
analysis_md="$evidence/b3_phase6_post_cts_congestion_analysis.md"
tcl="$root/verification/groot_normalization/wbq_b3_phase6_post_cts_global_route.tcl"

mkdir -p "$evidence" "$route_root"
for path in "$cts_manifest" "$cts_odb" "$cts_sdc" "$tcl"; do test -s "$path"; done
python3 - "$cts_manifest" "$cts_odb" "$cts_sdc" <<'PY'
import hashlib, json, pathlib, sys
def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
if manifest.get("status") != "PASS" or "B3_PHASE6_POST_CTS_GLOBAL_ROUTE" not in manifest.get("authorizes", []):
    raise SystemExit("B3 CTS gate does not authorize post-CTS global route")
for key, text in (("cts_odb", sys.argv[2]), ("cts_sdc", sys.argv[3])):
    path = pathlib.Path(text)
    if sha(path) != manifest["artifacts"][key]["sha256"]:
        raise SystemExit(f"post-CTS route input hash mismatch: {key}")
print("WBQ_B3_PHASE6_POST_CTS_INPUT_GATE PASS")
PY

for path in "$preflight" "$attempt" "$manifest" "$log" "$audit_log" "$guide" "$congestion" \
  "$routed_odb" "$routed_sdc" "$analysis_json" "$analysis_md"; do
  if [[ -e "$path" ]]; then
    echo "existing B3 Phase 6 post-CTS route artifact prevents overwrite: $path" >&2
    exit 4
  fi
done
if pgrep -x openroad >/dev/null; then
  echo "an OpenROAD process already exists; refusing concurrent post-CTS route" >&2
  exit 3
fi

cts_manifest_sha="$(sha256sum "$cts_manifest" | awk '{print $1}')"
cts_odb_sha="$(sha256sum "$cts_odb" | awk '{print $1}')"
cts_sdc_sha="$(sha256sum "$cts_sdc" | awk '{print $1}')"
start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
free_kib="$(df -Pk "$route_root" | awk 'NR==2 {print $4}')"
python3 - "$preflight" "$attempt" "$start" "$cts_manifest" "$cts_manifest_sha" "$cts_odb" "$cts_odb_sha" "$cts_sdc" "$cts_sdc_sha" "$free_kib" <<'PY'
import json, sys
preflight, attempt, start, manifest, manifest_sha, odb, odb_sha, sdc, sdc_sha, free_kib = sys.argv[1:]
payload = {
    "schema_version": 1, "phase": 6, "variant": "B3_PHASE6_POST_CTS",
    "status": "PASS", "generated_at_utc": start,
    "command": "openroad -threads 1 wbq_b3_phase6_post_cts_global_route.tcl",
    "global_route_invocation_limit": 1, "cugr_congestion_iterations": 10,
    "skip_large_fanout_nets": 20000,
    "reason_for_20000_limit": "Phase 5 mapped contract measured reset leaves up to 13671 sinks and forbids skipping rst_ni",
    "free_kib": int(free_kib),
    "inputs": {"cts_manifest": {"path": manifest, "sha256": manifest_sha},
               "cts_odb": {"path": odb, "sha256": odb_sha},
               "cts_sdc": {"path": sdc, "sha256": sdc_sha}},
    "authorizes": ["B3_PHASE6_POST_CTS_GLOBAL_ROUTE_COMPUTE"],
    "next_stage": "B3_PHASE6_POST_CTS_GLOBAL_ROUTE_COMPUTE",
}
with open(preflight, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2); stream.write("\n")
with open(attempt, "x", encoding="utf-8") as stream:
    json.dump({**payload, "status": "STARTED", "invocation_count": 1}, stream, indent=2); stream.write("\n")
PY

{
  echo "WBQ_B3_PHASE6_POST_CTS_START_UTC=$start"
  echo "WBQ_B3_PHASE6_POST_CTS_GLOBAL_ROUTE_INVOCATION_COUNT=1"
  echo "WBQ_B3_PHASE6_POST_CTS_CUGR_ITERATIONS=10"
  echo "WBQ_B3_PHASE6_POST_CTS_SKIP_LARGE_FANOUT_NETS=20000"
  echo "WBQ_B3_PHASE6_POST_CTS_MANIFEST_SHA256=$cts_manifest_sha"
  echo "WBQ_B3_PHASE6_POST_CTS_ODB_SHA256=$cts_odb_sha"
  echo "WBQ_B3_PHASE6_POST_CTS_SDC_SHA256=$cts_sdc_sha"
} > "$log"
export WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd"
export WBQ_CTS_ODB="$cts_odb"
export WBQ_CTS_SDC="$cts_sdc"
export WBQ_ROUTE_OUTPUT_ROOT="$route_root"
export WBQ_PHASE6_CUGR_CONGESTION_ITERATIONS=10
set +e
/usr/bin/time -v "$openroad_exe" -exit -no_init -threads 1 -no_splash "$tcl" >> "$log" 2>&1
route_rc=$?
set -e
echo "WBQ_B3_PHASE6_POST_CTS_EXIT_CODE=$route_rc" >> "$log"
echo "WBQ_B3_PHASE6_POST_CTS_ROUTE_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$log"

audit_rc=1
if [[ "$route_rc" -eq 0 && -s "$routed_odb" && -s "$routed_sdc" ]]; then
  {
    echo "WBQ_B3_PHASE6_ROUTE_AUDIT_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "WBQ_B3_PHASE6_ROUTE_AUDIT_ODB_SHA256=$(sha256sum "$routed_odb" | awk '{print $1}')"
    echo "WBQ_B3_PHASE6_ROUTE_AUDIT_SDC_SHA256=$(sha256sum "$routed_sdc" | awk '{print $1}')"
  } > "$audit_log"
  set +e
  WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd" WBQ_ROUTED_ODB="$routed_odb" WBQ_ROUTED_SDC="$routed_sdc" \
    "$openroad_exe" -exit -no_init -threads 1 -no_splash \
    "$root/verification/groot_normalization/audit_wbq_b3_phase6_post_cts_route.tcl" \
    >> "$audit_log" 2>&1
  audit_rc=$?
  set -e
  echo "WBQ_B3_PHASE6_ROUTE_AUDIT_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$audit_log"
fi

analysis_rc=1
if [[ "$route_rc" -eq 0 && "$audit_rc" -eq 0 && -s "$guide" && -e "$congestion" ]]; then
  set +e
  python3 tools/analyze_variant_residual_congestion.py \
    --variant B3_PHASE6_POST_CTS \
    --pass-token 'WBQ_B3_PHASE6_POST_CTS_GLOBAL_ROUTE PASS' --cugr-iterations 10 \
    --report "$congestion" --log "$log" --guide "$guide" --odb "$routed_odb" --sdc "$routed_sdc" \
    --invocation "$attempt" --output-json "$analysis_json" --output-md "$analysis_md"
  analysis_rc=$?
  set -e
fi
end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

python3 - "$manifest" "$attempt" "$end" "$route_rc" "$audit_rc" "$analysis_rc" "$log" "$audit_log" "$guide" "$congestion" "$routed_odb" "$routed_sdc" "$analysis_json" <<'PY'
import hashlib, json, pathlib, re, sys
(manifest, attempt, end, route_rc, audit_rc, analysis_rc, log, audit_log, guide,
 congestion, odb, sdc, analysis) = sys.argv[1:]
def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
def item(text):
    path = pathlib.Path(text)
    return {"path": str(path), "bytes": path.stat().st_size if path.exists() else 0,
            "sha256": sha(path) if path.exists() else None}
run_text = pathlib.Path(log).read_text(encoding="utf-8", errors="replace")
skipped = [{"net": net, "terminals": int(terminals)} for net, terminals in
           re.findall(r"Skipping net (\S+) with (\d+) terminals", run_text)]
analysis_data = json.load(open(analysis, encoding="utf-8")) if pathlib.Path(analysis).exists() else {}
totals = analysis_data.get("totals", {})
passed = (int(route_rc) == 0 and int(audit_rc) == 0 and int(analysis_rc) == 0
          and totals.get("rrr_residual") == 0 and totals.get("overflow_edges") == 0
          and not skipped)
attempt_data = json.load(open(attempt, encoding="utf-8"))
payload = {
    "schema_version": 1, "phase": 6, "variant": "B3_PHASE6_POST_CTS",
    "status": "PASS" if passed else "FAIL", "verdict": "PASS_POST_CTS_ZERO_CONGESTION" if passed else "ROUTED_NOT_CLOSED",
    "invocation_count": 1, "start_utc": attempt_data["generated_at_utc"], "end_utc": end,
    "exit_code": int(route_rc), "audit_exit_code": int(audit_rc), "direct_parser_exit_code": int(analysis_rc),
    "inputs": attempt_data["inputs"], "skipped_nets": skipped,
    "metrics": {"rrr_residual": totals.get("rrr_residual"), "overflow_edges": totals.get("overflow_edges"),
                "overflow_tracks": totals.get("overflow_tracks"), "congestion_windows": totals.get("windows")},
    "artifacts": {"log": item(log), "audit_log": item(audit_log), "guide": item(guide),
                  "congestion_report": item(congestion), "routed_odb": item(odb),
                  "routed_sdc": item(sdc), "direct_analysis": item(analysis)},
    "authorizes": ["B3_PHASE7_DETAILED_ROUTE"] if passed else [],
    "next_stage": "B3_PHASE7_DETAILED_ROUTE" if passed else None,
    "claim_boundary": "Post-CTS global-route research checkpoint; detailed route and manufacturing signoff are not established.",
}
with open(manifest, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2); stream.write("\n")
PY

test "$route_rc" -eq 0
test "$audit_rc" -eq 0
test "$analysis_rc" -eq 0
grep -q '"status": "PASS"' "$manifest"
echo "WBQ_B3_PHASE6_POST_CTS_GLOBAL_ROUTE PASS report=$manifest"
