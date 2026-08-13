#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "${root}"
log="reports/groot_normalization/results/bank_normalization_microprogram_adapter_yosys.log"
bash rtl/yosys_local.sh -Q -q -l "${log}" -p "read_verilog -sv -I. rtl/bank_normalization_microprogram_adapter.sv; hierarchy -check -top bank_normalization_microprogram_adapter; synth -top bank_normalization_microprogram_adapter; stat; check -assert"
echo "BANK_NORMALIZATION_MICROPROGRAM_ADAPTER_SYNTHESIS PASS data_width=256"
