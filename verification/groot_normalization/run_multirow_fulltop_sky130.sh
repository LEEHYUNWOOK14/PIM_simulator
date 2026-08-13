#!/usr/bin/env bash
set -euo pipefail
lanes="${1:-8}";engines="${2:-4}";root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "$root"
platform=/home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd;lib="$platform/lib/sky130_fd_sc_hd__tt_025C_1v80.lib";yosys=/home/chandler/.local/oss-cad-suite/bin/yosys;openroad=/home/chandler/.local/openroad-pi/usr/bin/openroad;oroot=/home/chandler/.local/openroad-pi
export LD_LIBRARY_PATH="/home/chandler/.local/miniconda3/envs/openroad-py310/lib:${oroot}/usr/lib:${oroot}/usr/lib64:${oroot}/opt/or-tools/lib:${LD_LIBRARY_PATH:-}"
results=reports/groot_normalization/results/multirow_fulltop_sky130;mkdir -p "$results";name="multirow_l${lanes}_e${engines}";netlist="$results/${name}.v";top=mixed_precision_multirow_datapath
common="rtl/bf16_to_fp32.sv rtl/fp32_to_bf16_rne.sv rtl/fp32_add.sv rtl/fp32_mul.sv rtl/fp32_add_pipe4.sv rtl/fp32_mul_pipe4.sv rtl/bf16_rsqrt_lut256.sv rtl/mixed_precision_bank_reducer_pingpong.sv rtl/mixed_precision_global_reducer16_pipe.sv rtl/mixed_precision_scalar_nr2_pipe.sv rtl/mixed_precision_scalar_engine_array.sv rtl/mixed_precision_bank_apply_pipe.sv rtl/mixed_precision_row_context_table.sv rtl/mixed_precision_multirow_datapath.sv"
"$yosys" -Q -q -l "$results/${name}_yosys.log" -p "read_liberty -lib -ignore_miss_func $lib; read_verilog -sv -I. $common; chparam -set LANES $lanes -set SCALAR_ENGINES $engines $top; hierarchy -check -top $top; synth -noabc -top $top; flatten; opt_clean; dfflibmap -liberty $lib; abc -liberty $lib; clean -purge; check -assert; stat -liberty $lib; write_verilog -noattr $netlist"
NORM_LIBERTY="$lib" NORM_TECH_LEF="$platform/lef/sky130_fd_sc_hd_merged.lef" NORM_NETLIST="$root/$netlist" NORM_TOP="$top" "$openroad" -exit verification/groot_normalization/normalization_sky130_sta.tcl >"$results/${name}_sta.log" 2>&1
echo "MULTIROW_FULLTOP_SKY130 PASS lanes=$lanes engines=$engines"
