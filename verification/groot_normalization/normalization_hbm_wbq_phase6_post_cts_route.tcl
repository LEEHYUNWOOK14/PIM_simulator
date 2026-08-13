# Phase-6 post-CTS control route. Keep the Phase-4 physical model fixed while
# routing the explicit clock tree from the exact 4_cts checkpoint.

foreach name {WBQ_PLATFORM_ROOT WBQ_CTS_ODB WBQ_CTS_SDC WBQ_ROUTE_OUTPUT_ROOT} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}

set platform_root $::env(WBQ_PLATFORM_ROOT)
set output_root $::env(WBQ_ROUTE_OUTPUT_ROOT)
read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $::env(WBQ_CTS_ODB)
read_sdc $::env(WBQ_CTS_SDC)
source $platform_root/setRC.tcl

# Preserve the exact distributed HBM landing-pad definition used by PF-4.
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
set pitch 250.0
set x0 1500.0
set y0 1500.0
set index 0
foreach name $bump_terms {
  set column [expr {$index % $columns}]
  set row [expr {$index / $columns}]
  place_pin -pin_name $name -layer met5 \
    -location [list [expr {$x0 + $column * $pitch}] [expr {$y0 + $row * $pitch}]] \
    -pin_size {20.0 20.0} -placed_status
  incr index
}
puts "WBQ_PHASE6_POST_CTS_BUMP_PIN_COUNT [llength $bump_terms]"

set_routing_layers -signal met1-met5 -clock met2-met5
puts "WBQ_PHASE6_POST_CTS_ROUTE_STAGE global_route"
global_route \
  -guide_file $output_root/logic_die_normalization_hbm_top_wbq_phase6_post_cts.route_guide \
  -congestion_report_file $output_root/logic_die_normalization_hbm_top_wbq_phase6_post_cts.congestion.rpt \
  -congestion_iterations 1 \
  -congestion_report_iter_step 1 \
  -critical_nets_percentage 0 \
  -snapshot_batched_width 0 \
  -skip_large_fanout_nets 5000 \
  -use_cugr \
  -allow_congestion

report_design_area
write_db $output_root/logic_die_normalization_hbm_top_wbq_phase6_post_cts_global_route.odb
write_sdc $output_root/logic_die_normalization_hbm_top_wbq_phase6_post_cts_global_route.sdc
puts "WBQ_PHASE6_POST_CTS_ROUTE_PASS"
