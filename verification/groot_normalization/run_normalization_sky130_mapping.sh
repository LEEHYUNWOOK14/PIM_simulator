#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "$root"
platform="/home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd"
lib="$platform/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
yosys="/home/chandler/.local/oss-cad-suite/bin/yosys"
openroad="/home/chandler/.local/openroad-pi/usr/bin/openroad"
openroad_root="/home/chandler/.local/openroad-pi"
export LD_LIBRARY_PATH="/home/chandler/.local/miniconda3/envs/openroad-py310/lib:${openroad_root}/usr/lib:${openroad_root}/usr/lib64:${openroad_root}/opt/or-tools/lib:${LD_LIBRARY_PATH:-}"
results="reports/groot_normalization/results/sky130_mapping";mkdir -p "$results"
top="bank_normalization_pipelined_vector_reducer"
for format in 0 1;do
 dtype="fp16";if [[ "$format" == 1 ]];then dtype="bf16";fi
 for lanes in 2 4;do
  stem="${top}_${dtype}_l${lanes}"
  netlist="$results/${stem}.v"
  "$yosys" -Q -q -l "$results/${stem}_yosys.log" -p \
   "read_liberty -lib -ignore_miss_func ${lib}; read_verilog -sv rtl/fp16_add.sv rtl/fp16_mul.sv rtl/bf16_add.sv rtl/bf16_mul.sv rtl/bank_normalization_pipelined_vector_reducer.sv; chparam -set DATA_FORMAT ${format} -set LANES ${lanes} ${top}; hierarchy -check -top ${top}; synth -noabc -top ${top}; flatten; opt_clean; dfflibmap -liberty ${lib}; abc -liberty ${lib}; clean -purge; check -assert; stat -liberty ${lib}; write_verilog -noattr ${netlist}"
  NORM_LIBERTY="$lib" NORM_TECH_LEF="$platform/lef/sky130_fd_sc_hd_merged.lef" \
   NORM_NETLIST="$root/$netlist" NORM_TOP="$top" \
   "$openroad" -exit verification/groot_normalization/normalization_sky130_sta.tcl \
   >"$results/${stem}_sta.log" 2>&1
 done
done
python3 tools/collect_normalization_sky130_metrics.py
echo "NORMALIZATION_SKY130_MAPPING PASS formats=FP16,BF16 lanes=2,4 clock=100MHz"
