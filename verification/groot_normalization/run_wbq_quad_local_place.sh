#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$root/verification/groot_normalization/eda_environment.sh"
if [[ "${WBQ_B2:-0}" == 1 ]]; then
  nickname=normalization_hbm_quad_local_b2
  report_dir="$root/reports/groot_normalization/quad_local_b2"
  prefix=b2
else
  nickname=normalization_hbm_quad_local_ab
  report_dir="$root/reports/groot_normalization/quad_local_ab"
  prefix=b
fi
config="$root/flow/designs/sky130hd/$nickname/config.mk"
result_dir="$orfs_flow/results/sky130hd/$nickname/base"
log="$report_dir/${prefix}_place.log"
gate="$report_dir/cheap_gate_manifest.json"
resized_odb="$result_dir/3_4_place_resized.odb"
rescue_tcl="$root/verification/groot_normalization/wbq_quad_local_respread_detail.tcl"
finalize_tcl="$root/verification/groot_normalization/wbq_quad_local_finalize_detail.tcl"
pre_incremental_odb="$result_dir/3_place.odb.pre_incremental.odb"
rescue_from_resized=0
# ORFS rotates/truncates failed temporary logs on restart, so the rescue
# decision must be based on durable stage artifacts rather than a log token.
# A saved resize DB without a final place DB means the expensive synthesis,
# floorplan, GPL, and repair stages completed but detailed placement did not.
if test -s "$resized_odb" && ! test -s "$result_dir/3_place.odb"; then
  rescue_from_resized=1
fi

python3 - "$gate" <<'PY'
import json, sys
data=json.load(open(sys.argv[1], encoding="utf-8"))
if data.get("overall_result") != "PASS":
    raise SystemExit("quad-local cheap gate is not PASS")
print("WBQ_QUAD_LOCAL_PLACE_GATE PASS")
PY
if pgrep -f "[o]penroad.*$nickname" >/dev/null; then
  echo "B OpenROAD job already running; refusing duplicate" >&2
  exit 3
fi
{
  echo "WBQ_QUAD_PLACE_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "WBQ_QUAD_PLACE_GATE_SHA256=$(sha256sum "$gate" | awk '{print $1}')"
} > "$log"
set +e
if test "$rescue_from_resized" -eq 1; then
  echo "WBQ_QUAD_PLACE_RESPREAD_RESCUE input=$resized_odb" >> "$log"
  export WBQ_PLATFORM_ROOT="$orfs_flow/platforms/sky130hd"
  export WBQ_QUAD_RESIZED_ODB="$resized_odb"
  export WBQ_QUAD_FLOORPLAN_SDC="$result_dir/2_floorplan.sdc"
  export WBQ_QUAD_RESPREAD_ODB="$result_dir/3_4_place_respread.odb"
  export WBQ_QUAD_PLACE_ODB="$result_dir/3_place.odb"
  export WBQ_QUAD_PLACE_SDC="$result_dir/3_place.sdc"
  selected_tcl="$rescue_tcl"
  if test -s "$pre_incremental_odb"; then
    export WBQ_QUAD_PRE_INCREMENTAL_ODB="$pre_incremental_odb"
    selected_tcl="$finalize_tcl"
    echo "WBQ_QUAD_PLACE_FINALIZE_RESCUE input=$pre_incremental_odb" >> "$log"
  fi
  /usr/bin/time -v "$openroad_exe" -exit -no_init \
    -threads "${NUM_CORES:-16}" -no_splash "$selected_tcl" \
    >> "$log" 2>&1
else
  /usr/bin/time -v make -C "$orfs_flow" \
    DESIGN_CONFIG="$config" STOB_REPO_ROOT="$root" \
    YOSYS_EXE="$yosys_exe" OPENROAD_EXE="$openroad_exe" \
    NUM_CORES="${NUM_CORES:-16}" SKIP_REPORT_METRICS=1 -j1 place \
    >> "$log" 2>&1
fi
rc=$?
set -e
echo "WBQ_QUAD_PLACE_EXIT_CODE=$rc" >> "$log"
test "$rc" -eq 0
test -s "$result_dir/3_place.odb"
test -s "$result_dir/3_place.sdc"
WBQ_QUAD_PLACE_ODB="$result_dir/3_place.odb" \
WBQ_QUAD_PLACE_SDC="$result_dir/3_place.sdc" \
  "$openroad_exe" -no_init -exit \
  "$root/verification/groot_normalization/audit_wbq_quad_local_placement.tcl" \
  >> "$log" 2>&1
grep -q "WBQ_QUAD_LOCAL_PLACEMENT_AUDIT PASS" "$log"
echo "WBQ_QUAD_LOCAL_PLACE PASS odb=$result_dir/3_place.odb" | tee -a "$log"
