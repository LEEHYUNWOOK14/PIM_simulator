#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)";cd "$root"
local_contexts="${1:-2}"
if python3 -c 'import numpy' 2>/dev/null; then
  python3 tools/prepare_rmsnorm_rtl_vectors.py
else
  "/mnt/c/Program Files/Python313/python.exe" "$(wslpath -w tools/prepare_rmsnorm_rtl_vectors.py)"
fi
vectors="reports/groot_normalization/results/rmsnorm_l8_vectors"
results="reports/groot_normalization/results/rmsnorm_l8_c${local_contexts}_results";mkdir -p "$results"
out="${TMPDIR:-/tmp}/rmsnorm_logic_die_pcu_l8_c${local_contexts}.out"
src=(rtl/bf16_to_fp32.sv rtl/fp32_to_bf16_rne.sv rtl/fp32_add.sv rtl/fp32_mul.sv rtl/fp32_add_pipe4.sv rtl/fp32_mul_pipe4.sv rtl/bf16_rsqrt_lut256.sv rtl/mixed_precision_bank_reducer_pingpong.sv rtl/mixed_precision_global_reducer16_pipe.sv rtl/mixed_precision_scalar_nr2_pipe.sv rtl/mixed_precision_scalar_engine_array.sv rtl/mixed_precision_bank_apply_pipe.sv rtl/mixed_precision_row_context_table.sv rtl/mixed_precision_multirow_datapath.sv rtl/normalization_bank_scheduler.sv rtl/logic_die_normalization_pcu_top.sv verification/groot_normalization/groot_logic_die_pcu_trace_tb.sv)
iverilog -g2012 -Wall -s groot_logic_die_pcu_trace_tb -P groot_logic_die_pcu_trace_tb.L=8 -P groot_logic_die_pcu_trace_tb.SCALAR_ENGINES=4 -P groot_logic_die_pcu_trace_tb.LOCAL_REDUCE_CONTEXTS="$local_contexts" -o "$out" "${src[@]}"
:>"$results/rtl_runs.log"
while IFS=, read -r p rows hidden v invh eps;do
  p="${p//$'\r'/}";eps="${eps//$'\r'/}";[[ "$p" == profile_id ]]&&continue
  vvp "$out" "+RMS=1" "+PROFILE=$p" "+ROWS=$rows" "+HIDDEN=$hidden" "+VECTORS=$v" "+INVH=$invh" "+EPS=$eps" \
    "+X=$vectors/${p}_x.hex" "+GAMMA=$vectors/${p}_gamma.hex" "+BETA=$vectors/${p}_beta.hex" \
    "+MIXED=$vectors/${p}_mixed_expected.hex" "+PYTORCH=$vectors/${p}_reference_expected.hex" \
    "+ACTUAL=$results/${p}_actual.hex"|tee -a "$results/rtl_runs.log"
done<"$vectors/cases.csv"
