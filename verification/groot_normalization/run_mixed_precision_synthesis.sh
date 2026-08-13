#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "$root"
results=reports/groot_normalization/results/mixed_precision_synthesis;mkdir -p "$results"
common="rtl/bf16_to_fp32.sv rtl/fp32_to_bf16_rne.sv rtl/fp32_add.sv rtl/fp32_mul.sv rtl/fp32_add_pipe4.sv rtl/fp32_mul_pipe4.sv rtl/bf16_rsqrt_lut256.sv rtl/mixed_precision_bank_reducer4.sv rtl/mixed_precision_bank_reducer4_interleaved.sv rtl/mixed_precision_global_reducer16.sv rtl/mixed_precision_global_reducer16_pipe.sv rtl/mixed_precision_scalar_nr2.sv rtl/mixed_precision_scalar_nr2_pipe.sv rtl/mixed_precision_bank_apply4.sv rtl/mixed_precision_bank_apply4_pipe.sv rtl/mixed_precision_normalization_datapath.sv"
for top in fp32_add fp32_mul fp32_to_bf16_rne fp32_add_pipe4 fp32_mul_pipe4 mixed_precision_bank_reducer4 mixed_precision_bank_reducer4_interleaved mixed_precision_global_reducer16 mixed_precision_global_reducer16_pipe mixed_precision_scalar_nr2 mixed_precision_scalar_nr2_pipe mixed_precision_bank_apply4 mixed_precision_bank_apply4_pipe;do
  [[ -n "${MIXED_SYNTH_TOP_FILTER:-}" && "$top" != "$MIXED_SYNTH_TOP_FILTER" ]]&&continue
  bash rtl/yosys_local.sh -Q -q -l "$results/${top}_yosys.log" -p "read_verilog -sv -I. $common; hierarchy -check -top $top; synth -top $top; check -assert; stat; flatten; opt; ltp -noff"
  echo "MIXED_PRECISION_SYNTHESIS PASS top=$top"
done
# Full 16-bank/64-lane top is synthesized separately because it is the actual
# selected throughput configuration and materially larger than each component.
if [[ -z "${MIXED_SYNTH_TOP_FILTER:-}" || "$MIXED_SYNTH_TOP_FILTER" == mixed_precision_normalization_datapath ]];then
 bash rtl/yosys_local.sh -Q -q -l "$results/mixed_precision_normalization_datapath_yosys.log" -p "read_verilog -sv -I. $common; hierarchy -check -top mixed_precision_normalization_datapath; synth -top mixed_precision_normalization_datapath; check -assert; stat"
 echo "MIXED_PRECISION_SYNTHESIS PASS top=mixed_precision_normalization_datapath banks=16 lanes=4"
fi
