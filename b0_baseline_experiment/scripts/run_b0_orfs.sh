#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workspace="${repo_root}/b0_baseline_experiment"
orfs_root="${ORFS_ROOT:-/home/chandler/OpenROAD-flow-scripts}"
flow="${orfs_root}/flow"
work_home="${workspace}/orfs"
result_dir="${workspace}/results/physical"
log_dir="${result_dir}/logs"
mkdir -p "${work_home}" "${result_dir}" "${log_dir}"

target="${1:-all}"
config="${workspace}/config/orfs_config.mk"
make_args=(
  DESIGN_CONFIG="${config}" STOB_REPO_ROOT="${repo_root}" WORK_HOME="${work_home}"
  YOSYS_EXE=/home/chandler/.local/oss-cad-suite/bin/yosys
  OPENROAD_EXE=/home/chandler/.local/stob-eda/openroad/bin/openroad
  KLAYOUT_CMD=/usr/bin/klayout NUM_CORES=4 DETAILED_ROUTE_END_ITERATION=0
  MATCH_CELL_FOOTPRINT= SKIP_REPORT_METRICS=1 ENABLE_PLACE_REPAIR_TIMING=0
  ENABLE_DPO=0 SKIP_CTS_REPAIR_TIMING=1 SKIP_INCREMENTAL_REPAIR=1
  SKIP_ANTENNA_REPAIR=1 SKIP_ANTENNA_REPAIR_POST_DRT=1 RECOVER_POWER=0
)

cd "${flow}"
if [[ "${target}" == all ]]; then
  make "${make_args[@]}" -j1 2>&1 | tee "${log_dir}/orfs_all.log"
else
  make "${make_args[@]}" -j1 "${target}" 2>&1 | tee "${log_dir}/orfs_${target}.log"
fi

orfs_result="${work_home}/results/sky130hd/b0_bank_only_baseline/base"
orfs_report="${work_home}/reports/sky130hd/b0_bank_only_baseline/base"
orfs_log="${work_home}/logs/sky130hd/b0_bank_only_baseline/base"
printf 'orfs_result=%s\norfs_report=%s\norfs_log=%s\n' "${orfs_result}" "${orfs_report}" "${orfs_log}" >"${result_dir}/orfs_paths.txt"
printf 'B0 ORFS target=%s complete\n' "${target}"
