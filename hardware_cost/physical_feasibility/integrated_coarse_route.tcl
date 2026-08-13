set platform_root $::env(PF_PLATFORM_ROOT)
set placed_db $::env(PF_PLACED_DB)
set placed_sdc $::env(PF_PLACED_SDC)
set output_root $::env(PF_ROUTE_OUTPUT_ROOT)

read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $placed_db
read_sdc $placed_sdc
source $platform_root/setRC.tcl

puts "COARSE_ROUTE_STAGE pre_route_area"
report_design_area
puts "COARSE_ROUTE_STAGE detailed_placement"
detailed_placement -max_displacement {500 500} \
  -report_file_name $output_root/detailed_placement.rpt
puts "COARSE_ROUTE_STAGE legal_placement_check"
check_placement -report_file_name $output_root/legal_placement_check.rpt

set_routing_layers -signal met1-met5 -clock met2-met5
puts "COARSE_ROUTE_STAGE global_route"
global_route \
  -guide_file $output_root/logic_die_normalization_hbm_top.route_guide \
  -congestion_report_file $output_root/logic_die_normalization_hbm_top.congestion.rpt \
  -congestion_iterations 1 \
  -skip_large_fanout_nets 5000 \
  -allow_congestion

puts "COARSE_ROUTE_PASS"
