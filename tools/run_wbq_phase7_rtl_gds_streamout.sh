#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$root/verification/groot_normalization/eda_environment.sh"

manifest="$root/reports/final_integrated_gds_execution/wbq_phase7_detailed_route_manifest.json"
def="$physical_report_root/logic_die_normalization_hbm_top_wbq_phase7_detailed_route.def"
tech="$orfs_flow/platforms/sky130hd/sky130hd.lyt"
cell_gds="$orfs_flow/platforms/sky130hd/gds/sky130_fd_sc_hd.gds"
converter="$orfs_flow/util/def2stream.py"
output_dir="$root/output/final_integrated_gds/inputs"
output="$output_dir/integrated_rtl_routed.gds"
log="$physical_report_root/logic_die_normalization_hbm_top_wbq_phase7_rtl_gds_streamout.log"

if pgrep -f '[o]penroad.*normalization_hbm_wbq' >/dev/null; then
  echo "wbq OpenROAD job already running; refusing concurrent RTL GDS stream-out" >&2
  exit 3
fi

command -v klayout >/dev/null
test -s "$manifest"
test -s "$def"
test -s "$tech"
test -s "$cell_gds"
test -s "$converter"
if test -e "$output" || test -e "$log"; then
  echo "existing RTL GDS stream-out artifact prevents overwrite" >&2
  exit 4
fi

python3 - "$manifest" "$def" <<'PY'
import hashlib
import json
import sys
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


manifest_path, def_path = map(Path, sys.argv[1:])
manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
if manifest.get("gate_pass") is not True or manifest.get("verdict") != "PASS_RESEARCH_DETAILED_ROUTE":
    raise SystemExit("Phase-7 manifest does not authorize RTL GDS stream-out")
item = manifest.get("artifacts", {}).get("detailed_def", {})
if def_path.stat().st_size != item.get("bytes") or sha256(def_path) != item.get("sha256"):
    raise SystemExit("Phase-7 detailed DEF bytes/hash mismatch")
print("WBQ_PHASE7_RTL_GDS_INPUT_GATE PASS")
PY

mkdir -p "$output_dir"
{
  echo "WBQ_RTL_GDS_GIT_SHA=$(git -C "$root" rev-parse HEAD)"
  echo "WBQ_RTL_GDS_ORFS_SHA=$(git -C "$orfs_root" rev-parse HEAD)"
  echo "WBQ_RTL_GDS_KLAYOUT_VERSION=$(klayout -b -v 2>&1 | head -n 1)"
  echo "WBQ_RTL_GDS_OPENROAD_DIRECT_WRITER=UNAVAILABLE_IN_PINNED_BINARY"
  echo "WBQ_RTL_GDS_STREAMOUT_METHOD=ORFS_KLAYOUT_DEF2STREAM"
  echo "WBQ_RTL_GDS_MANIFEST_SHA256=$(sha256sum "$manifest" | awk '{print $1}')"
  echo "WBQ_RTL_GDS_DEF_SHA256=$(sha256sum "$def" | awk '{print $1}')"
  echo "WBQ_RTL_GDS_TECH_SHA256=$(sha256sum "$tech" | awk '{print $1}')"
  echo "WBQ_RTL_GDS_CELL_LIBRARY_SHA256=$(sha256sum "$cell_gds" | awk '{print $1}')"
  echo "WBQ_RTL_GDS_CONVERTER_SHA256=$(sha256sum "$converter" | awk '{print $1}')"
  echo "WBQ_RTL_GDS_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$log"

set +e
/usr/bin/time -v klayout -zz \
  -rd design_name=logic_die_normalization_hbm_top \
  -rd in_def="$def" \
  -rd in_files="$cell_gds" \
  -rd seal_file= \
  -rd out_file="$output" \
  -rd tech_file="$tech" \
  -rd layer_map= \
  -r "$converter" >> "$log" 2>&1
rc=$?
set -e
echo "WBQ_RTL_GDS_EXIT_CODE=$rc" >> "$log"
echo "WBQ_RTL_GDS_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$log"

test "$rc" -eq 0
test -s "$output"
echo "WBQ_RTL_GDS_OUTPUT_SHA256=$(sha256sum "$output" | awk '{print $1}')" >> "$log"
echo "NORMALIZATION_HBM_WBQ_PHASE7_RTL_GDS_STREAMOUT PASS gds=$output" | tee -a "$log"
