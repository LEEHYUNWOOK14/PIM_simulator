foreach name {
  WBQ_PLATFORM_ROOT
  WBQ_B22_PLACE_ODB
  WBQ_B22_PLACE_SDC
  WBQ_B22_ROUTE_OUTPUT_ROOT
  WBQ_B22_CUGR_CONGESTION_ITERATIONS
} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}

set iterations $::env(WBQ_B22_CUGR_CONGESTION_ITERATIONS)
if {![string is integer -strict $iterations] || $iterations != 1} {
  error "B22 congestion iterations must be exactly 1, got $iterations"
}
set platform_root $::env(WBQ_PLATFORM_ROOT)
set output_root $::env(WBQ_B22_ROUTE_OUTPUT_ROOT)
read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $::env(WBQ_B22_PLACE_ODB)
read_sdc $::env(WBQ_B22_PLACE_SDC)
source $platform_root/setRC.tcl

# Keep B2's sealed I/O landing pattern and routing policy. B22 preserves the
# DRC penalty of 100 and the nine-anchor placement that passed legality.
set bump_terms {}
set block [ord::get_db_block]
foreach bterm [$block getBTerms] {
  set name [$bterm getName]
  if {[string match "cmd_*" $name] || [string match "read_*" $name]} {
    lappend bump_terms $name
  }
}
set bump_terms [lsort $bump_terms]
set columns 25
set pitch 300.0
set x0 1500.0
set y0 500.0
set index 0
foreach name $bump_terms {
  set column [expr {$index % $columns}]
  set row [expr {$index / $columns}]
  place_pin -pin_name $name -layer met5 \
    -location [list [expr {$x0 + $column*$pitch}] [expr {$y0 + $row*$pitch}]] \
    -pin_size {20.0 20.0} -placed_status
  incr index
}
puts "WBQ_B22_ROUTE_BUMP_PIN_GRID_COLUMNS $columns"
puts "WBQ_B22_ROUTE_BUMP_PIN_COUNT [llength $bump_terms]"
puts "WBQ_B22_ROUTE_CUGR_CONGESTION_ITERATIONS $iterations"
set_routing_layers -signal met1-met5 -clock met2-met5
global_route \
  -guide_file $output_root/b22_quad_local.route_guide \
  -congestion_report_file $output_root/b22_quad_local.congestion.rpt \
  -congestion_iterations $iterations -congestion_report_iter_step 1 \
  -critical_nets_percentage 0 -snapshot_batched_width 0 \
  -skip_large_fanout_nets 20000 -use_cugr -allow_congestion
report_design_area
write_db $output_root/b22_quad_local_global_route.odb
write_sdc -no_timestamp $output_root/b22_quad_local_global_route.sdc
puts "WBQ_B22_SINGLE_GLOBAL_ROUTE PASS"
