#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
results="reports/groot_normalization/results"
mkdir -p "$results"
summary="$results/foundation_regression_results.csv"
printf 'category,name,status\n' > "$summary"

run_gate() {
  local category="$1" name="$2" script="$3"
  echo "FOUNDATION ${category}: ${name}"
  if bash "$script"; then
    printf '%s,%s,PASS\n' "$category" "$name" >> "$summary"
  else
    printf '%s,%s,FAIL\n' "$category" "$name" >> "$summary"
    return 1
  fi
}

tests=(
  run_bf16_arithmetic_random_test.sh
  run_bf16_normalization_test.sh
  run_normalization_interface_contract_test.sh
  run_bank_normalization_pipelined_vector_reducer_test.sh
  run_bank_normalization_test.sh
  run_bank_normalization_vector_reducer_test.sh
  run_bank_pim_normalization_microprogram_test.sh
  run_fp16_rsqrt_test.sh
  run_hierarchical_normalization_test.sh
  run_normalization_reduction_test.sh
  run_normalization_scalar_test.sh
)
for test_script in "${tests[@]}"; do
  run_gate test "${test_script%.sh}" "verification/groot_normalization/$test_script"
done

synthesis=(
  run_bf16_normalization_synthesis.sh
  run_bank_normalization_pipelined_vector_reducer_synthesis.sh
  run_bank_normalization_vector_reducer_synthesis.sh
  run_shared_pair_reducer_synthesis.sh
)
for synth_script in "${synthesis[@]}"; do
  run_gate synthesis "${synth_script%.sh}" "verification/groot_normalization/$synth_script"
done
echo "FOUNDATION_REGRESSION PASS summary=$summary"
