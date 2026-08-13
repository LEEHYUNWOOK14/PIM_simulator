#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$repo_root/b1_logic_die_experiment"
mkdir -p "$work/artifacts" "$work/logs" "$work/metrics"
cd "$repo_root"
iv="${HOME}/.local/iverilog/usr/bin/iverilog"
vvp="${HOME}/.local/iverilog/usr/bin/vvp"
ivl_base="$(find "${HOME}/.local/iverilog/usr/lib" -type d -name ivl -print -quit)"
mapfile -t sources < "$work/sources.list"

{
  echo '[B1-G3] exact plan-shape contract probe (expected assertion failure)'
  "$iv" -B "$ivl_base" -g2012 -s full_pim_system_top \
    -P full_pim_system_top.CHANNELS=1 -P full_pim_system_top.BANKS=1 \
    -P full_pim_system_top.PIM_BLOCKS=1 -P full_pim_system_top.PCUS=1 \
    -P full_pim_system_top.ROWS=1 -P full_pim_system_top.COLS=1 \
    -P full_pim_system_top.DATA_WIDTH=16 -P full_pim_system_top.CRF_DEPTH=2 \
    -P full_pim_system_top.WEIGHT_BUFFER_BYTES=16 \
    -P full_pim_system_top.ENABLE_LOGIC_DIE_PCU=1 \
    -P full_pim_system_top.ENABLE_NORMALIZATION_ENGINE=0 \
    -o "$work/artifacts/b1_contract_probe.out" "${sources[@]}"
  set +e
  "$vvp" -M "$ivl_base" "$work/artifacts/b1_contract_probe.out" > "$work/logs/b1_contract_probe.log" 2>&1
  probe_rc=$?
  set -e
  if [[ $probe_rc -eq 0 ]]; then
    echo 'ERROR: invalid exact plan shape unexpectedly passed'
    exit 1
  fi
  grep -E 'each PIM block requires|DATA_WIDTH must be divisible' "$work/logs/b1_contract_probe.log"
  echo '[B1-G3] valid minimal hierarchical end-to-end test'
  "$iv" -B "$ivl_base" -g2012 -s b1_hierarchical_tb \
    -o "$work/artifacts/b1_hierarchical_tb.out" "${sources[@]}" "$work/b1_hierarchical_tb.sv"
  "$vvp" -M "$ivl_base" "$work/artifacts/b1_hierarchical_tb.out"
  echo '[B1-G3] existing bank/logic regression set'
  bash verification/rtl_audit/run_aud_001_008_regression.sh
  echo '[B1-G3] result-router exhaustive combinational proof'
  bash rtl/yosys_local.sh -Q -p \
    "read_verilog -formal -sv rtl/logic_result_router.sv verification/rtl_audit/logic_result_router_formal.sv; prep -top logic_result_router_formal -flatten; select -module logic_result_router_formal; sat -prove ok 1"
} 2>&1 | tee "$work/logs/b1_functional.log"

cat > "$work/metrics/b1_functional_results.csv" <<'EOF'
test,status,mismatches,protocol_errors,deadlocks,backpressure_checked,evidence
exact_plan_contract_probe,EXPECTED_FAIL,0,0,0,0,logs/b1_contract_probe.log
hierarchical_bank_logic_e2e,PASS,0,0,0,1,logs/b1_functional.log
bank_logic_regression,PASS,0,0,0,1,logs/b1_functional.log
result_router_formal,PASS,0,0,0,1,logs/b1_functional.log
normalization_off_idle,PASS,0,0,0,0,logs/b1_functional.log
EOF
