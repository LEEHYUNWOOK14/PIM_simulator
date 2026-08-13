#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "$root"
platform=/home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd;lib="$platform/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
yosys=/home/chandler/.local/oss-cad-suite/bin/yosys;openroad=/home/chandler/.local/openroad-pi/usr/bin/openroad;oroot=/home/chandler/.local/openroad-pi
export LD_LIBRARY_PATH="/home/chandler/.local/miniconda3/envs/openroad-py310/lib:${oroot}/usr/lib:${oroot}/usr/lib64:${oroot}/opt/or-tools/lib:${LD_LIBRARY_PATH:-}"
results=reports/groot_normalization/results/mixed_precision_sky130;mkdir -p "$results"
common="rtl/bf16_to_fp32.sv rtl/fp32_to_bf16_rne.sv rtl/fp32_add.sv rtl/fp32_mul.sv rtl/fp32_add_pipe4.sv rtl/fp32_mul_pipe4.sv rtl/bf16_rsqrt_lut256.sv rtl/mixed_precision_bank_reducer4.sv rtl/mixed_precision_bank_reducer4_interleaved.sv rtl/mixed_precision_global_reducer16.sv rtl/mixed_precision_global_reducer16_pipe.sv rtl/mixed_precision_scalar_nr2.sv rtl/mixed_precision_scalar_nr2_pipe.sv rtl/mixed_precision_bank_apply4.sv rtl/mixed_precision_bank_apply4_pipe.sv"
for top in fp32_add_pipe4 fp32_mul_pipe4 mixed_precision_bank_reducer4 mixed_precision_bank_reducer4_interleaved mixed_precision_global_reducer16 mixed_precision_global_reducer16_pipe mixed_precision_scalar_nr2 mixed_precision_scalar_nr2_pipe mixed_precision_bank_apply4 mixed_precision_bank_apply4_pipe;do
 [[ -n "${MIXED_TOP_FILTER:-}" && "$top" != "$MIXED_TOP_FILTER" ]]&&continue
 netlist="$results/${top}.v"
 "$yosys" -Q -q -l "$results/${top}_yosys.log" -p "read_liberty -lib -ignore_miss_func $lib; read_verilog -sv -I. $common; hierarchy -check -top $top; synth -noabc -top $top; flatten; opt_clean; dfflibmap -liberty $lib; abc -liberty $lib; clean -purge; check -assert; stat -liberty $lib; write_verilog -noattr $netlist"
 NORM_LIBERTY="$lib" NORM_TECH_LEF="$platform/lef/sky130_fd_sc_hd_merged.lef" NORM_NETLIST="$root/$netlist" NORM_TOP="$top" "$openroad" -exit verification/groot_normalization/normalization_sky130_sta.tcl >"$results/${top}_sta.log" 2>&1
 echo "MIXED_PRECISION_SKY130 PASS top=$top constraint=10ns"
done
