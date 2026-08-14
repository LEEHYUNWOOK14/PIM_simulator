#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$root/verification/groot_normalization/eda_environment.sh"

odb="$orfs_flow/results/sky130hd/normalization_hbm_wbq/base/3_3_place_gp.odb"
tcl="$root/verification/groot_normalization/diagnose_wbq_pd_net.tcl"
out_dir="$root/reports/groot_normalization/physical_feasibility/wbq_pd_net_diagnostics"
timeout_seconds="${WBQ_PD_TIMEOUT_SECONDS:-180}"
mkdir -p "$out_dir"
test -s "$odb"

nets=(
  clk_i
  rst_ni
  u_adapter/_14518_
  u_adapter/_14521_
  u_writeback_slice/capture
  reduction_valid[0]
  replay_valid[0]
  u_adapter/state_q[2]
  u_adapter/_15000_
  u_adapter/_14515_
  u_adapter/_15001_
  u_adapter/_20968_
  u_adapter/_20969_
)

summary="$out_dir/summary.tsv"
printf 'net\tstatus\telapsed_seconds\tlog\n' > "$summary"
for net in "${nets[@]}"; do
  safe_name="${net//\//__}"
  safe_name="${safe_name//\[/_}"
  safe_name="${safe_name//\]/_}"
  log="$out_dir/${safe_name}.log"
  start="$(date +%s)"
  set +e
  WBQ_DIAG_ODB="$odb" WBQ_DIAG_NET="$net" \
    timeout --signal=TERM --kill-after=10 "$timeout_seconds" \
    "$openroad_exe" -exit -no_init -threads 1 -no_splash "$tcl" \
    > "$log" 2>&1
  rc=$?
  set -e
  end="$(date +%s)"
  elapsed="$((end - start))"
  if test "$rc" -eq 0; then
    status=pass
  elif test "$rc" -eq 124 || test "$rc" -eq 137; then
    status=timeout
  else
    status="error_$rc"
  fi
  printf '%s\t%s\t%s\t%s\n' "$net" "$status" "$elapsed" "$log" | tee -a "$summary"
done

echo "WBQ_PD_DIAGNOSTICS_COMPLETE summary=$summary"
