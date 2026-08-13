#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flow=/home/chandler/OpenROAD-flow-scripts/flow
platform="$flow/platforms/sky130hd"
openroad=/home/chandler/.local/stob-eda/openroad/bin/openroad
evidence="$root/reports/groot_normalization/physical_feasibility"
netlist="$evidence/logic_die_normalization_hbm_top_sky130.v"
placed_db="$evidence/logic_die_normalization_hbm_top_repaired_legal.odb"
placed_sdc="$evidence/logic_die_normalization_hbm_top_repaired_legal.sdc"
placement_log="$evidence/logic_die_normalization_hbm_top_repair_legalize.log"
run_root="$(mktemp -d "$evidence/integrated_route_run.XXXXXX")"
cleanup() {
  case "$run_root" in
    "$evidence"/integrated_route_run.*) rm -rf -- "$run_root" ;;
    *) echo "refusing to remove unexpected temporary path: $run_root" >&2 ;;
  esac
}
trap cleanup EXIT

test -s "$netlist"
test -s "$placed_db"
test -s "$placed_sdc"
grep -q '^REPAIR_LEGAL_PASS$' "$placement_log"
if [[ ! "$placed_db" -nt "$netlist" ]]; then
  echo "placed DB predates mapped netlist; regenerate placement first" >&2
  exit 2
fi

export PF_PLATFORM_ROOT="$platform"
export PF_PLACED_DB="$placed_db"
export PF_PLACED_SDC="$placed_sdc"
export PF_ROUTE_OUTPUT_ROOT="$run_root"
log="$run_root/logic_die_normalization_hbm_top_coarse_route.log"
{
  echo "PF_SOURCE_NETLIST_SHA256=$(sha256sum "$netlist" | awk '{print $1}')"
  echo "PF_SOURCE_PLACEMENT_LOG_SHA256=$(sha256sum "$placement_log" | awk '{print $1}')"
  echo "PF_SOURCE_PLACED_DB_BYTES=$(stat -c '%s' "$placed_db")"
  echo "PF_SKIPPED_FANOUT_THRESHOLD=5000"
  echo "PF_GLOBAL_ROUTER=CUGR"
  # One thread avoids per-worker memory multiplication on this multi-million
  # cell feasibility netlist.  PF-4 needs a complete congestion/overflow
  # observation, not maximum routing throughput.
  "$openroad" -exit -no_init -threads 1 -no_splash \
    "$root/hardware_cost/physical_feasibility/integrated_global_route_only.tcl"
} >"$log" 2>&1

grep -q '^COARSE_ROUTE_PASS$' "$log"
test -s "$run_root/logic_die_normalization_hbm_top.route_guide"
test -s "$run_root/logic_die_normalization_hbm_top.congestion.rpt"
cp -f -- "$log" "$evidence/logic_die_normalization_hbm_top_route_from_legal.log"
cp -f -- "$run_root/logic_die_normalization_hbm_top.route_guide" "$evidence/logic_die_normalization_hbm_top.route_guide"
cp -f -- "$run_root/logic_die_normalization_hbm_top.congestion.rpt" "$evidence/logic_die_normalization_hbm_top.congestion.rpt"
cp -f -- "$run_root/legal_placement_check.rpt" "$evidence/coarse_legal_placement_check.rpt"
echo "HARDWARE_COST_INTEGRATED_COARSE_ROUTE PASS log=$evidence/logic_die_normalization_hbm_top_route_from_legal.log"
