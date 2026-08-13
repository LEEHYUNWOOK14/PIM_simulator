#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"
yosys="$yosys_exe"
results="reports/groot_normalization/results/structural_audit";mkdir -p "$results"
common="rtl/fp16_add.sv rtl/fp16_mul.sv rtl/bf16_add.sv rtl/bf16_mul.sv rtl/fp16_rsqrt_lut256.sv rtl/bf16_rsqrt_lut256.sv rtl/bank_normalization_local_reducer.sv rtl/bank_normalization_apply.sv rtl/bank_normalization_vector_reducer.sv rtl/bank_normalization_pipelined_vector_reducer.sv rtl/logic_normalization_scalar_engine.sv rtl/logic_normalization_reduction_engine.sv rtl/hierarchical_normalization_datapath.sv"

audit() {
 local top="$1" format="$2" params="$3" stem="$4"
 "$yosys" -Q -q -l "$results/${stem}.log" -p \
  "read_verilog -sv -I. ${common}; chparam -set DATA_FORMAT ${format} ${params} ${top}; hierarchy -check -top ${top}; synth -noabc -top ${top}; check -assert; select -assert-none t:\$dlatch; stat"
}

for format in 0 1;do
 dtype="fp16";if [[ "$format" == 1 ]];then dtype="bf16";fi
 audit bank_normalization_local_reducer "$format" "" "bank_local_${dtype}"
 audit bank_normalization_apply "$format" "" "bank_apply_${dtype}"
 audit logic_normalization_scalar_engine "$format" "" "scalar_${dtype}"
 audit logic_normalization_reduction_engine "$format" "-set BANKS 4" "reduction_${dtype}"
 audit hierarchical_normalization_datapath "$format" "-set BANKS 4" "hierarchical_${dtype}"
 for lanes in 1 2 4 8 16;do
  audit bank_normalization_vector_reducer "$format" "-set LANES ${lanes}" "vector_${dtype}_l${lanes}"
 done
 for lanes in 2 4 8 16;do
  audit bank_normalization_pipelined_vector_reducer "$format" "-set LANES ${lanes}" "pipelined_${dtype}_l${lanes}"
 done
done
echo "NORMALIZATION_STRUCTURAL_AUDIT PASS formats=FP16,BF16 lanes=1,2,4,8,16 no_latch check_assert"
