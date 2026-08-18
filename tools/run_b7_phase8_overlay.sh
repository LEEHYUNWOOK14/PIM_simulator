#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
python_exe="${STOB_FLOORPLAN_PYTHON:-$root/.venv/bin/python}"
phase7_evidence="$root/reports/groot_normalization/quad_local_b7/phase7"
evidence="$root/reports/groot_normalization/quad_local_b7/phase8"
phase7_root="${WBQ_B7_PHASE7_ROOT:-/dev/shm/wbq_b7_phase6_10/phase7}"
phase8_root="${WBQ_B7_PHASE8_ROOT:-/dev/shm/wbq_b7_phase6_10/phase8}"
rtl_manifest="$phase7_evidence/b7_phase7_rtl_gds_execution_report.json"
rtl_gds="$phase7_root/b7_phase7_routed.gds"
source="$root/design/floorplan/logic_die_floorplan.json"
schema="$root/design/floorplan/logic_die_floorplan.schema.json"
floorplan="$phase8_root/b7_floorplan_manifest.json"
tsv_csv="$phase8_root/b7_tsv_connectivity.csv"
transform="$phase8_root/b7_floorplan_transform.json"
schema_validation="$phase8_root/b7_overlay_schema_validation.json"
build="$phase8_root/overlay_build"
build_gds="$build/logic_die_floorplan.gds"
build_lyp="$build/logic_die_floorplan.lyp"
vis="$build/visualization_manifest.json"
overlay_gds="$phase8_root/b7_tsv_bump_overlay.gds"
overlay_lyp="$phase8_root/b7_tsv_bump_overlay.lyp"
preflight="$evidence/b7_phase8_preflight.json"
manifest="$evidence/b7_phase8_overlay_execution_report.json"
report="$evidence/b7_phase8_overlay_execution_report.md"

mkdir -p "$evidence" "$phase8_root"
for path in "$rtl_manifest" "$rtl_gds" "$source" "$schema"; do test -s "$path"; done
test -x "$python_exe"
"$python_exe" -c 'import gdstk, jsonschema'
python3 - "$rtl_manifest" "$rtl_gds" <<'PY'
import hashlib, json, pathlib, sys
def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
if manifest.get("status") != "PASS" or "B7_PHASE8_OVERLAY" not in manifest.get("authorizes", []):
    raise SystemExit("B7 Phase 7 RTL GDS does not authorize Phase 8")
if sha(pathlib.Path(sys.argv[2])) != manifest["gds"]["sha256"]:
    raise SystemExit("B7 Phase 8 RTL GDS hash mismatch")
print("WBQ_B7_PHASE8_INPUT_GATE PASS")
PY
for path in "$floorplan" "$tsv_csv" "$transform" "$schema_validation" "$build_gds" "$build_lyp" \
  "$vis" "$overlay_gds" "$overlay_lyp" "$preflight" "$manifest" "$report"; do
  if [[ -e "$path" ]]; then echo "existing B7 Phase 8 artifact prevents overwrite: $path" >&2; exit 4; fi
done

start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
rtl_manifest_sha="$(sha256sum "$rtl_manifest" | awk '{print $1}')"
rtl_gds_sha="$(sha256sum "$rtl_gds" | awk '{print $1}')"
python3 - "$preflight" "$start" "$rtl_manifest" "$rtl_manifest_sha" "$rtl_gds" "$rtl_gds_sha" <<'PY'
import json, sys
preflight, start, manifest, manifest_sha, gds, gds_sha = sys.argv[1:]
payload = {"schema_version": 1, "phase": 8, "variant": "B7_PHASE8_OVERLAY",
           "status": "PASS", "generated_at_utc": start,
           "commands": ["prepare_wbq_overlay_manifest.py", "validate_logic_die_floorplan.py",
                        "export_logic_die_floorplan_gds.py", "independent KLayout readback"],
           "inputs": {"phase7_rtl_gds_manifest": {"path": manifest, "sha256": manifest_sha},
                      "rtl_gds": {"path": gds, "sha256": gds_sha}},
           "authorizes": ["B7_PHASE8_OVERLAY_BUILD"], "next_stage": "B7_PHASE8_OVERLAY_BUILD"}
