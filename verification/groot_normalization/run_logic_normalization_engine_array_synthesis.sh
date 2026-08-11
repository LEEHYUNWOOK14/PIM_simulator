#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "${root}"
values=("$@");if [[ ${#values[@]} -eq 0 ]];then values=(1 2 4 8 16);fi
for engines in "${values[@]}";do
 log="reports/groot_normalization/results/logic_normalization_engine_array_e${engines}_yosys.log"
 bash rtl/yosys_local.sh -Q -q -l "${log}" -p "read_verilog -sv -I. rtl/fp16_add.sv rtl/fp16_mul.sv rtl/fp16_rsqrt_lut256.sv rtl/logic_normalization_scalar_engine.sv rtl/logic_normalization_reduction_engine.sv rtl/logic_normalization_engine_array.sv; chparam -set ENGINES ${engines} -set BANKS 16 logic_normalization_engine_array; hierarchy -check -top logic_normalization_engine_array; synth -top logic_normalization_engine_array; stat; check -assert"
done
echo "LOGIC_NORMALIZATION_ENGINE_ARRAY_SYNTHESIS PASS engines=${values[*]}"
