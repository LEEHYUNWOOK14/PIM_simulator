#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$root/verification/groot_normalization/eda_environment.sh"
if [[ "${WBQ_B2:-0}" == 1 ]]; then
  nickname=normalization_hbm_quad_local_b2
  top=logic_die_normalization_hbm_quad_local_b2_top
  report_dir="$root/reports/groot_normalization/quad_local_b2"
  prefix=b2
  audit_args=(--top "$top" --require-b2-completion)
else
  nickname=normalization_hbm_quad_local_ab
  top=logic_die_normalization_hbm_quad_local_ab_top
  report_dir="$root/reports/groot_normalization/quad_local_ab"
  prefix=b
  audit_args=(--top "$top")
fi
config="$root/flow/designs/sky130hd/$nickname/config.mk"
result_dir="$orfs_flow/results/sky130hd/$nickname/base"
log="$report_dir/${prefix}_floorplan_preflight.log"
odb="$result_dir/2_floorplan.odb"
mkdir -p "$report_dir"

test -s "$report_dir/${top}_sky130.v"
python3 "$root/tools/audit_wbq_quad_local_netlist.py" \
  --json "$report_dir/${prefix}_mapped_hierarchy.json" --stage mapped \
  --output "$report_dir/${prefix}_mapped_locality_audit.json" \
  "${audit_args[@]}"

/usr/bin/time -v make -C "$orfs_flow" \
  DESIGN_CONFIG="$config" STOB_REPO_ROOT="$root" \
  YOSYS_EXE="$yosys_exe" OPENROAD_EXE="$openroad_exe" \
  NUM_CORES="${NUM_CORES:-16}" SKIP_REPORT_METRICS=1 -j1 floorplan \
  > "$log" 2>&1
test -s "$odb"
WBQ_QUAD_FENCE_ODB="$odb" WBQ_QUAD_FENCE_DENSITY=0.39 \
  "$openroad_exe" -no_init -exit \
  "$root/verification/groot_normalization/audit_wbq_quad_fence_capacity.tcl" \
  >> "$log" 2>&1
grep -q "WBQ_QUAD_FENCE_CREATE PASS" "$log"
grep -q "WBQ_QUAD_FENCE_CAPACITY PASS" "$log"
echo "WBQ_QUAD_LOCAL_FLOORPLAN_PREFLIGHT PASS odb=$odb" | tee -a "$log"
