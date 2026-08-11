#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "${root}"
for engines in 4 8 16;do
 log="reports/groot_normalization/results/logic_normalization_dispatcher_e${engines}_yosys.log"
 bash rtl/yosys_local.sh -Q -q -l "${log}" -p "read_verilog -sv -I. rtl/fp16_add.sv rtl/fp16_mul.sv rtl/fp16_rsqrt_lut256.sv rtl/logic_normalization_scalar_engine.sv rtl/logic_normalization_reduction_engine.sv rtl/logic_normalization_engine_array.sv rtl/logic_normalization_dispatcher_top.sv; chparam -set ENGINES ${engines} -set BANKS 16 logic_normalization_dispatcher_top; hierarchy -check -top logic_normalization_dispatcher_top; synth -top logic_normalization_dispatcher_top; stat; check -assert"
done
echo "LOGIC_NORMALIZATION_DISPATCHER_SYNTHESIS PASS engines=4,8,16"
