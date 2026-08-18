#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"
evidence="$root/reports/groot_normalization/quad_local_b7/phase7"
phase7_root="${WBQ_B7_PHASE7_ROOT:-/dev/shm/wbq_b7_phase6_10/phase7}"
manifest="$evidence/b7_phase7_detailed_route_execution_report.json"
def="$phase7_root/b7_phase7_detailed_route.def"
tech="$orfs_flow/platforms/sky130hd/sky130hd.lyt"
cell_gds="$orfs_flow/platforms/sky130hd/gds/sky130_fd_sc_hd.gds"
converter="$orfs_flow/util/def2stream.py"
gds="$phase7_root/b7_phase7_routed.gds"
log="$evidence/b7_phase7_rtl_gds_streamout.log"
preflight="$evidence/b7_phase7_rtl_gds_preflight.json"
attempt="$evidence/b7_phase7_rtl_gds_invocation.json"
output_manifest="$evidence/b7_phase7_rtl_gds_execution_report.json"

for path in "$manifest" "$def" "$tech" "$cell_gds" "$converter"; do test -s "$path"; done
command -v klayout >/dev/null
python3 - "$manifest" "$def" <<'PY'
import hashlib, json, pathlib, sys
def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
if manifest.get("status") != "PASS" or "B7_PHASE7_RTL_GDS_STREAMOUT" not in manifest.get("authorizes", []):
    raise SystemExit("B7 Phase 7 manifest does not authorize GDS streamout")
if sha(pathlib.Path(sys.argv[2])) != manifest["artifacts"]["detailed_def"]["sha256"]:
    raise SystemExit("B7 detailed DEF hash mismatch")
print("WBQ_B7_PHASE7_RTL_GDS_INPUT_GATE PASS")
PY
for path in "$gds" "$log" "$preflight" "$attempt" "$output_manifest"; do
  if [[ -e "$path" ]]; then echo "existing B7 RTL GDS artifact prevents overwrite: $path" >&2; exit 4; fi
done
if pgrep -x openroad >/dev/null; then echo "OpenROAD exists; refusing concurrent GDS streamout" >&2; exit 3; fi

manifest_sha="$(sha256sum "$manifest" | awk '{print $1}')"
def_sha="$(sha256sum "$def" | awk '{print $1}')"
start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
tech_sha="$(sha256sum "$tech" | awk '{print $1}')"
cell_gds_sha="$(sha256sum "$cell_gds" | awk '{print $1}')"
converter_sha="$(sha256sum "$converter" | awk '{print $1}')"
python3 - "$preflight" "$attempt" "$start" "$manifest" "$manifest_sha" "$def" "$def_sha" \
  "$tech" "$tech_sha" "$cell_gds" "$cell_gds_sha" "$converter" "$converter_sha" <<'PY'
import json, sys
preflight, attempt, start, manifest, manifest_sha, deffile, def_sha, tech, tech_sha, cell_gds, cell_gds_sha, converter, converter_sha = sys.argv[1:]
payload = {"schema_version": 1, "phase": 7, "variant": "B7_PHASE7_RTL_GDS",
           "status": "PASS", "generated_at_utc": start,
           "command": "klayout ORFS def2stream.py", "invocation_limit": 1,
           "streamout_method": "ORFS_KLAYOUT_DEF2STREAM_FROM_OPENROAD_DETAILED_DEF",
           "inputs": {"phase7_manifest": {"path": manifest, "sha256": manifest_sha},
                      "detailed_def": {"path": deffile, "sha256": def_sha},
                      "technology": {"path": tech, "sha256": tech_sha},
                      "cell_gds": {"path": cell_gds, "sha256": cell_gds_sha},
                      "converter": {"path": converter, "sha256": converter_sha}},
           "authorizes": ["B7_PHASE7_RTL_GDS_STREAMOUT_COMPUTE"],
           "next_stage": "B7_PHASE7_RTL_GDS_STREAMOUT_COMPUTE"}
with open(preflight, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2); stream.write("\n")
with open(attempt, "x", encoding="utf-8") as stream:
    json.dump({**payload, "status": "STARTED", "invocation_count": 1}, stream, indent=2); stream.write("\n")
PY

{
  echo "WBQ_B7_RTL_GDS_START_UTC=$start"
  echo "WBQ_B7_RTL_GDS_INVOCATION_COUNT=1"
  echo "WBQ_B7_RTL_GDS_MANIFEST_SHA256=$manifest_sha"
  echo "WBQ_B7_RTL_GDS_DEF_SHA256=$def_sha"
  echo "WBQ_B7_RTL_GDS_STREAMOUT_METHOD=ORFS_KLAYOUT_DEF2STREAM_FROM_OPENROAD_DETAILED_DEF"
  echo "WBQ_B7_RTL_GDS_KLAYOUT_VERSION=$(klayout -b -v 2>&1 | head -n 1)"
  echo "WBQ_B7_RTL_GDS_TECH_SHA256=$tech_sha"
  echo "WBQ_B7_RTL_GDS_CELL_LIBRARY_SHA256=$cell_gds_sha"
  echo "WBQ_B7_RTL_GDS_CONVERTER_SHA256=$converter_sha"
} > "$log"
set +e
/usr/bin/time -v klayout -zz \
  -rd design_name=logic_die_normalization_hbm_quad_local_b2_top \
  -rd in_def="$def" -rd in_files="$cell_gds" -rd seal_file= \
  -rd out_file="$gds" -rd tech_file="$tech" -rd layer_map= \
  -r "$converter" >> "$log" 2>&1
rc=$?
set -e
echo "WBQ_B7_RTL_GDS_EXIT_CODE=$rc" >> "$log"
echo "WBQ_B7_RTL_GDS_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$log"
if [[ "$rc" -eq 0 && -s "$gds" ]]; then
  echo "WBQ_B7_RTL_GDS_OUTPUT_SHA256=$(sha256sum "$gds" | awk '{print $1}')" >> "$log"
fi
test "$rc" -eq 0
test -s "$gds"
python3 tools/check_b7_phase7_rtl_gds.py --gds "$gds" --source "$manifest" --log "$log" \
  --technology "$tech" --cell-gds "$cell_gds" --converter "$converter" --output "$output_manifest"
grep -q '"status": "PASS"' "$output_manifest"
echo "WBQ_B7_PHASE7_RTL_GDS_STREAMOUT PASS report=$output_manifest"
