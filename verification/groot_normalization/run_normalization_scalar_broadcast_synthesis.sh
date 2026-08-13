#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "${root}"
for banks in 4 8 16;do
  log="reports/groot_normalization/results/normalization_scalar_broadcast_b${banks}_yosys.log"
  bash rtl/yosys_local.sh -Q -q -l "${log}" -p "read_verilog -sv rtl/normalization_scalar_broadcast.sv; chparam -set BANKS ${banks} normalization_scalar_broadcast; hierarchy -check -top normalization_scalar_broadcast; synth -top normalization_scalar_broadcast; stat; check -assert"
done
echo "NORMALIZATION_SCALAR_BROADCAST_SYNTHESIS PASS banks=4,8,16"
