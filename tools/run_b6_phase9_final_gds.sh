#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
phase7_evidence="$root/reports/groot_normalization/quad_local_b6/phase7"
phase8_evidence="$root/reports/groot_normalization/quad_local_b6/phase8"
evidence="$root/reports/groot_normalization/quad_local_b6/phase9"
phase7_root="${WBQ_B6_PHASE7_ROOT:-/dev/shm/wbq_b6_phase6_10/phase7}"
phase8_root="${WBQ_B6_PHASE8_ROOT:-/dev/shm/wbq_b6_phase6_10/phase8}"
phase9_root="${WBQ_B6_PHASE9_ROOT:-$root/output/final_integrated_gds/b6}"
rtl_manifest="$phase7_evidence/b6_phase7_rtl_gds_execution_report.json"
overlay_manifest="$phase8_evidence/b6_phase8_overlay_execution_report.json"
rtl_gds="$phase7_root/b6_phase7_routed.gds"
overlay_gds="$phase8_root/b6_tsv_bump_overlay.gds"
overlay_lyp="$phase8_root/b6_tsv_bump_overlay.lyp"
floorplan="$phase8_root/b6_floorplan_manifest.json"
recipe="$phase9_root/b6_final_gds_merge_recipe.json"
final_dir="$phase9_root/final"
gds="$final_dir/merged_final_physical.gds"
lyp="$final_dir/merged_final_physical.lyp"
merge_report="$phase9_root/b6_merged_final_physical_report.json"
png="$phase9_root/b6_klayout_fixed_camera.png"
preflight="$evidence/b6_phase9_preflight.json"
log="$evidence/b6_phase9_merge_render.log"
manifest="$evidence/b6_phase9_final_gds_execution_report.json"

mkdir -p "$evidence" "$phase9_root" "$final_dir"
for path in "$rtl_manifest" "$overlay_manifest" "$rtl_gds" "$overlay_gds" "$overlay_lyp" "$floorplan"; do test -s "$path"; done
for path in "$recipe" "$gds" "$lyp" "$merge_report" "$png" "$preflight" "$log" "$manifest"; do
  if [[ -e "$path" ]]; then echo "existing B6 Phase 9 artifact prevents overwrite: $path" >&2; exit 4; fi
done

mapfile -t bbox < <(python3 - "$rtl_manifest" "$overlay_manifest" "$rtl_gds" "$overlay_gds" "$overlay_lyp" "$floorplan" <<'PY'
import hashlib, json, pathlib, sys
def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
rtl_manifest, overlay_manifest, rtl_gds, overlay_gds, overlay_lyp, floorplan = map(pathlib.Path, sys.argv[1:])
rtl = json.loads(rtl_manifest.read_text(encoding="utf-8"))
overlay = json.loads(overlay_manifest.read_text(encoding="utf-8"))
if rtl.get("status") != "PASS" or "B6_PHASE8_OVERLAY" not in rtl.get("authorizes", []):
    raise SystemExit("B6 RTL GDS manifest is not an authorizing PASS")
if overlay.get("status") != "PASS" or "B6_PHASE9_FINAL_GDS_MERGE" not in overlay.get("authorizes", []):
    raise SystemExit("B6 overlay manifest is not an authorizing PASS")
if rtl["gds"]["sha256"] != sha(rtl_gds): raise SystemExit("B6 RTL GDS hash mismatch")
for key, path in (("overlay_gds", overlay_gds), ("overlay_lyp", overlay_lyp), ("floorplan_manifest", floorplan)):
    if overlay["artifacts"][key]["sha256"] != sha(path): raise SystemExit(f"B6 Phase 9 hash mismatch: {key}")
bbox = rtl.get("geometry", {}).get("bbox_um")
if bbox != overlay.get("die_bbox_um") or len(bbox or []) != 4: raise SystemExit("B6 RTL/overlay bbox mismatch")
for value in bbox: print(format(float(value), ".12g"))
PY
)
test "${#bbox[@]}" -eq 4

start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
python3 - "$preflight" "$start" "$rtl_manifest" "$overlay_manifest" "$rtl_gds" "$overlay_gds" <<'PY'
import hashlib, json, pathlib, sys
def item(text):
    path = pathlib.Path(text); digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""): digest.update(chunk)
    return {"path": str(path), "sha256": digest.hexdigest()}
preflight, start, rtl_manifest, overlay_manifest, rtl_gds, overlay_gds = sys.argv[1:]
payload = {"schema_version": 1, "phase": 9, "variant": "B6_PHASE9_FINAL_GDS",
           "status": "PASS", "generated_at_utc": start,
           "merge_invocation_limit": 1, "render_invocation_limit": 1,
           "inputs": {"rtl_manifest": item(rtl_manifest), "overlay_manifest": item(overlay_manifest),
                      "rtl_gds": item(rtl_gds), "overlay_gds": item(overlay_gds)},
           "authorizes": ["B6_PHASE9_MERGE_RENDER"], "next_stage": "B6_PHASE9_MERGE_RENDER"}
with open(preflight, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2); stream.write("\n")
PY

