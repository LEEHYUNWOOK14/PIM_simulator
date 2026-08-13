#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "${root}"
log="reports/groot_normalization/results/normalization_row_context_table_b16_e16_yosys.log"
bash rtl/yosys_local.sh -Q -q -l "${log}" -p "read_verilog -sv rtl/normalization_row_context_table.sv; chparam -set BANKS 16 -set ENTRIES 16 normalization_row_context_table; hierarchy -check -top normalization_row_context_table; synth -top normalization_row_context_table; stat; check -assert"
echo "NORMALIZATION_ROW_CONTEXT_TABLE_SYNTHESIS PASS banks=16 entries=16"
