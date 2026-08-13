#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
platform=/home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd
sta=/home/chandler/.local/stob-eda/openroad/bin/sta
results="$root/reports/groot_normalization/physical_feasibility"
netlist="$results/logic_die_normalization_hbm_top_sky130.v"
log="$results/logic_die_normalization_hbm_top_sky130_sta.log"

test -s "$netlist"
export PF_LIBERTY="$platform/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
export PF_NETLIST="$netlist"
export PF_TOP=logic_die_normalization_hbm_top
export PF_CLOCK_PERIOD_NS=1000.0

{
  echo "PF_SOURCE_NETLIST_SHA256=$(sha256sum "$netlist" | awk '{print $1}')"
  "$sta" -no_init -exit "$root/hardware_cost/physical_feasibility/integrated_sta.tcl"
} >"$log" 2>&1
grep -q '^PHYS_FEAS_CHECK_SETUP_END$' "$log"
grep -q '^PHYS_FEAS_UNCONSTRAINED_END$' "$log"
grep -q '^PHYS_FEAS_MAX_PATH_END$' "$log"
echo "HARDWARE_COST_INTEGRATED_STA PASS log=$log"
