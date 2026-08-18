#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"
report="$root/reports/groot_normalization/quad_local_b5"
decision="$report/b5_eco_decision.json"
b2_floorplan="$orfs_flow/results/sky130hd/normalization_hbm_quad_local_b2/base/2_floorplan.odb"
b2_floorplan_sdc="$orfs_flow/results/sky130hd/normalization_hbm_quad_local_b2/base/2_floorplan.sdc"
mkdir -p "$report" "$root/reports/groot_normalization/results/quad_local_b5_actual_trace"
python3 - "$decision" <<'PY'
import json, sys
data=json.load(open(sys.argv[1]))
if data.get("decision") != "SELECT_B5_DIAMOND_LEGALIZER_ECO" or data.get("authorizes") != []:
    raise SystemExit("B5 ECO is not selected fail-closed")
print("B5_ECO_INPUT_GATE PASS")
PY
run_log() { local log="$1"; shift; "$@" > "$log" 2>&1; }
run_log "$report/bitexact_reduction.log" bash verification/groot_normalization/run_mixed_precision_quad_reduction_bitexact_test.sh
run_log "$report/random_ab_differential.log" env B2_REGISTERED_QUAD_COMPLETION=1 bash verification/groot_normalization/run_logic_die_normalization_quad_local_ab_random_test.sh
run_log "$report/writeback_inflight_reset.log" bash verification/groot_normalization/run_normalization_writeback_quad_local_reset_test.sh
run_log "$report/pcu_ab_matrix.log" env B2_REGISTERED_QUAD_COMPLETION=1 bash verification/groot_normalization/run_logic_die_normalization_pcu_top_test.sh
run_log "$report/boundary_ab_matrix.log" env B2_REGISTERED_QUAD_COMPLETION=1 bash verification/groot_normalization/run_normalization_hbm_boundary_test.sh
WBQ_B2=1 WBQ_VARIANT=B5 bash verification/groot_normalization/run_normalization_hbm_quad_local_ab_rtl_check.sh
WBQ_B2=1 WBQ_VARIANT=B5 bash verification/groot_normalization/run_normalization_hbm_quad_local_ab_sky130_mapping.sh
WBQ_B2=1 WBQ_VARIANT=B5 bash verification/groot_normalization/run_wbq_quad_local_actual_trace_test.sh
test -s "$b2_floorplan"; test -s "$b2_floorplan_sdc"
if pgrep -x openroad >/dev/null; then echo "OpenROAD exists before B5 read-only audit" >&2; exit 3; fi
{
  echo "WBQ_B5_FLOORPLAN_AUDIT_MODE=READ_ONLY_B2_SAME_NETLIST_AND_GEOMETRY"
  echo "WBQ_B5_FLOORPLAN_ODB_SHA256=$(sha256sum "$b2_floorplan" | awk '{print $1}')"
  echo "WBQ_B5_FLOORPLAN_SDC_SHA256=$(sha256sum "$b2_floorplan_sdc" | awk '{print $1}')"
} > "$report/b5_floorplan_preflight.log"
WBQ_QUAD_FENCE_ODB="$b2_floorplan" WBQ_QUAD_FENCE_DENSITY=0.39 "$openroad_exe" -no_init -exit \
  "$root/verification/groot_normalization/audit_wbq_quad_fence_capacity.tcl" >> "$report/b5_floorplan_preflight.log" 2>&1
grep -q "WBQ_QUAD_FENCE_CAPACITY PASS" "$report/b5_floorplan_preflight.log"
WBQ_B2=1 WBQ_VARIANT=B5 python3 tools/collect_wbq_quad_local_cheap_gate.py
python3 - "$report/cheap_gate_manifest.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
if d.get("overall_result")!="PASS" or len(d.get("gates",[]))!=9 or d.get("authorizes") != ["B5_PLACEMENT","B5_SINGLE_GLOBAL_ROUTE"]:
    raise SystemExit("B5 cheap gate/authorization mismatch")
print("WBQ_B5_CHEAP_GATES PASS gates=9")
PY
