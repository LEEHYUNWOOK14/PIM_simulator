#!/usr/bin/env bash
set -euo pipefail
lanes="${1:?usage: $0 LANES [PROFILE] [ENGINES] [CONTEXTS] [FIFO]}";filter="${2:-}";engines="${3:-4}";contexts="${4:-8}";fifo="${5:-16}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."&&pwd)";cd "$root"
vectors="reports/groot_normalization/results/multirow_l${lanes}_vectors"
if [[ ! -f "$vectors/cases.csv" ]];then python3 tools/prepare_groot_multirow_vectors.py --lanes "$lanes";fi
out="${TMPDIR:-/tmp}/groot_logic_die_pcu_l${lanes}_e${engines}.out"
src=(rtl/bf16_to_fp32.sv rtl/fp32_to_bf16_rne.sv rtl/fp32_add.sv rtl/fp32_mul.sv rtl/fp32_add_pipe4.sv rtl/fp32_mul_pipe4.sv rtl/bf16_rsqrt_lut256.sv rtl/mixed_precision_bank_reducer_pingpong.sv rtl/mixed_precision_global_reducer16_pipe.sv rtl/mixed_precision_scalar_nr2_pipe.sv rtl/mixed_precision_scalar_engine_array.sv rtl/mixed_precision_bank_apply_pipe.sv rtl/mixed_precision_row_context_table.sv rtl/mixed_precision_multirow_datapath.sv rtl/normalization_bank_scheduler.sv rtl/logic_die_normalization_pcu_top.sv verification/groot_normalization/groot_logic_die_pcu_trace_tb.sv)
iverilog -g2012 -Wall -s groot_logic_die_pcu_trace_tb -P groot_logic_die_pcu_trace_tb.L="$lanes" -P groot_logic_die_pcu_trace_tb.SCALAR_ENGINES="$engines" -P groot_logic_die_pcu_trace_tb.TOP_CONTEXTS="$contexts" -P groot_logic_die_pcu_trace_tb.APPLY_FIFO_DEPTH="$fifo" -o "$out" "${src[@]}"
results="reports/groot_normalization/results/logic_die_pcu_l${lanes}_e${engines}_results";mkdir -p "$results";log="$results/rtl_runs.log";[[ -z "$filter" ]]&&:>"$log"
while IFS=, read -r p rows hidden v invh eps class;do p="${p//$'\r'/}";[[ "$p" == profile_id ]]&&continue;[[ -n "$filter"&&"$p" != "$filter" ]]&&continue;vvp "$out" "+PROFILE=$p" "+ROWS=$rows" "+HIDDEN=$hidden" "+VECTORS=$v" "+INVH=$invh" "+EPS=$eps" "+X=$vectors/${p}_x.hex" "+GAMMA=$vectors/${p}_gamma.hex" "+BETA=$vectors/${p}_beta.hex" "+MIXED=$vectors/${p}_mixed_expected.hex" "+PYTORCH=$vectors/${p}_pytorch_expected.hex" "+ACTUAL=$results/${p}_actual.hex"|tee -a "$log";done<"$vectors/cases.csv"
