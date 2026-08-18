foreach name {WBQ_PLATFORM_ROOT WBQ_GRT_ODB WBQ_GRT_SDC WBQ_DRT_OUTPUT_ROOT} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}
set platform_root $::env(WBQ_PLATFORM_ROOT)
set output_root $::env(WBQ_DRT_OUTPUT_ROOT)
read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $::env(WBQ_GRT_ODB)
read_sdc $::env(WBQ_GRT_SDC)
source $platform_root/setRC.tcl
if {![grt::have_routes]} { error "B6 Phase 7 input has no global routes" }
set_routing_layers -signal met1-met5 -clock met2-met5
set_propagated_clock [all_clocks]
puts "WBQ_B6_PHASE7_DETAILED_ROUTE_STAGE detailed_route"
detailed_route \
  -output_drc $output_root/b6_phase7_detailed_route.drc.rpt \
  -output_maze $output_root/b6_phase7_detailed_route.maze.log \
  -droute_end_iter 64 -drc_report_iter_step 5 -verbose 1
set fully_routed [design_is_routed]
puts "WBQ_B6_PHASE7_DESIGN_IS_ROUTED $fully_routed"
if {!$fully_routed} { error "B6 Phase 7 ended with unrouted nets" }
check_antennas -report_file $output_root/b6_phase7_antenna.rpt
report_checks -path_delay max -group_count 5 -endpoint_count 5 -format full_clock_expanded \
  > $output_root/b6_phase7_timing.rpt
report_tns >> $output_root/b6_phase7_timing.rpt
report_wns >> $output_root/b6_phase7_timing.rpt
report_worst_slack -max >> $output_root/b6_phase7_timing.rpt
report_check_types -max_slew -violators > $output_root/b6_phase7_max_slew.rpt
report_check_types -max_capacitance -violators > $output_root/b6_phase7_max_capacitance.rpt
report_check_types -max_fanout -violators > $output_root/b6_phase7_max_fanout.rpt
report_design_area
write_db $output_root/b6_phase7_detailed_route.odb
write_sdc -no_timestamp $output_root/b6_phase7_detailed_route.sdc
write_def $output_root/b6_phase7_detailed_route.def
write_verilog $output_root/b6_phase7_detailed_route.v
puts "WBQ_B6_PHASE7_DETAILED_ROUTE PASS"
