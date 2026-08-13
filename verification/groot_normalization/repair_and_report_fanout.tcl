set flow /home/chandler/OpenROAD-flow-scripts/flow
set platform $flow/platforms/sky130hd
read_liberty $platform/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $::env(NORM_INPUT_DB)
read_sdc $::env(NORM_INPUT_SDC)
source $platform/setRC.tcl
set_dont_use {sky130_fd_sc_hd__probe* sky130_fd_sc_hd__lpflow_*}
set_max_fanout 64 [current_design]

proc print_top_fanout {label} {
  set ranked {}
  set block [ord::get_db_block]
  foreach net [$block getNets] {
    set fanout 0
    foreach iterm [$net getITerms] {
      if { [$iterm getIoType] == "INPUT" } { incr fanout }
    }
    lappend ranked [list $fanout [$net getName]]
  }
  set ranked [lsort -integer -decreasing -index 0 $ranked]
  puts "${label}_BEGIN"
  foreach item [lrange $ranked 0 19] { puts "[lindex $item 0]\t[lindex $item 1]" }
  puts "${label}_END"
}

print_top_fanout FANOUT_BEFORE_REPAIR
repair_design -pre_placement -max_wire_length 1000 -max_utilization 70
print_top_fanout FANOUT_AFTER_REPAIR
report_check_types -max_fanout -violators
write_db $::env(NORM_OUTPUT_DB)
