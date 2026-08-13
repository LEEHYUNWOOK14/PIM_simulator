#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workspace="${repo_root}/b0_baseline_experiment"
logbase="${workspace}/orfs/logs/sky130hd/b0_bank_only_baseline/base"
phybase="${workspace}/orfs/results/sky130hd/b0_bank_only_baseline/base"
out="${workspace}/results/physical"
power="${workspace}/results/power"
manifest="${workspace}/manifest"
mkdir -p "${out}" "${manifest}"

for f in "${phybase}/6_final.odb" "${phybase}/6_final.def" "${phybase}/6_final.gds" \
         "${phybase}/6_final.spef" "${out}/b0_post_cts_timing.log" \
         "${out}/b0_post_route_timing.log" "${power}/b0_postroute_vcd_power.log"; do
  [[ -s "${f}" ]] || { echo "missing artifact: ${f}" >&2; exit 1; }
done
grep -q 'FULL_PIM_GDS PASS' "${out}/b0_gds_validation.log"

post_cts_setup="$(grep 'worst slack max' "${out}/b0_post_cts_timing.log" | awk '{print $4}')"
post_cts_hold="$(grep 'worst slack min' "${out}/b0_post_cts_timing.log" | awk '{print $4}')"
post_cts_tns="$(grep 'tns max' "${out}/b0_post_cts_timing.log" | awk '{print $3}')"
post_cts_skew="$(grep 'setup skew' "${out}/b0_post_cts_timing.log" | awk '{print $1}')"
post_route_setup="$(grep 'worst slack max' "${out}/b0_post_route_timing.log" | awk '{print $4}')"
post_route_hold="$(grep 'worst slack min' "${out}/b0_post_route_timing.log" | awk '{print $4}')"
post_route_tns="$(grep 'tns max' "${out}/b0_post_route_timing.log" | awk '{print $3}')"
post_route_skew="$(grep 'setup skew' "${out}/b0_post_route_timing.log" | awk '{print $1}')"
drc="$(jq -r '."detailedroute__route__drc_errors"' "${logbase}/5_2_route.json")"
wire="$(jq -r '."detailedroute__route__wirelength"' "${logbase}/5_2_route.json")"
vias="$(jq -r '."detailedroute__route__vias"' "${logbase}/5_2_route.json")"
antenna_nets="$(jq -r '."detailedroute__antenna__violating__nets"' "${logbase}/5_2_route.json")"
antenna_pins="$(jq -r '."detailedroute__antenna__violating__pins"' "${logbase}/5_2_route.json")"
placement_viol="$(jq -r '."detailedplace__design__violations"' "${logbase}/3_5_place_dp.json")"
power_w="$(grep '^Total ' "${power}/b0_postroute_vcd_power.log" | awk '{print $5}')"
energy_nj="$(awk -v p="${power_w}" 'BEGIN {printf "%.6f", p*885.0/2.0}')"
annotated="$(sed -n 's/.*Annotated \([0-9][0-9]*\) pin activities.*/\1/p' "${power}/b0_postroute_vcd_power.log" | tail -1)"

cat >"${out}/b0_physical_metrics.csv" <<EOF
metric,value,unit,evidence
core_area,581908.096,um2,MEASURED_OPENROAD_FLOORPLAN
final_design_area,252471,um2,MEASURED_OPENROAD_FINAL
final_utilization,43,percent,MEASURED_OPENROAD_FINAL
placement_violations,${placement_viol},count,MEASURED_OPENROAD_DPL
post_cts_setup_slack,${post_cts_setup},ns,MEASURED_OPENROAD_STA_ESTIMATED_RC
post_cts_hold_slack,${post_cts_hold},ns,MEASURED_OPENROAD_STA_ESTIMATED_RC
post_cts_tns,${post_cts_tns},ns,MEASURED_OPENROAD_STA_ESTIMATED_RC
post_cts_setup_skew,${post_cts_skew},ns,MEASURED_OPENROAD_STA
post_route_setup_slack,${post_route_setup},ns,MEASURED_OPENROAD_STA_SPEF
post_route_hold_slack,${post_route_hold},ns,MEASURED_OPENROAD_STA_SPEF
post_route_tns,${post_route_tns},ns,MEASURED_OPENROAD_STA_SPEF
post_route_setup_skew,${post_route_skew},ns,MEASURED_OPENROAD_STA
detailed_route_drc_errors,${drc},count,MEASURED_OPENROAD_DRT
detailed_route_wirelength,${wire},um,MEASURED_OPENROAD_DRT
detailed_route_vias,${vias},count,MEASURED_OPENROAD_DRT
antenna_violating_nets,${antenna_nets},count,MEASURED_OPENROAD_ANTENNA
antenna_violating_pins,${antenna_pins},count,MEASURED_OPENROAD_ANTENNA
gds_cells,203,count,MEASURED_KLAYOUT
gds_bbox,768.725x768.725,um,MEASURED_KLAYOUT
EOF

sed -i '/^postroute_average_power,/d; /^energy_per_vector_add,/d' "${power}/b0_power_metrics.csv"
cat >>"${power}/b0_power_metrics.csv" <<EOF
postroute_average_power,${power_w},W,MEASURED_OPENROAD_GATE_VCD
energy_per_vector_add,${energy_nj},nJ,DERIVED_POWER_X_DURATION_DIV_OPS
EOF
[[ "${annotated}" -gt 0 ]]
sha256sum "${phybase}/6_final.odb" "${phybase}/6_final.def" "${phybase}/6_final.gds" \
  "${phybase}/6_final.spef" "${phybase}/6_final.v" >"${manifest}/physical_artifact_sha256.txt"
sha256sum "${out}/b0_physical_metrics.csv" "${power}/b0_power_metrics.csv" \
  "${power}/b0_gate_activity.vcd" >"${manifest}/measurement_sha256.txt"
printf 'B0 physical/power collected route_drc=%s power_W=%s energy_nJ_per_add=%s\n' \
  "${drc}" "${power_w}" "${energy_nj}"
