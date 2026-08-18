#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
vectors=reports/groot_normalization/results/multirow_l4_vectors
if [[ ! -s "$vectors/cases.csv" || ! -s "$vectors/action_vlln_x.hex" ]]; then
  if [[ ! -s reports/groot_normalization/results/actual_groot/action_head_trace/action_vlln_input_bf16.hex ]]; then
    python3 tools/restore_groot_trace_hex_from_pt.py
  fi
  python3 tools/prepare_groot_multirow_vectors.py --lanes 4
fi
if [[ "${WBQ_VARIANT:-}" =~ ^B[345]$ ]]; then
  variant_lower="${WBQ_VARIANT,,}"
  results="reports/groot_normalization/results/quad_local_${variant_lower}_actual_trace"
elif [[ "${WBQ_B2:-0}" == 1 ]]; then
  results=reports/groot_normalization/results/quad_local_b2_actual_trace
else
  results=reports/groot_normalization/results/quad_local_ab_actual_trace
fi
mkdir -p "$results"
log="$results/rtl_runs.log"
if [[ "${GROOT_APPEND_LOG:-0}" != 1 ]]; then
  : > "$log"
fi
out="${TMPDIR:-/tmp}/wbq_quad_local_actual_trace.out"
src=(
  rtl/bf16_to_fp32.sv rtl/fp32_to_bf16_rne.sv rtl/fp32_add.sv rtl/fp32_mul.sv
  rtl/fp32_add_pipe4.sv rtl/fp32_mul_pipe4.sv rtl/bf16_rsqrt_lut256.sv
  rtl/mixed_precision_bank_reducer_pingpong.sv rtl/mixed_precision_global_reducer16_pipe.sv
  rtl/mixed_precision_scalar_nr2_pipe.sv rtl/mixed_precision_scalar_engine_array.sv
  rtl/mixed_precision_bank_apply_pipe.sv rtl/mixed_precision_row_context_table.sv
  rtl/mixed_precision_multirow_datapath.sv rtl/normalization_bank_scheduler.sv
  rtl/logic_die_normalization_pcu_top.sv
  rtl/normalization_quad_local_bank_scheduler.sv
  rtl/mixed_precision_quad_local_multirow_datapath.sv
  rtl/logic_die_normalization_quad_local_pcu_top.sv
  rtl/normalization_hbm_quad_local_boundary_adapter.sv
  verification/groot_normalization/groot_logic_die_pcu_trace_tb.sv
)
iverilog -g2012 -Wall -s groot_logic_die_pcu_trace_tb \
  -P groot_logic_die_pcu_trace_tb.L=4 \
  -P groot_logic_die_pcu_trace_tb.QUAD_LOCAL_AB=1 \
  -P groot_logic_die_pcu_trace_tb.B2_REGISTERED_QUAD_COMPLETION="${WBQ_B2:-0}" \
  -o "$out" "${src[@]}"

count=0
while IFS=, read -r profile rows hidden vectors_per_bank inv_hidden epsilon classification; do
  profile="${profile//$'\r'/}"
  [[ "$profile" == profile_id ]] && continue
  if [[ -n "${GROOT_PROFILE_FILTER:-}" && "$profile" != "$GROOT_PROFILE_FILTER" ]]; then
    continue
  fi
  vvp "$out" \
    "+PROFILE=$profile" "+ROWS=$rows" "+HIDDEN=$hidden" \
    "+VECTORS=$vectors_per_bank" "+INVH=$inv_hidden" "+EPS=$epsilon" \
    "+X=$vectors/${profile}_x.hex" "+GAMMA=$vectors/${profile}_gamma.hex" \
    "+BETA=$vectors/${profile}_beta.hex" \
    "+MIXED=$vectors/${profile}_mixed_expected.hex" \
    "+PYTORCH=$vectors/${profile}_pytorch_expected.hex" \
    "+ACTUAL=$results/${profile}_actual.hex" | tee -a "$log"
  count=$((count+1))
done < "$vectors/cases.csv"

if [[ -n "${GROOT_PROFILE_FILTER:-}" ]]; then
  test "$count" -eq 1
  echo "WBQ_QUAD_LOCAL_ACTUAL_TRACE_SMOKE PASS profile=$GROOT_PROFILE_FILTER"
  exit 0
fi
test "$count" -eq 6
analysis_args=()
if [[ "${WBQ_VARIANT:-}" =~ ^B[345]$ ]]; then
  variant_lower="${WBQ_VARIANT,,}"
  analysis_args+=(--b2 --results "$results" --variant "logic_die_normalization_hbm_quad_local_${variant_lower}_physical_eco")
elif [[ "${WBQ_B2:-0}" == 1 ]]; then
  analysis_args+=(--b2)
fi
python3 tools/analyze_wbq_quad_local_actual_trace.py "${analysis_args[@]}"
echo "WBQ_QUAD_LOCAL_ACTUAL_TRACE_TEST PASS profiles=$count"
