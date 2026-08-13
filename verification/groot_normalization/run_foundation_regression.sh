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
  shift 3
  echo "FOUNDATION ${category}: ${name}"
  if bash "$script" "$@"; then
    printf '%s,%s,PASS\n' "$category" "$name" >> "$summary"
  else
    printf '%s,%s,FAIL\n' "$category" "$name" >> "$summary"
    return 1
  fi
}

mapfile -t tests < <(find verification/groot_normalization -maxdepth 1 -type f \
  -name 'run_*_test.sh' \
  ! -name 'run_groot_mixed_precision_c11_trace_test.sh' \
  ! -name 'run_groot_mixed_precision_trace_test.sh' \
  -printf '%f\n' | sort)
for test_script in "${tests[@]}"; do
  if [[ "$test_script" == "run_groot_multirow_trace_test.sh" ]]; then
    run_gate test "${test_script%.sh}" "verification/groot_normalization/$test_script" 4
  else
    run_gate test "${test_script%.sh}" "verification/groot_normalization/$test_script"
  fi
done

if [[ "${1:-}" == "--tests-only" ]];then
  echo "FOUNDATION_REGRESSION TESTS PASS summary=$summary"
  exit 0
fi

synthesis=(
  run_bf16_normalization_synthesis.sh
  run_normalization_fullpath_synthesis.sh
  run_normalization_structural_audit.sh
  run_bank_normalization_pipelined_vector_reducer_synthesis.sh
  run_bank_normalization_vector_reducer_synthesis.sh
  run_shared_pair_reducer_synthesis.sh
)
for synth_script in "${synthesis[@]}"; do
  run_gate synthesis "${synth_script%.sh}" "verification/groot_normalization/$synth_script"
done
if [[ -x /home/chandler/.local/oss-cad-suite/bin/yosys &&
      -x /home/chandler/.local/openroad-pi/usr/bin/openroad &&
      -f /home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib ]];then
  run_gate physical run_normalization_sky130_mapping \
    verification/groot_normalization/run_normalization_sky130_mapping.sh
else
  printf 'physical,run_normalization_sky130_mapping,SKIP_TOOL_UNAVAILABLE\n' >> "$summary"
fi
python3 tools/collect_normalization_synthesis_metrics.py
echo "FOUNDATION_REGRESSION PASS summary=$summary"
