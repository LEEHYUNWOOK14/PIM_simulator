#!/usr/bin/env bash
set -euo pipefail
if [[ "${PF_ALLOW_LEGACY_ROUTE:-0}" != "1" ]]; then
  echo "legacy 40%-core route is disabled after the capped congestion result; set PF_ALLOW_LEGACY_ROUTE=1 only for an intentional rerun" >&2
  exit 4
fi
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
report_root="$root/reports/groot_normalization/physical_feasibility"
log="$report_root/logic_die_normalization_hbm_top_route_from_legal.log"
netlist="$report_root/logic_die_normalization_hbm_top_sky130.v"
placement_log="$report_root/logic_die_normalization_hbm_top_repair_legalize.log"
if pgrep -f '[o]penroad.*normalization_hbm_route_from_legal\.tcl' >/dev/null; then
  echo "route_from_legal already running; refusing duplicate execution" >&2
  exit 3
fi
tmp_log="$log.tmp.$$"
openroad_log="$tmp_log.openroad"
cleanup() {
  status=$?
  if [[ $status -ne 0 && -f "$tmp_log" ]]; then
    if [[ -s "$openroad_log" ]]; then
      cat "$openroad_log" >>"$tmp_log"
    fi
    mv -f -- "$tmp_log" "$log.failed.$$"
  fi
  rm -f -- "$tmp_log" "$openroad_log"
}
trap cleanup EXIT
{
  echo "PF_SOURCE_NETLIST_SHA256=$(sha256sum "$netlist" | awk '{print $1}')"
  echo "PF_SOURCE_PLACEMENT_LOG_SHA256=$(sha256sum "$placement_log" | awk '{print $1}')"
  echo "PF_SKIPPED_FANOUT_THRESHOLD=5000"
  echo "PF_GLOBAL_ROUTER=CUGR"
} >"$tmp_log"
rm -f -- \
  "$report_root/logic_die_normalization_hbm_top.route_guide" \
  "$report_root/logic_die_normalization_hbm_top.congestion.rpt"
/home/chandler/.local/stob-eda/openroad/bin/openroad -exit -no_init -threads 1 -no_splash \
  -log "$openroad_log" "$root/verification/groot_normalization/normalization_hbm_route_from_legal.tcl"
cat "$openroad_log" >>"$tmp_log"
grep -q '^ROUTE_FROM_LEGAL_PASS$' "$tmp_log"
test -s "$report_root/logic_die_normalization_hbm_top.route_guide"
test -s "$report_root/logic_die_normalization_hbm_top.congestion.rpt"
mv -f -- "$tmp_log" "$log"
