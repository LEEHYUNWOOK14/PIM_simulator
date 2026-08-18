#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"

report="$root/reports/groot_normalization/quad_local_b4"
result="$root/reports/groot_normalization/results/quad_local_b4_actual_trace"
decision="$report/b4_eco_decision.json"
b2_floorplan="$orfs_flow/results/sky130hd/normalization_hbm_quad_local_b2/base/2_floorplan.odb"
b2_floorplan_sdc="$orfs_flow/results/sky130hd/normalization_hbm_quad_local_b2/base/2_floorplan.sdc"
mkdir -p "$report" "$result"

python3 - "$decision" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
if data.get("decision") != "SELECT_B4_RUDY_ROUTABILITY_RESPREAD_ECO":
    raise SystemExit("B4 ECO decision is not selected")
if data.get("authorizes") != []:
    raise SystemExit("pre-cheap B4 decision must remain fail-closed")
print("B4_ECO_INPUT_GATE PASS")
PY

run_log() {
  local log="$1"
  shift
  "$@" > "$log" 2>&1
}

run_log "$report/bitexact_reduction.log" \
  bash verification/groot_normalization/run_mixed_precision_quad_reduction_bitexact_test.sh
run_log "$report/random_ab_differential.log" \
  env B2_REGISTERED_QUAD_COMPLETION=1 \
  bash verification/groot_normalization/run_logic_die_normalization_quad_local_ab_random_test.sh
run_log "$report/writeback_inflight_reset.log" \
  bash verification/groot_normalization/run_normalization_writeback_quad_local_reset_test.sh
run_log "$report/pcu_ab_matrix.log" \
  env B2_REGISTERED_QUAD_COMPLETION=1 \
  bash verification/groot_normalization/run_logic_die_normalization_pcu_top_test.sh
run_log "$report/boundary_ab_matrix.log" \
  env B2_REGISTERED_QUAD_COMPLETION=1 \
  bash verification/groot_normalization/run_normalization_hbm_boundary_test.sh

WBQ_B2=1 WBQ_VARIANT=B4 \
  bash verification/groot_normalization/run_normalization_hbm_quad_local_ab_rtl_check.sh
WBQ_B2=1 WBQ_VARIANT=B4 \
  bash verification/groot_normalization/run_normalization_hbm_quad_local_ab_sky130_mapping.sh
WBQ_B2=1 WBQ_VARIANT=B4 \
  bash verification/groot_normalization/run_wbq_quad_local_actual_trace_test.sh

test -s "$b2_floorplan"
test -s "$b2_floorplan_sdc"
if pgrep -x openroad >/dev/null; then
  echo "OpenROAD process exists before B4 read-only floorplan audit" >&2
  exit 3
fi
{
  echo "WBQ_B4_FLOORPLAN_AUDIT_MODE=READ_ONLY_B2_SAME_NETLIST_AND_GEOMETRY"
  echo "WBQ_B4_FLOORPLAN_ODB_SHA256=$(sha256sum "$b2_floorplan" | awk '{print $1}')"
  echo "WBQ_B4_FLOORPLAN_SDC_SHA256=$(sha256sum "$b2_floorplan_sdc" | awk '{print $1}')"
} > "$report/b4_floorplan_preflight.log"
WBQ_QUAD_FENCE_ODB="$b2_floorplan" WBQ_QUAD_FENCE_DENSITY=0.39 \
  "$openroad_exe" -no_init -exit \
  "$root/verification/groot_normalization/audit_wbq_quad_fence_capacity.tcl" \
  >> "$report/b4_floorplan_preflight.log" 2>&1
grep -q "WBQ_QUAD_FENCE_CAPACITY PASS" "$report/b4_floorplan_preflight.log"

WBQ_B2=1 WBQ_VARIANT=B4 python3 tools/collect_wbq_quad_local_cheap_gate.py
python3 - "$report/cheap_gate_manifest.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
if data.get("overall_result") != "PASS" or len(data.get("gates", [])) != 9:
    raise SystemExit("B4 cheap gate is not 9/9 PASS")
if data.get("authorizes") != ["B4_PLACEMENT", "B4_SINGLE_GLOBAL_ROUTE"]:
    raise SystemExit("B4 cheap authorization mismatch")
print("WBQ_B4_CHEAP_GATES PASS gates=9")
PY
