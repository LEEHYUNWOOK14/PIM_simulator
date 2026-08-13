#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
for shared in 0 1; do
  out="${TMPDIR:-/tmp}/normalization_bank_scheduler_${shared}.out"
  iverilog -g2012 -Wall -s normalization_bank_scheduler_tb \
    -P normalization_bank_scheduler_tb.SHARED="$shared" -o "$out" \
    rtl/normalization_bank_scheduler.sv \
    verification/groot_normalization/normalization_bank_scheduler_tb.sv
  vvp "$out"
done
