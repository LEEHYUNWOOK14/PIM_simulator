#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/experiment/results/hierarchy_arbitration_microbenchmark.csv}"

extract() {
  local line="$1" key="$2"
  printf '%s\n' "$line" | sed -n -E "s/.*${key}\[([^]]+)\].*/\1/p"
}

cd "$ROOT_DIR"
scons -j"${BUILD_JOBS:-4}" >/dev/null
output="$(./sim --gtest_filter=HierarchyPIMArbiterTest.SimultaneousRequestPolicyMicrobenchmark 2>&1)" || {
  printf '%s\n' "$output" >&2
  exit 1
}

printf 'policy,completion_cycle,bank_wait_cycles,logic_wait_cycles,bank_max_wait,logic_max_wait,ready_bypasses,arbitration_stall_cycles\n' > "$RESULT_FILE"
while IFS= read -r line; do
  [[ "$line" == HIERARCHY_ARBITRATION_RESULT* ]] || continue
  printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$(extract "$line" policy)" \
    "$(extract "$line" completion_cycle)" \
    "$(extract "$line" bank_wait_cycles)" \
    "$(extract "$line" logic_wait_cycles)" \
    "$(extract "$line" bank_max_wait)" \
    "$(extract "$line" logic_max_wait)" \
    "$(extract "$line" ready_bypasses)" \
    "$(extract "$line" arbitration_stall_cycles)" >> "$RESULT_FILE"
done <<< "$output"

echo "Result: $RESULT_FILE"
column -s, -t "$RESULT_FILE" 2>/dev/null || cat "$RESULT_FILE"
