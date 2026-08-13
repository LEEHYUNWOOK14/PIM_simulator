set flow_root /home/chandler/OpenROAD-flow-scripts/flow
set platform_root $flow_root/platforms/sky130hd
set report_root /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/reports/groot_normalization/physical_feasibility

read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $report_root/logic_die_normalization_hbm_top_v2_repaired_legal.odb
read_sdc $report_root/logic_die_normalization_hbm_top_v2_repaired_legal.sdc
source $platform_root/setRC.tcl

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
puts "V3_BUMP_PIN_COUNT [llength $bump_terms]"

set_routing_layers -signal met2-met5 -clock met2-met5
puts "V3_ROUTE_STAGE global_route"
global_route \
  -guide_file $report_root/logic_die_normalization_hbm_top_v3.route_guide \
  -congestion_report_file $report_root/logic_die_normalization_hbm_top_v3.congestion.rpt \
  -congestion_iterations 5 \
  -congestion_report_iter_step 5 \
  -critical_nets_percentage 0 \
  -snapshot_batched_width 0 \
  -skip_large_fanout_nets 5000 \
  -use_cugr \
  -allow_congestion
report_design_area
puts "V3_ROUTE_PASS"
