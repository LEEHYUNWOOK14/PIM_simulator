#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rtl_manifest="$root/reports/final_integrated_gds_execution/wbq_phase7_rtl_gds_manifest.json"
overlay_manifest="$root/reports/final_integrated_gds_execution/wbq_overlay_validation.json"
rtl_gds="$root/output/final_integrated_gds/inputs/integrated_rtl_routed.gds"
overlay_gds="$root/output/final_integrated_gds/inputs/tsv_bump_overlay.gds"
overlay_lyp="$root/output/final_integrated_gds/inputs/tsv_bump_overlay.lyp"
floorplan="$root/output/final_integrated_gds/inputs/floorplan_manifest.json"
recipe="$root/output/final_integrated_gds/recipe/final_gds_merge_recipe.json"
final_dir="$root/output/final_integrated_gds/final"
validation="$root/output/final_integrated_gds/validation/merged_final_physical_report.json"

for output in "$recipe" "$final_dir/merged_final_physical.gds" \
  "$final_dir/merged_final_physical.lyp" "$validation"; do
  if test -e "$output"; then
    echo "existing final merge artifact prevents overwrite: $output" >&2
    exit 4
  fi
done

mapfile -t bbox < <(PYTHONPATH="$root/tools${PYTHONPATH:+:$PYTHONPATH}" python3 - \
  "$rtl_manifest" "$overlay_manifest" "$rtl_gds" "$overlay_gds" "$overlay_lyp" "$floorplan" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

rtl_manifest, overlay_manifest, rtl_gds, overlay_gds, overlay_lyp, floorplan = map(Path, sys.argv[1:])
for path in (rtl_manifest, overlay_manifest, rtl_gds, overlay_gds, overlay_lyp, floorplan):
    if not path.is_file() or path.stat().st_size == 0:
        raise SystemExit(f"missing/non-empty final merge input: {path}")
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
rtl = json.loads(rtl_manifest.read_text(encoding="utf-8-sig"))
overlay = json.loads(overlay_manifest.read_text(encoding="utf-8-sig"))
if rtl.get("status") != "PASS" or rtl.get("signoff") is not False:
    raise SystemExit("RTL GDS manifest is not a non-signoff PASS")
if overlay.get("status") != "PASS" or overlay.get("signoff") is not False:
    raise SystemExit("overlay manifest is not a non-signoff PASS")
if rtl.get("gds", {}).get("sha256") != sha(rtl_gds):
    raise SystemExit("RTL GDS hash mismatch")
if overlay.get("overlay_gds", {}).get("sha256") != sha(overlay_gds):
    raise SystemExit("overlay GDS hash mismatch")
if overlay.get("overlay_lyp", {}).get("sha256") != sha(overlay_lyp):
    raise SystemExit("overlay LYP hash mismatch")
if overlay.get("manifest", {}).get("sha256") != sha(floorplan):
    raise SystemExit("floorplan manifest hash mismatch")
rtl_bbox = rtl.get("geometry", {}).get("bbox_um")
overlay_bbox = overlay.get("die_bbox_um")
if rtl_bbox != overlay_bbox or len(rtl_bbox or []) != 4:
    raise SystemExit("RTL and overlay bbox mismatch")
for value in rtl_bbox:
    print(format(float(value), ".12g"))
PY
)
test "${#bbox[@]}" -eq 4

mkdir -p "$(dirname "$recipe")" "$final_dir" "$(dirname "$validation")"
PYTHONPATH="$root/tools${PYTHONPATH:+:$PYTHONPATH}" python3 "$root/tools/prepare_final_gds_merge_recipe.py" \
  --rtl-gds "$rtl_gds" --rtl-top logic_die_normalization_hbm_top \
  --overlay-gds "$overlay_gds" --overlay-top STOB_LOGIC_DIE_FLOORPLAN_NOT_SIGNOFF \
  --manifest "$floorplan" --overlay-lyp "$overlay_lyp" \
  --recipe "$recipe" --output-root "$final_dir" --report "$validation" \
  --orientation R0 --minimum-anchor-count 2 --anchor-tolerance-um 0.001 \
  --anchor "lower_left:${bbox[0]}:${bbox[1]}:${bbox[0]}:${bbox[1]}" \
  --anchor "upper_right:${bbox[2]}:${bbox[3]}:${bbox[2]}:${bbox[3]}"

bash "$root/tools/run_final_rtl_gds_merge.sh" "$recipe"

python3 - "$validation" "${bbox[@]}" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
bbox = [float(value) for value in sys.argv[2:]]
checks = {
    "status": report.get("status") == "PASS",
    "not_signoff": report.get("signoff") is False,
    "two_anchors": len(report.get("anchors", [])) == 2,
    "zero_anchor_error": report.get("max_anchor_residual_um") == 0.0,
    "rtl_bbox": report.get("geometry", {}).get("transformed_rtl_bbox_um") == bbox,
    "within_die": report.get("geometry", {}).get("rtl_within_manifest_die") is True,
    "two_top_instances": report.get("cell_namespace", {}).get("output_top_instance_count") == 2,
    "research_boundary": "RESEARCH ARTIFACT — NOT FOR FABRICATION" in report.get("claim_boundary", ""),
}
failed = [name for name, passed in checks.items() if not passed]
if failed:
    raise SystemExit("wbq final merge gate failed: " + ", ".join(failed))
print("WBQ_FINAL_GDS_MERGE PASS")
PY
