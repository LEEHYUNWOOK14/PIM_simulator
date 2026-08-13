#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gds="$root/output/final_integrated_gds/final/merged_final_physical.gds"
lyp="$root/output/final_integrated_gds/final/merged_final_physical.lyp"
report="$root/output/final_integrated_gds/validation/merged_final_physical_report.json"
png="$root/output/final_integrated_gds/validation/klayout_fixed_camera.png"
log="$root/reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_wbq_final_gds_render.log"

test -s "$gds"
test -s "$lyp"
test -s "$report"
if test -e "$png" || test -e "$log"; then
  echo "existing final GDS render output prevents overwrite" >&2
  exit 4
fi
python3 - "$gds" "$report" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

gds, report = map(Path, sys.argv[1:])
doc = json.loads(report.read_text(encoding="utf-8-sig"))
actual = hashlib.sha256(gds.read_bytes()).hexdigest()
if doc.get("status") != "PASS" or doc.get("signoff") is not False:
    raise SystemExit("final merge report is not a non-signoff PASS")
if doc.get("output", {}).get("gds_sha256") != actual:
    raise SystemExit("final merged GDS hash mismatch before rendering")
print("WBQ_FINAL_RENDER_INPUT_GATE PASS")
PY

mkdir -p "$(dirname "$png")" "$(dirname "$log")"
{
  echo "WBQ_FINAL_RENDER_GDS_SHA256=$(sha256sum "$gds" | awk '{print $1}')"
  echo "WBQ_FINAL_RENDER_LYP_SHA256=$(sha256sum "$lyp" | awk '{print $1}')"
  echo "WBQ_FINAL_RENDER_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  STOB_FINAL_GDS="$gds" STOB_FINAL_LYP="$lyp" STOB_FINAL_PNG="$png" \
    klayout -zz -r "$root/tools/render_wbq_final_gds.py"
  echo "WBQ_FINAL_RENDER_PNG_SHA256=$(sha256sum "$png" | awk '{print $1}')"
  echo "WBQ_FINAL_RENDER_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$log" 2>&1
test -s "$png"
grep -q '^KLAYOUT_WBQ_FINAL_RENDER PASS ' "$log"
echo "WBQ_FINAL_GDS_RENDER PASS png=$png"
