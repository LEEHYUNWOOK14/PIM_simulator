#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$root/verification/groot_normalization/eda_environment.sh"

config="$root/flow/designs/sky130hd/normalization_hbm_wbq/config.mk"
result_dir="$orfs_flow/results/sky130hd/normalization_hbm_wbq/base"
decision="$root/reports/final_integrated_gds_execution/wbq_post_route_decision.json"
placement_manifest="$root/reports/final_integrated_gds_execution/wbq_placement_manifest.json"
gate_manifest="$root/reports/final_integrated_gds_execution/wbq_phase6_input_gate.json"
log="$physical_report_root/logic_die_normalization_hbm_top_wbq_phase6_cts.log"
place_odb="$result_dir/3_place.odb"
place_sdc="$result_dir/3_place.sdc"
cts_odb="$result_dir/4_cts.odb"
cts_sdc="$result_dir/4_cts.sdc"

if pgrep -f '[o]penroad.*normalization_hbm_wbq' >/dev/null; then
  echo "wbq OpenROAD job already running; refusing duplicate execution" >&2
  exit 3
fi

test -x "$openroad_exe"
test -x "$yosys_exe"
test -s "$config"
test -s "$decision"
test -s "$placement_manifest"
test -s "$place_odb"
test -s "$place_sdc"

# Never silently reuse or overwrite a partial/old CTS checkpoint. A failed
# attempt must first be audited and explicitly archived by the operator.
for output in \
  "$result_dir/4_1_cts.odb" \
  "$result_dir/4_1_error.odb" \
  "$result_dir/4_cts.odb" \
  "$result_dir/4_cts.sdc"; do
  if test -e "$output"; then
    echo "existing Phase-6 output prevents a fresh CTS run: $output" >&2
    exit 4
  fi
done

python3 "$root/tools/verify_wbq_phase6_gate.py" \
  --decision "$decision" \
  --placement "$placement_manifest" \
  --output "$gate_manifest"

mkdir -p "$physical_report_root"
{
  echo "WBQ_PHASE6_CTS_GIT_SHA=$(git -C "$root" rev-parse HEAD)"
  echo "WBQ_PHASE6_CTS_ORFS_SHA=$(git -C "$orfs_root" rev-parse HEAD)"
  echo "WBQ_PHASE6_CTS_OPENROAD_VERSION=$($openroad_exe -version 2>&1)"
  echo "WBQ_PHASE6_CTS_DECISION_SHA256=$(sha256sum "$decision" | awk '{print $1}')"
  echo "WBQ_PHASE6_CTS_GATE_SHA256=$(sha256sum "$gate_manifest" | awk '{print $1}')"
  echo "WBQ_PHASE6_CTS_PLACE_ODB_SHA256=$(sha256sum "$place_odb" | awk '{print $1}')"
  echo "WBQ_PHASE6_CTS_PLACE_SDC_SHA256=$(sha256sum "$place_sdc" | awk '{print $1}')"
  echo "WBQ_PHASE6_CTS_SIGNAL_LAYERS=met1-met5"
  echo "WBQ_PHASE6_CTS_CLOCK_LAYERS=met2-met5"
  echo "WBQ_PHASE6_CTS_POLICY=ORFS_TRITONCTS_REPAIR_CLOCK_NETS"
  echo "WBQ_PHASE6_CTS_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$log"

set +e
/usr/bin/time -v make -C "$orfs_flow" \
  DESIGN_CONFIG="$config" STOB_REPO_ROOT="$root" \
  YOSYS_EXE="$yosys_exe" OPENROAD_EXE="$openroad_exe" \
  NUM_CORES="${NUM_CORES:-16}" SKIP_REPORT_METRICS=1 \
  MIN_ROUTING_LAYER=met1 MIN_CLK_ROUTING_LAYER=met2 MAX_ROUTING_LAYER=met5 \
  -j1 cts >> "$log" 2>&1
rc=$?
set -e
echo "WBQ_PHASE6_CTS_EXIT_CODE=$rc" >> "$log"
echo "WBQ_PHASE6_CTS_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$log"

test "$rc" -eq 0
test -s "$cts_odb"
test -s "$cts_sdc"
grep -q 'Running cts.tcl, stage 4_1_cts' "$log"
echo "NORMALIZATION_HBM_WBQ_PHASE6_CTS PASS odb=$cts_odb" | tee -a "$log"
