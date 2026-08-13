# Lightweight physical-feasibility continuation from the converged skip-IO
# global placement and the subsequent IO-placement database.  This deliberately
# omits timing-driven replacement, CTS and sign-off repair.
set flow_root /home/chandler/OpenROAD-flow-scripts/flow
set platform_root $flow_root/platforms/sky130hd
set result_root $flow_root/results/sky130hd/normalization_hbm_feasibility/base
set report_root /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/reports/groot_normalization/physical_feasibility

read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $result_root/3_2_place_iop.odb
read_sdc $result_root/2_floorplan.sdc
source $platform_root/setRC.tcl

puts "COARSE_ROUTE_STAGE pre_route_area"
report_design_area
puts "COARSE_ROUTE_STAGE fanout_repair"
set_max_fanout 64 [current_design]
set_dont_use {sky130_fd_sc_hd__probe* sky130_fd_sc_hd__lpflow_*}
repair_design -max_utilization 70
puts "COARSE_ROUTE_STAGE detailed_placement"
detailed_placement -max_displacement {500 500} \
  -report_file_name $report_root/coarse_detailed_placement.rpt
puts "COARSE_ROUTE_STAGE legal_placement_check"
check_placement -report_file_name $report_root/coarse_legal_placement_check.rpt
write_db $report_root/logic_die_normalization_hbm_top_repaired_legal.odb
write_sdc $report_root/logic_die_normalization_hbm_top_repaired_legal.sdc
puts "COARSE_ROUTE_REPAIRED_LEGAL_DB_SAVED"

set_routing_layers -signal met1-met5 -clock met2-met5
puts "COARSE_ROUTE_STAGE global_route"
global_route \
  -guide_file $report_root/logic_die_normalization_hbm_top.route_guide \
  -congestion_report_file $report_root/logic_die_normalization_hbm_top.congestion.rpt \
  -congestion_iterations 10 \
  -skip_large_fanout_nets 10000 \
  -allow_congestion

write_db $report_root/logic_die_normalization_hbm_top_coarse_grt.odb
puts "COARSE_ROUTE_PASS"