with open(preflight, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2); stream.write("\n")
PY

"$python_exe" tools/prepare_wbq_overlay_manifest.py --source "$source" --rtl-manifest "$rtl_manifest" \
  --output "$floorplan" --tsv-output "$tsv_csv" --transform-output "$transform"
"$python_exe" tools/validate_logic_die_floorplan.py --manifest "$floorplan" --schema "$schema" \
  --tsv-csv "$tsv_csv" --output "$schema_validation"
python3 - "$transform" "$rtl_manifest" <<'PY'
import json, sys
from pathlib import Path
transform = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
rtl = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
anchors = transform.get("anchors", [])
if transform.get("anchor_count") != 2 or len(anchors) != 2:
    raise SystemExit("B7 Phase 8 requires exactly two anchors")
if any(float(item.get("error_um", -1)) != 0.0 for item in anchors):
    raise SystemExit("B7 Phase 8 anchor error is nonzero")
if transform.get("target_rtl_gds_bbox_um") != rtl.get("geometry", {}).get("bbox_um"):
    raise SystemExit("B7 Phase 8 target bbox mismatch")
print("WBQ_B7_PHASE8_ANCHOR_GATE PASS anchors=2 max_error_um=0")
PY
"$python_exe" tools/export_logic_die_floorplan_gds.py --manifest "$floorplan" --output "$build"
STOB_FLOORPLAN_GDS="$build_gds" STOB_FLOORPLAN_VIS_MANIFEST="$vis" \
  klayout -zz -r tools/check_logic_die_floorplan_gds.py
cp -- "$build_gds" "$overlay_gds"
cp -- "$build_lyp" "$overlay_lyp"

end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
python3 - "$manifest" "$report" "$start" "$end" "$rtl_manifest" "$rtl_gds" "$floorplan" "$tsv_csv" "$transform" "$schema_validation" "$overlay_gds" "$overlay_lyp" "$vis" <<'PY'
import hashlib, json, pathlib, sys
(manifest, report, start, end, rtl_manifest, rtl_gds, floorplan, tsv_csv, transform,
 validation, overlay_gds, overlay_lyp, vis) = sys.argv[1:]
def item(text):
    path = pathlib.Path(text)
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return {"path": str(path), "bytes": path.stat().st_size,
            "sha256": digest.hexdigest()}
transform_data = json.load(open(transform, encoding="utf-8"))
validation_data = json.load(open(validation, encoding="utf-8"))
payload = {"schema_version": 1, "phase": 8, "variant": "B7_PHASE8_OVERLAY",
           "status": "PASS", "signoff": False, "start_utc": start, "end_utc": end,
           "die_bbox_um": transform_data["target_rtl_gds_bbox_um"],
           "anchors": transform_data["anchors"], "counts": validation_data["counts"],
           "independent_klayout_readback": True,
           "inputs": {"phase7_rtl_gds_manifest": item(rtl_manifest), "rtl_gds": item(rtl_gds)},
           "artifacts": {"floorplan_manifest": item(floorplan), "tsv_csv": item(tsv_csv),
                         "transform": item(transform), "schema_validation": item(validation),
                         "overlay_gds": item(overlay_gds), "overlay_lyp": item(overlay_lyp),
                         "visualization_manifest": item(vis)},
           "authorizes": ["B7_PHASE9_FINAL_GDS_MERGE"],
           "next_stage": "B7_PHASE9_FINAL_GDS_MERGE",
           "claim_boundary": "Illustrative/estimated overlay in the routed RTL coordinate frame; not manufacturing geometry."}
with open(manifest, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2); stream.write("\n")
pathlib.Path(report).write_text(
    "# B7 Phase 8 overlay\n\n"
    f"- Status: **PASS**\n- Anchors: {len(payload['anchors'])}, maximum error 0 um\n"
    f"- Overlay GDS: `{payload['artifacts']['overlay_gds']['sha256']}`\n"
    "- Boundary: illustrative research geometry; not manufacturing signoff.\n",
    encoding="utf-8")
PY
echo "WBQ_B7_PHASE8_OVERLAY PASS report=$manifest"

