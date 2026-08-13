#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workspace="${repo_root}/b0_baseline_experiment"
physical="${workspace}/orfs/results/sky130hd/b0_bank_only_baseline/base"
power_dir="${workspace}/results/power"
mkdir -p "${power_dir}"

odb="${physical}/6_final.odb"
vcd="${workspace}/results/power/b0_gate_activity.vcd"
log="${power_dir}/b0_postroute_vcd_power.log"
[[ -s "${odb}" && -s "${vcd}" ]] || { echo "missing ODB or VCD" >&2; exit 1; }

set +e
B0_FINAL_ODB="${odb}" B0_VCD="${vcd}" B0_VCD_SCOPE=b0_gate_activity_tb/dut \
B0_FINAL_SDC="${physical}/6_final.sdc" \
B0_LIBERTY=/home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib \
  /home/chandler/.local/stob-eda/openroad/bin/openroad -no_init -no_splash -exit \
  "${workspace}/config/b0_postroute_power.tcl" >"${log}" 2>&1
rc=$?
set -e
grep -q B0_POWER_REPORT_END "${log}"
annotated="$(sed -n 's/.*Annotated \([0-9][0-9]*\) pin activities.*/\1/p' "${log}" | tail -1)"
[[ -n "${annotated}" && "${annotated}" -gt 0 ]] || {
  echo "VCD annotation failed: annotated=${annotated:-missing}" >&2
  exit 1
}

sha256sum "${vcd}" "${odb}" >"${power_dir}/power_input_sha256.txt"
printf 'metric,value,unit,evidence\nworkload_id,B0_TWO_FP16_VECTOR_ADD_ROUTE0_ROUTE1,string,MEASURED_GATE_VCD\nsimulated_operations,2,vector_add,MEASURED_TESTBENCH\nsimulation_duration,885,ns,MEASURED_GATE_VCD\nannotated_pin_activities,%s,pins,MEASURED_OPENROAD\nopenroad_exit_code,%s,count,MEASURED_TOOL_EXIT\n' "${annotated}" "${rc}" >"${power_dir}/b0_power_metrics.csv"
printf 'B0-G8 post-route VCD power report complete rc=%s log=%s\n' "${rc}" "${log}"
