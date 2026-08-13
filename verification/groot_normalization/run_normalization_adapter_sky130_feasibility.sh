#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
platform=/home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd
lib="$platform/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
lef="$platform/lef/sky130_fd_sc_hd_merged.lef"
yosys=/home/chandler/.local/oss-cad-suite/bin/yosys
openroad=/home/chandler/.local/openroad-pi/usr/bin/openroad
oroot=/home/chandler/.local/openroad-pi
export LD_LIBRARY_PATH="/home/chandler/.local/miniconda3/envs/openroad-py310/lib:${oroot}/usr/lib:${oroot}/usr/lib64:${oroot}/opt/or-tools/lib:${LD_LIBRARY_PATH:-}"
results=reports/groot_normalization/physical_feasibility
mkdir -p "$results"
top=normalization_hbm_boundary_adapter
netlist="$results/${top}_sky130.v"
log="$results/${top}_sky130_yosys.log"

"$yosys" -Q -l "$log" -p "
  read_liberty -lib -ignore_miss_func $lib;
  read_verilog -sv -I. rtl/normalization_hbm_boundary_adapter.sv;
  hierarchy -check -top $top;
  synth -noabc -top $top;
  flatten;
  opt_clean;
  dfflibmap -liberty $lib;
  abc -liberty $lib -D 100000 \
    -dont_use sky130_fd_sc_hd__lpflow_* \
    -dont_use sky130_fd_sc_hd__probe*;
  clean -purge;
  hilomap -singleton \
    -hicell sky130_fd_sc_hd__conb_1 HI \
    -locell sky130_fd_sc_hd__conb_1 LO;
  check -assert;
  stat -liberty $lib;
  write_verilog -noattr $netlist
"

NORM_LIBERTY="$lib" NORM_TECH_LEF="$lef" NORM_NETLIST="$root/$netlist" \
NORM_TOP="$top" NORM_CLOCK_PERIOD_NS=1000.0 \
  "$openroad" -exit verification/groot_normalization/normalization_physical_feasibility_sta.tcl \
  >"$results/${top}_sky130_sta.log" 2>&1

grep -q "Found and reported 0 problems" "$log"
grep -q "PHYS_FEAS_MAX_PATH_END" "$results/${top}_sky130_sta.log"
echo "NORMALIZATION_ADAPTER_SKY130_FEASIBILITY PASS"
