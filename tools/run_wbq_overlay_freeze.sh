#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python_exe="${STOB_FLOORPLAN_PYTHON:-$root/.venv/bin/python}"
manifest="$root/output/final_integrated_gds/inputs/floorplan_manifest.json"
tsv_csv="$root/output/final_integrated_gds/inputs/tsv_connectivity.csv"
transform="$root/output/final_integrated_gds/inputs/floorplan_transform.json"
rtl_manifest="$root/reports/final_integrated_gds_execution/wbq_phase7_rtl_gds_manifest.json"
schema="$root/design/floorplan/logic_die_floorplan.schema.json"
build_dir="$root/output/final_integrated_gds/inputs/overlay_build"
gds="$build_dir/logic_die_floorplan.gds"
lyp="$build_dir/logic_die_floorplan.lyp"
vis="$build_dir/visualization_manifest.json"
canonical_gds="$root/output/final_integrated_gds/inputs/tsv_bump_overlay.gds"
canonical_lyp="$root/output/final_integrated_gds/inputs/tsv_bump_overlay.lyp"
validation="$root/reports/final_integrated_gds_execution/wbq_overlay_validation.json"
report="$root/reports/final_integrated_gds_execution/08_overlay_merge_report.html"

for output in "$manifest" "$tsv_csv" "$transform" "$gds" "$lyp" "$vis" \
  "$canonical_gds" "$canonical_lyp" "$validation" "$report"; do
  if test -e "$output"; then
    echo "existing wbq overlay output prevents overwrite: $output" >&2
    exit 4
  fi
done
test -x "$python_exe"
"$python_exe" -c 'import gdstk, jsonschema'

"$python_exe" "$root/tools/prepare_wbq_overlay_manifest.py"
"$python_exe" "$root/tools/validate_logic_die_floorplan.py" \
  --manifest "$manifest" --schema "$schema" --tsv-csv "$tsv_csv" \
  --output "$validation"
"$python_exe" - "$transform" "$rtl_manifest" <<'PY'
import json
import sys
from pathlib import Path

transform = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
rtl = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8-sig"))
anchors = transform.get("anchors", [])
if transform.get("anchor_count") != 2 or len(anchors) != 2:
    raise SystemExit("wbq overlay requires exactly two coordinate anchors")
if any(float(item.get("error_um", -1)) != 0.0 for item in anchors):
    raise SystemExit("wbq overlay anchor error is nonzero")
if transform.get("target_rtl_gds_bbox_um") != rtl.get("geometry", {}).get("bbox_um"):
    raise SystemExit("wbq overlay transform target bbox does not match RTL GDS")
print("WBQ_OVERLAY_ANCHOR_GATE PASS anchors=2 max_error_um=0")
PY

"$python_exe" "$root/tools/export_logic_die_floorplan_gds.py" \
  --manifest "$manifest" --output "$build_dir"
STOB_FLOORPLAN_GDS="$gds" STOB_FLOORPLAN_VIS_MANIFEST="$vis" \
  klayout -zz -r "$root/tools/check_logic_die_floorplan_gds.py"

cp -- "$gds" "$canonical_gds"
cp -- "$lyp" "$canonical_lyp"
test "$(sha256sum "$gds" | awk '{print $1}')" = "$(sha256sum "$canonical_gds" | awk '{print $1}')"
test "$(sha256sum "$lyp" | awk '{print $1}')" = "$(sha256sum "$canonical_lyp" | awk '{print $1}')"

"$python_exe" - "$manifest" "$tsv_csv" "$transform" "$vis" "$validation" "$canonical_gds" "$canonical_lyp" "$report" <<'PY'
import hashlib
import html
import json
import sys
from pathlib import Path

manifest, csv_path, transform_path, vis_path, validation_path, gds, lyp, report = map(Path, sys.argv[1:])
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
doc = json.loads(manifest.read_text(encoding="utf-8-sig"))
transform = json.loads(transform_path.read_text(encoding="utf-8-sig"))
vis = json.loads(vis_path.read_text(encoding="utf-8-sig"))
validation = json.loads(validation_path.read_text(encoding="utf-8-sig"))
payload = {
    "schema_version": 1,
    "status": "PASS",
    "signoff": False,
    "manifest": {"path": str(manifest), "bytes": manifest.stat().st_size, "sha256": sha(manifest)},
    "tsv_csv": {"path": str(csv_path), "bytes": csv_path.stat().st_size, "sha256": sha(csv_path)},
    "transform": {"path": str(transform_path), "bytes": transform_path.stat().st_size, "sha256": sha(transform_path)},
    "overlay_gds": {"path": str(gds), "bytes": gds.stat().st_size, "sha256": sha(gds)},
    "overlay_lyp": {"path": str(lyp), "bytes": lyp.stat().st_size, "sha256": sha(lyp)},
    "die_bbox_um": transform["target_rtl_gds_bbox_um"],
    "anchors": transform["anchors"],
    "counts": validation["counts"],
    "independent_klayout_readback": True,
    "visualization_manifest_sha256": sha(vis_path),
    "claim_boundary": "Illustrative/estimated TSV, micro-bump, HBM and reserved-region overlay in the exact routed RTL coordinate frame; not manufacturing geometry. RESEARCH ARTIFACT — NOT FOR FABRICATION",
}
validation_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
esc = lambda value: html.escape(str(value))
report.write_text(f"""<!doctype html><html lang=\"ko\"><head><meta charset=\"utf-8\"><title>WBQ overlay 보고서</title><style>body{{font-family:system-ui,sans-serif;max-width:1080px;margin:32px auto;color:#182235}}h1,h2{{color:#173f6b}}table{{border-collapse:collapse;width:100%}}th,td{{padding:10px;border-bottom:1px solid #ddd;text-align:left}}th{{background:#eef3f8}}.verdict{{padding:16px;background:#e7f6ed;border-left:6px solid #168154}}</style></head><body><h1>Phase 8 — TSV·micro-bump·HBM overlay</h1><div class=\"verdict\"><strong>PASS</strong><br>Canonical schema, geometry, connectivity, anchors, independent KLayout readback</div><table><tr><th>RTL coordinate bbox µm</th><td>{esc(payload['die_bbox_um'])}</td></tr><tr><th>Anchors / max error</th><td>2 / 0 µm</td></tr><tr><th>TSV bundles / shapes</th><td>{payload['counts']['tsv_bundles']} / {payload['counts']['tsv_shapes']}</td></tr><tr><th>Micro-bump bundles / shapes</th><td>{payload['counts']['micro_bump_bundles']} / {payload['counts']['micro_bump_shapes']}</td></tr><tr><th>Overlay GDS SHA-256</th><td><code>{payload['overlay_gds']['sha256']}</code></td></tr></table><p>Overlay는 illustrative/estimated research geometry이며 실제 제조 pin map이 아니다. <strong>RESEARCH ARTIFACT — NOT FOR FABRICATION.</strong></p></body></html>""", encoding="utf-8")
print(f"WBQ_OVERLAY_FREEZE PASS gds={gds} sha256={payload['overlay_gds']['sha256']}")
PY
