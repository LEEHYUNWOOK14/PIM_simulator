#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$root/verification/groot_normalization/eda_environment.sh"

result_dir="$orfs_flow/results/sky130hd/normalization_hbm_wbq/base"
cts_manifest="$root/reports/final_integrated_gds_execution/wbq_phase6_cts_manifest.json"
cts_odb="$result_dir/4_cts.odb"
cts_sdc="$result_dir/4_cts.sdc"
prefix="$physical_report_root/logic_die_normalization_hbm_top_wbq_phase6_post_cts"
log="${prefix}_route.log"
guide="${prefix}.route_guide"
congestion="${prefix}.congestion.rpt"
routed_odb="${prefix}_global_route.odb"
routed_sdc="${prefix}_global_route.sdc"
tcl="$root/verification/groot_normalization/normalization_hbm_wbq_phase6_post_cts_route.tcl"

if pgrep -f '[o]penroad.*normalization_hbm_wbq' >/dev/null; then
  echo "wbq OpenROAD job already running; refusing duplicate execution" >&2
  exit 3
fi

test -s "$cts_manifest"
test -s "$cts_odb"
test -s "$cts_sdc"
test -s "$tcl"

for output in "$log" "$guide" "$congestion" "$routed_odb" "$routed_sdc"; do
  if test -e "$output"; then
    echo "existing Phase-6 post-CTS route output prevents overwrite: $output" >&2
    exit 4
  fi
done

python3 - "$cts_manifest" "$cts_odb" "$cts_sdc" <<'PY'
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


manifest_path, odb_path, sdc_path = map(Path, sys.argv[1:])
manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
if manifest.get("gate_pass") is not True:
    raise SystemExit("wbq CTS manifest gate_pass is not true")
if manifest.get("top") != "logic_die_normalization_hbm_top":
    raise SystemExit("wbq CTS manifest top mismatch")
for name, path in (("cts_odb", odb_path), ("cts_sdc", sdc_path)):
    item = manifest.get("artifacts", {}).get(name, {})
    if path.stat().st_size != item.get("bytes") or sha256(path) != item.get("sha256"):
        raise SystemExit(f"wbq CTS {name} bytes/hash mismatch")
print("WBQ_PHASE6_POST_CTS_INPUT_GATE PASS")
PY

export WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd"
export WBQ_CTS_ODB="$cts_odb"
export WBQ_CTS_SDC="$cts_sdc"
export WBQ_ROUTE_OUTPUT_ROOT="$physical_report_root"

{
  echo "WBQ_PHASE6_POST_CTS_GIT_SHA=$(git -C "$root" rev-parse HEAD)"
  echo "WBQ_PHASE6_POST_CTS_ORFS_SHA=$(git -C "$orfs_root" rev-parse HEAD)"
  echo "WBQ_PHASE6_POST_CTS_OPENROAD_VERSION=$($openroad_exe -version 2>&1)"
  echo "WBQ_PHASE6_POST_CTS_MANIFEST_SHA256=$(sha256sum "$cts_manifest" | awk '{print $1}')"
  echo "WBQ_PHASE6_POST_CTS_ODB_SHA256=$(sha256sum "$cts_odb" | awk '{print $1}')"
  echo "WBQ_PHASE6_POST_CTS_SDC_SHA256=$(sha256sum "$cts_sdc" | awk '{print $1}')"
  echo "WBQ_PHASE6_POST_CTS_PIN_MODEL=DISTRIBUTED_INTERNAL_MET5_20UM_LANDING_PAD"
  echo "WBQ_PHASE6_POST_CTS_SIGNAL_LAYERS=met1-met5"
  echo "WBQ_PHASE6_POST_CTS_CLOCK_LAYERS=met2-met5"
  echo "WBQ_PHASE6_POST_CTS_CONGESTION_ITERATIONS=1"
  echo "WBQ_PHASE6_POST_CTS_GLOBAL_ROUTER=CUGR"
  echo "WBQ_PHASE6_POST_CTS_SKIP_LARGE_FANOUT_NETS=5000"
  echo "WBQ_PHASE6_POST_CTS_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$log"

set +e
/usr/bin/time -v "$openroad_exe" -exit -no_init -threads 1 -no_splash "$tcl" >> "$log" 2>&1
rc=$?
set -e
echo "WBQ_PHASE6_POST_CTS_EXIT_CODE=$rc" >> "$log"
echo "WBQ_PHASE6_POST_CTS_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$log"

test "$rc" -eq 0
test -s "$guide"
test -s "$congestion"
test -s "$routed_odb"
test -s "$routed_sdc"
grep -q '^WBQ_PHASE6_POST_CTS_ROUTE_PASS$' "$log"
awk -f "$root/verification/groot_normalization/summarize_congestion.awk" "$congestion" \
  > "${prefix}.congestion.summary"
awk -f "$root/verification/groot_normalization/classify_congestion_sources.awk" "$congestion" \
  > "${prefix}.sources.summary"
echo "NORMALIZATION_HBM_WBQ_PHASE6_POST_CTS_ROUTE PASS guide=$guide" | tee -a "$log"
