#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
flow=/home/chandler/OpenROAD-flow-scripts/flow
config="$root/flow/designs/sky130hd/normalization_hbm_feasibility/config.mk"
cd "$flow"
make DESIGN_CONFIG="$config" STOB_REPO_ROOT="$root" \
  YOSYS_EXE=/home/chandler/.local/oss-cad-suite/bin/yosys \
  OPENROAD_EXE=/home/chandler/.local/stob-eda/openroad/bin/openroad \
  NUM_CORES=4 SKIP_REPORT_METRICS=1 -j1 grt

result_dir="$flow/results/sky130hd/normalization_hbm_feasibility/base"
test -s "$result_dir/5_1_grt.odb"
echo "NORMALIZATION_HBM_TOP_GLOBAL_ROUTE PASS odb=$result_dir/5_1_grt.odb"
