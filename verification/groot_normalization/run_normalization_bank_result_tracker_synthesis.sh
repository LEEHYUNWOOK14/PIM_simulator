#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "${root}"
log="reports/groot_normalization/results/normalization_bank_result_tracker_b16_e16_yosys.log"
bash rtl/yosys_local.sh -Q -q -l "${log}" -p "read_verilog -sv rtl/normalization_bank_result_tracker.sv; chparam -set BANKS 16 -set ENTRIES 16 normalization_bank_result_tracker; hierarchy -check -top normalization_bank_result_tracker; synth -top normalization_bank_result_tracker; stat; check -assert"
echo "NORMALIZATION_BANK_RESULT_TRACKER_SYNTHESIS PASS banks=16 entries=16"
