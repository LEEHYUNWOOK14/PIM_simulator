#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$root/verification/groot_normalization/eda_environment.sh"

manifest="$root/reports/final_integrated_gds_execution/wbq_phase6_post_cts_route_manifest.json"
prefix="$physical_report_root/logic_die_normalization_hbm_top_wbq_phase7_detailed_route"
input_prefix="$physical_report_root/logic_die_normalization_hbm_top_wbq_phase6_post_cts_global_route"
input_odb="${input_prefix}.odb"
input_sdc="${input_prefix}.sdc"
log="${prefix}.log"
tcl="$root/verification/groot_normalization/normalization_hbm_wbq_phase7_detailed_route.tcl"

if pgrep -f '[o]penroad.*normalization_hbm_wbq' >/dev/null; then
  echo "wbq OpenROAD job already running; refusing duplicate execution" >&2
  exit 3
fi

test -s "$manifest"
test -s "$input_odb"
test -s "$input_sdc"
test -s "$tcl"

for suffix in log odb sdc def v drc.rpt maze.log; do
  output="${prefix}.${suffix}"
  if test -e "$output"; then
    echo "existing Phase-7 output prevents overwrite: $output" >&2
    exit 4
  fi
done

python3 - "$manifest" "$input_odb" "$input_sdc" <<'PY'
import hashlib
import json
import shutil
import sys
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


manifest_path, odb_path, sdc_path = map(Path, sys.argv[1:])
manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
if manifest.get("gate_pass") is not True or manifest.get("verdict") != "PASS_PF4_POST_CTS":
    raise SystemExit("post-CTS route manifest does not authorize detailed route")
for name, path in (("routed_odb", odb_path), ("routed_sdc", sdc_path)):
    item = manifest.get("artifacts", {}).get(name, {})
    if path.stat().st_size != item.get("bytes") or sha256(path) != item.get("sha256"):
        raise SystemExit(f"Phase-7 input {name} bytes/hash mismatch")
memory = Path("/proc/meminfo").read_text(encoding="ascii")
available_kib = int(next(line.split()[1] for line in memory.splitlines() if line.startswith("MemAvailable:")))
if available_kib < 32 * 1024 * 1024:
    raise SystemExit(f"Phase-7 requires at least 32 GiB available RAM; found {available_kib / 1024 / 1024:.2f} GiB")
free_bytes = shutil.disk_usage(manifest_path.parent).free
if free_bytes < 40 * 1024**3:
    raise SystemExit(f"Phase-7 requires at least 40 GiB free disk; found {free_bytes / 1024**3:.2f} GiB")
print(f"WBQ_PHASE7_INPUT_GATE PASS available_ram_gib={available_kib / 1024 / 1024:.2f} free_disk_gib={free_bytes / 1024**3:.2f}")
PY

export WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd"
export WBQ_GRT_ODB="$input_odb"
export WBQ_GRT_SDC="$input_sdc"
export WBQ_DRT_OUTPUT_ROOT="$physical_report_root"

{
  echo "WBQ_PHASE7_GIT_SHA=$(git -C "$root" rev-parse HEAD)"
  echo "WBQ_PHASE7_ORFS_SHA=$(git -C "$orfs_root" rev-parse HEAD)"
  echo "WBQ_PHASE7_OPENROAD_VERSION=$($openroad_exe -version 2>&1)"
  echo "WBQ_PHASE7_ROUTE_MANIFEST_SHA256=$(sha256sum "$manifest" | awk '{print $1}')"
  echo "WBQ_PHASE7_INPUT_ODB_SHA256=$(sha256sum "$input_odb" | awk '{print $1}')"
  echo "WBQ_PHASE7_INPUT_SDC_SHA256=$(sha256sum "$input_sdc" | awk '{print $1}')"
  echo "WBQ_PHASE7_SIGNAL_LAYERS=met1-met5"
  echo "WBQ_PHASE7_CLOCK_LAYERS=met2-met5"
  echo "WBQ_PHASE7_END_ITERATION=64"
  echo "WBQ_PHASE7_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  free -h
  df -h "$root"
} > "$log"

set +e
/usr/bin/time -v "$openroad_exe" -exit -no_init -threads "${NUM_CORES:-16}" -no_splash "$tcl" >> "$log" 2>&1
rc=$?
set -e
echo "WBQ_PHASE7_EXIT_CODE=$rc" >> "$log"
echo "WBQ_PHASE7_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$log"

test "$rc" -eq 0
for suffix in odb sdc def v; do
  test -s "${prefix}.${suffix}"
done
for suffix in drc.rpt maze.log; do
  test -f "${prefix}.${suffix}"
done
grep -q '^WBQ_PHASE7_DESIGN_IS_ROUTED 1$' "$log"
grep -q '^WBQ_PHASE7_DETAILED_ROUTE_PASS$' "$log"
echo "NORMALIZATION_HBM_WBQ_PHASE7_DETAILED_ROUTE PASS odb=${prefix}.odb" | tee -a "$log"
