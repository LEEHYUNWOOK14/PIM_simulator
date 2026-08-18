#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
source "$root/verification/groot_normalization/eda_environment.sh"

if [[ "${WBQ_VARIANT:-}" =~ ^B([3-9]|[1-9][0-9])$ ]]; then
  variant_lower="${WBQ_VARIANT,,}"
  report_dir="reports/groot_normalization/quad_local_${variant_lower}"
  top=logic_die_normalization_hbm_quad_local_b2_top
  prefix="$variant_lower"
  audit_args=(--top "$top" --require-b2-completion)
elif [[ "${WBQ_B2:-0}" == 1 ]]; then
  report_dir=reports/groot_normalization/quad_local_b2
  top=logic_die_normalization_hbm_quad_local_b2_top
  prefix=b2
  audit_args=(--top "$top" --require-b2-completion)
else
  report_dir=reports/groot_normalization/quad_local_ab
  top=logic_die_normalization_hbm_quad_local_ab_top
  prefix=b
  audit_args=(--top "$top")
fi
mkdir -p "$report_dir"
log="$report_dir/yosys_rtl_check.log"
json="$report_dir/${prefix}_rtl_hierarchy.json"
audit="$report_dir/${prefix}_rtl_locality_audit.json"
src=(
  rtl/bf16_to_fp32.sv rtl/fp32_to_bf16_rne.sv rtl/fp32_add.sv rtl/fp32_mul.sv
  rtl/fp32_add_pipe4.sv rtl/fp32_mul_pipe4.sv rtl/bf16_rsqrt_lut256.sv
  rtl/mixed_precision_bank_reducer_pingpong.sv rtl/mixed_precision_global_reducer16_pipe.sv
  rtl/mixed_precision_scalar_nr2_pipe.sv rtl/mixed_precision_scalar_engine_array.sv
  rtl/mixed_precision_bank_apply_pipe.sv rtl/mixed_precision_row_context_table.sv
  rtl/mixed_precision_multirow_datapath.sv rtl/normalization_bank_scheduler.sv
  rtl/logic_die_normalization_pcu_top.sv rtl/normalization_writeback_quad_slice.sv
  rtl/normalization_quad_local_bank_scheduler.sv
  rtl/mixed_precision_quad_local_multirow_datapath.sv
  rtl/logic_die_normalization_quad_local_pcu_top.sv
  rtl/normalization_hbm_quad_local_boundary_adapter.sv
  rtl/logic_die_normalization_hbm_quad_local_ab_top.sv
  rtl/logic_die_normalization_hbm_quad_local_b2_top.sv
)

"$yosys_exe" -Q -l "$log" -p "
  read_verilog -sv -I. ${src[*]};
  hierarchy -check -top $top;
  proc;
  opt_clean;
  check -assert;
  stat -top $top;
  write_json $json;
"

grep -q "Found and reported 0 problems" "$log"
grep -q "normalization_hbm_quad_local_boundary_adapter" "$log"
grep -q "normalization_hbm_quad_payload_store" "$log"
grep -Eq '4[[:space:]]+.*normalization_hbm_quad_payload_store' "$log"
grep -q 'normalization_quad_reset_leaf' "$log"
if grep -Eq "logic_die_normalization_hbm_top|hierarchical_normalization_bank_core_top" \
    rtl/logic_die_normalization_hbm_quad_local_ab_top.sv; then
  # Comments may describe excluded designs; reject only actual instantiations.
  if grep -Eq '^[[:space:]]*(logic_die_normalization_hbm_top|hierarchical_normalization_bank_core_top)[[:space:]#]' \
      rtl/logic_die_normalization_hbm_quad_local_ab_top.sv; then
    echo "B top aliases an excluded top" >&2
    exit 1
  fi
fi

python3 tools/audit_wbq_quad_local_netlist.py \
  --json "$json" --stage rtl --output "$audit" "${audit_args[@]}"

echo "NORMALIZATION_HBM_QUAD_LOCAL_AB_RTL_CHECK PASS log=$log"