{
  echo "WBQ_B6_PHASE9_START_UTC=$start"
  echo "WBQ_B6_PHASE9_MERGE_INVOCATION_COUNT=1"
  echo "WBQ_B6_PHASE9_RENDER_INVOCATION_COUNT=1"
} > "$log"
PYTHONPATH="$root/tools${PYTHONPATH:+:$PYTHONPATH}" python3 tools/prepare_final_gds_merge_recipe.py \
  --rtl-gds "$rtl_gds" --rtl-top logic_die_normalization_hbm_quad_local_b2_top \
  --overlay-gds "$overlay_gds" --overlay-top STOB_LOGIC_DIE_FLOORPLAN_NOT_SIGNOFF \
  --manifest "$floorplan" --overlay-lyp "$overlay_lyp" --recipe "$recipe" \
  --output-root "$final_dir" --report "$merge_report" --orientation R0 \
  --minimum-anchor-count 2 --anchor-tolerance-um 0.001 \
  --anchor "lower_left:${bbox[0]}:${bbox[1]}:${bbox[0]}:${bbox[1]}" \
  --anchor "upper_right:${bbox[2]}:${bbox[3]}:${bbox[2]}:${bbox[3]}" \
  >> "$log" 2>&1

bash tools/run_final_rtl_gds_merge.sh "$recipe" >> "$log" 2>&1

python3 - "$gds" "$merge_report" "${bbox[@]}" <<'PY'
import hashlib, json, pathlib, sys
gds, report = map(pathlib.Path, sys.argv[1:3]); bbox = [float(value) for value in sys.argv[3:]]
doc = json.loads(report.read_text(encoding="utf-8"))
digest = hashlib.sha256()
with gds.open("rb") as stream:
    for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""): digest.update(chunk)
actual = digest.hexdigest()
checks = {"status": doc.get("status") == "PASS", "not_signoff": doc.get("signoff") is False,
          "gds_hash": doc.get("output", {}).get("gds_sha256") == actual,
          "two_anchors": len(doc.get("anchors", [])) == 2,
          "zero_anchor_error": doc.get("max_anchor_residual_um") == 0.0,
          "rtl_bbox": doc.get("geometry", {}).get("transformed_rtl_bbox_um") == bbox,
          "within_die": doc.get("geometry", {}).get("rtl_within_manifest_die") is True,
          "two_top_instances": doc.get("cell_namespace", {}).get("output_top_instance_count") == 2}
failed = [name for name, passed in checks.items() if not passed]
if failed: raise SystemExit("B6 Phase 9 merge gate failed: " + ", ".join(failed))
print("WBQ_B6_PHASE9_MERGE_GATE PASS")
PY

{
  echo "WBQ_B6_PHASE9_RENDER_GDS_SHA256=$(sha256sum "$gds" | awk '{print $1}')"
  echo "WBQ_B6_PHASE9_RENDER_LYP_SHA256=$(sha256sum "$lyp" | awk '{print $1}')"
  STOB_FINAL_GDS="$gds" STOB_FINAL_LYP="$lyp" STOB_FINAL_PNG="$png" \
    klayout -zz -r tools/render_wbq_final_gds.py
  echo "WBQ_B6_PHASE9_RENDER_PNG_SHA256=$(sha256sum "$png" | awk '{print $1}')"
} >> "$log" 2>&1
test -s "$png"
grep -q '^KLAYOUT_WBQ_FINAL_RENDER PASS ' "$log"
end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "WBQ_B6_PHASE9_END_UTC=$end" >> "$log"

python3 - "$manifest" "$start" "$end" "$recipe" "$gds" "$lyp" "$merge_report" "$png" "$log" <<'PY'
import hashlib, json, pathlib, sys
manifest, start, end, recipe, gds, lyp, report, png, log = sys.argv[1:]
def item(text):
    path = pathlib.Path(text); digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""): digest.update(chunk)
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": digest.hexdigest()}
merge = json.load(open(report, encoding="utf-8"))
payload = {"schema_version": 1, "phase": 9, "variant": "B6_PHASE9_FINAL_GDS",
           "status": "PASS", "signoff": False, "start_utc": start, "end_utc": end,
           "merge_invocation_count": 1, "render_invocation_count": 1,
           "checks": {"merge_status_pass": merge.get("status") == "PASS",
                      "two_anchors": len(merge.get("anchors", [])) == 2,
                      "zero_anchor_residual": merge.get("max_anchor_residual_um") == 0.0,
                      "two_top_instances": merge.get("cell_namespace", {}).get("output_top_instance_count") == 2},
           "artifacts": {"recipe": item(recipe), "final_gds": item(gds), "final_lyp": item(lyp),
                         "merge_report": item(report), "fixed_camera_png": item(png), "log": item(log)},
           "authorizes": ["B6_PHASE10_COMPLETION_AUDIT"],
           "next_stage": "B6_PHASE10_COMPLETION_AUDIT",
           "claim_boundary": "Merged routed RTL plus illustrative overlay research GDS; not tape-out or manufacturing signoff."}
if not all(payload["checks"].values()): payload["status"] = "FAIL"; payload["authorizes"] = []; payload["next_stage"] = None
with open(manifest, "x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2); stream.write("\n")
PY
grep -q '"status": "PASS"' "$manifest"
echo "WBQ_B6_PHASE9_FINAL_GDS PASS report=$manifest"
