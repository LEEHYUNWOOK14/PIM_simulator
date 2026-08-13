set flow_root /home/chandler/OpenROAD-flow-scripts/flow
set platform_root $flow_root/platforms/sky130hd
set result_root $flow_root/results/sky130hd/normalization_hbm_feasibility_v2/base
set report_root /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/reports/groot_normalization/physical_feasibility

read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $result_root/3_3_place_gp.odb
read_sdc $result_root/2_floorplan.sdc
source $platform_root/setRC.tcl

puts "V2_REPAIR_LEGAL_STAGE pre_repair_area"
report_design_area
set_max_fanout 64 [current_design]
set_dont_use {sky130_fd_sc_hd__probe* sky130_fd_sc_hd__lpflow_*}
puts "V2_REPAIR_LEGAL_STAGE fanout_slew_cap_repair"
repair_design -max_utilization 70
report_check_types -max_fanout -violators
puts "V2_REPAIR_LEGAL_STAGE post_repair_area"
report_design_area

puts "V2_REPAIR_LEGAL_STAGE detailed_placement"
detailed_placement -max_displacement {500 500} \
  -report_file_name $report_root/coarse_v2_detailed_placement.rpt
puts "V2_REPAIR_LEGAL_STAGE placement_check"
check_placement -report_file_name $report_root/coarse_v2_legal_placement_check.rpt
write_db $report_root/logic_die_normalization_hbm_top_v2_repaired_legal.odb
write_sdc $report_root/logic_die_normalization_hbm_top_v2_repaired_legal.sdc
puts "V2_REPAIR_LEGAL_PASS"
