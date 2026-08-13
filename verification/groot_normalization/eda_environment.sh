#!/usr/bin/env bash
# Shared, portable EDA paths for the normalization physical experiments.
# Callers may override every path through the corresponding environment variable.

repo_root="${STOB_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
orfs_root="${ORFS_ROOT:-${HOME}/OpenROAD-flow-scripts}"
orfs_flow="${ORFS_FLOW_ROOT:-${orfs_root}/flow}"
sky130hd_platform="${SKY130HD_PLATFORM:-${orfs_flow}/platforms/sky130hd}"
sky130hd_liberty="${SKY130HD_LIBERTY:-${sky130hd_platform}/lib/sky130_fd_sc_hd__tt_025C_1v80.lib}"

if [[ -n "${OPENROAD_EXE:-}" ]]; then
  openroad_exe="${OPENROAD_EXE}"
elif [[ -x "${orfs_root}/tools/install/OpenROAD/bin/openroad" ]]; then
  openroad_exe="${orfs_root}/tools/install/OpenROAD/bin/openroad"
else
  openroad_exe="$(command -v openroad 2>/dev/null || true)"
fi

if [[ -n "${YOSYS_EXE:-}" ]]; then
  yosys_exe="${YOSYS_EXE}"
elif [[ -x "${orfs_root}/tools/install/yosys/bin/yosys" ]]; then
  yosys_exe="${orfs_root}/tools/install/yosys/bin/yosys"
else
  yosys_exe="$(command -v yosys 2>/dev/null || true)"
fi

physical_report_root="${PHYSICAL_REPORT_ROOT:-${repo_root}/reports/groot_normalization/physical_feasibility}"

export STOB_REPO_ROOT="${repo_root}"
export ORFS_ROOT="${orfs_root}"
export ORFS_FLOW_ROOT="${orfs_flow}"
export SKY130HD_PLATFORM="${sky130hd_platform}"
export SKY130HD_LIBERTY="${sky130hd_liberty}"
export OPENROAD_EXE="${openroad_exe}"
export YOSYS_EXE="${yosys_exe}"
export PHYSICAL_REPORT_ROOT="${physical_report_root}"

