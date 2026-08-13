set flow_root /home/chandler/OpenROAD-flow-scripts/flow
set platform_root $flow_root/platforms/sky130hd
set result_root $flow_root/results/sky130hd/normalization_hbm_feasibility/base
set report_root /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/reports/groot_normalization/physical_feasibility

read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $result_root/3_2_place_iop.odb
read_sdc $result_root/2_floorplan.sdc
source $platform_root/setRC.tcl

proc report_top_fanout {label report_path} {
  set ranked {}
  set max_fanout -1
  set max_name ""
  set block [ord::get_db_block]
  foreach net [$block getNets] {
    set fanout 0
    foreach iterm [$net getITerms] {
      if { [$iterm getIoType] == "INPUT" } { incr fanout }
    }
    if { $fanout > $max_fanout } {
      set max_fanout $fanout
      set max_name [$net getName]
    }
    # Keep only bounded-fanout violations.  Retaining all ~4.5 M nets in a
    # Tcl list consumed more than 20 GB and was itself the memory bottleneck.
    if { $fanout > 64 } { lappend ranked [list $fanout [$net getName]] }
  }
  set ranked [lsort -integer -decreasing -index 0 $ranked]
  set fh [open $report_path w]
  puts $fh "${label}_BEGIN"
  foreach item [lrange $ranked 0 99] { puts $fh "[lindex $item 0]\t[lindex $item 1]" }
  puts $fh "${label}_END"
  close $fh
  puts "${label}_MAX $max_fanout $max_name VIOLATING_NETS [llength $ranked]"
}

puts "REPAIR_LEGAL_STAGE pre_repair_area"
report_design_area
set_max_fanout 64 [current_design]
set_dont_use {sky130_fd_sc_hd__probe* sky130_fd_sc_hd__lpflow_*}
puts "REPAIR_LEGAL_STAGE fanout_repair"
repair_design -max_utilization 70
report_check_types -max_fanout -violators
puts "REPAIR_LEGAL_STAGE post_repair_area"
report_design_area

puts "REPAIR_LEGAL_STAGE detailed_placement"
detailed_placement -max_displacement {500 500} \
  -report_file_name $report_root/coarse_detailed_placement.rpt
puts "REPAIR_LEGAL_STAGE placement_check"
check_placement -report_file_name $report_root/coarse_legal_placement_check.rpt
write_db $report_root/logic_die_normalization_hbm_top_repaired_legal.odb
write_sdc $report_root/logic_die_normalization_hbm_top_repaired_legal.sdc
puts "REPAIR_LEGAL_PASS"
