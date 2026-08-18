#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"

report="$root/reports/groot_normalization/quad_local_b25"
result="$root/reports/groot_normalization/results/quad_local_b25_actual_trace"
decision="$report/b25_eco_decision.json"
config="$root/flow/designs/sky130hd/normalization_hbm_quad_local_b25/config.mk"
floorplan="$orfs_flow/results/sky130hd/normalization_hbm_quad_local_b25/base/2_floorplan.odb"
mkdir -p "$report" "$result"

python3 - "$decision" <<'PY'
import json, sys
d=json.load(open(sys.argv[1]))
if d.get("decision") != "SELECT_B25_AGGREGATED_COMPLETION_DESCRIPTOR_ECO" or d.get("authorizes") != []:
    raise SystemExit("B25 decision is not fail-closed")
print("B25_ECO_INPUT_GATE PASS")
PY

run_log() { local log="$1"; shift; "$@" > "$log" 2>&1; }
run_log "$report/bitexact_reduction.log" bash verification/groot_normalization/run_mixed_precision_quad_reduction_bitexact_test.sh
run_log "$report/random_ab_differential.log" env B2_REGISTERED_QUAD_COMPLETION=1 bash verification/groot_normalization/run_logic_die_normalization_quad_local_ab_random_test.sh
run_log "$report/writeback_inflight_reset.log" bash verification/groot_normalization/run_normalization_writeback_quad_local_reset_test.sh
run_log "$report/pcu_ab_matrix.log" env B2_REGISTERED_QUAD_COMPLETION=1 bash verification/groot_normalization/run_logic_die_normalization_pcu_top_test.sh
run_log "$report/boundary_ab_matrix.log" env B2_REGISTERED_QUAD_COMPLETION=1 bash verification/groot_normalization/run_normalization_hbm_boundary_test.sh

WBQ_B2=1 WBQ_VARIANT=B25 bash verification/groot_normalization/run_normalization_hbm_quad_local_ab_rtl_check.sh
WBQ_B2=1 WBQ_VARIANT=B25 bash verification/groot_normalization/run_normalization_hbm_quad_local_ab_sky130_mapping.sh
WBQ_B2=1 WBQ_VARIANT=B25 bash verification/groot_normalization/run_wbq_quad_local_actual_trace_test.sh

if pgrep -x openroad >/dev/null; then
  echo "OpenROAD process exists before B25 floorplan" >&2
  exit 3
fi
/usr/bin/time -v make -C "$orfs_flow" DESIGN_CONFIG="$config" STOB_REPO_ROOT="$root" \
  YOSYS_EXE="$yosys_exe" OPENROAD_EXE="$openroad_exe" NUM_CORES=16 SKIP_REPORT_METRICS=1 -j1 floorplan \
  > "$report/b25_floorplan_preflight.log" 2>&1
test -s "$floorplan"
WBQ_QUAD_FENCE_ODB="$floorplan" WBQ_QUAD_FENCE_DENSITY=0.39 \
  "$openroad_exe" -no_init -exit verification/groot_normalization/audit_wbq_quad_fence_capacity.tcl \
  >> "$report/b25_floorplan_preflight.log" 2>&1
grep -q "WBQ_QUAD_FENCE_CAPACITY PASS" "$report/b25_floorplan_preflight.log"

WBQ_B2=1 WBQ_VARIANT=B25 python3 tools/collect_wbq_quad_local_cheap_gate.py
python3 - "$report/cheap_gate_manifest.json" <<'PY'
import json, sys
d=json.load(open(sys.argv[1]))
if d.get("overall_result") != "PASS" or d.get("authorizes") != ["B25_PLACEMENT", "B25_SINGLE_GLOBAL_ROUTE"]:
    raise SystemExit("B25 cheap gate authorization mismatch")
print("WBQ_B25_CHEAP_GATES PASS gates=9")
PY
