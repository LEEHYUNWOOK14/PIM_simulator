#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workspace="${repo_root}/b0_baseline_experiment"
power="${workspace}/results/power"
netlist="${workspace}/orfs/results/sky130hd/b0_bank_only_baseline/base/6_final.v"
cells=/home/chandler/.local/oss-cad-suite/examples/eqy/spm/sky130_fd_sc_hd.v
primitives=/home/chandler/.local/oss-cad-suite/examples/eqy/spm/primitives.v
mkdir -p "${power}"
cd "${repo_root}"
iverilog -g2012 -s b0_gate_activity_tb -o "${power}/b0_gate_activity.out" \
  "${primitives}" "${cells}" "${netlist}" b0_baseline_experiment/tb/b0_gate_activity_tb.sv \
  >"${power}/b0_gate_compile.log" 2>&1
vvp "${power}/b0_gate_activity.out" >"${power}/b0_gate_run.log" 2>&1
grep -q B0_GATE_ACTIVITY_TB\ PASS "${power}/b0_gate_run.log"
printf 'B0 gate activity VCD complete\n'
