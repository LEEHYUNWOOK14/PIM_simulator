#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flow=/home/chandler/OpenROAD-flow-scripts/flow
config="$root/flow/designs/sky130hd/normalization_hbm_feasibility/config.mk"
target_rel=results/sky130hd/normalization_hbm_feasibility/base/3_2_place_iop.odb
target="$flow/$target_rel"
netlist="$root/reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_sky130.v"

cd "$flow"
make DESIGN_CONFIG="$config" STOB_REPO_ROOT="$root" \
  YOSYS_EXE=/home/chandler/.local/oss-cad-suite/bin/yosys \
  OPENROAD_EXE=/home/chandler/.local/stob-eda/openroad/bin/openroad \
  NUM_CORES=4 SKIP_REPORT_METRICS=1 -j1 "$target_rel"

test -s "$target"
test "$target" -nt "$netlist"
echo "HARDWARE_COST_INTEGRATED_PLACEMENT PASS odb=$target"
