set flow_root /home/chandler/OpenROAD-flow-scripts/flow
set platform_root $flow_root/platforms/sky130hd
set report_root /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/reports/groot_normalization/physical_feasibility

read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $report_root/logic_die_normalization_hbm_top_v5_bank_regions.odb
read_sdc $report_root/logic_die_normalization_hbm_top_v2_repaired_legal.sdc
source $platform_root/setRC.tcl

# Keep the physical HBM boundary proxy identical to V4 so this experiment
# isolates the effect of bank-local placement.
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
puts "V5_BUMP_PIN_COUNT [llength $bump_terms]"

puts "V5_PLACE_STAGE global_placement"
global_placement \
  -skip_io \
  -density 0.39 \
  -force_center_initial_place \
  -initial_place_max_fanout 5000 \
  -random_seed 42
write_db $report_root/logic_die_normalization_hbm_top_v5_bank_gp.odb

puts "V5_PLACE_STAGE detailed_placement"
detailed_placement \
  -max_displacement {500 500} \
  -report_file_name $report_root/logic_die_normalization_hbm_top_v5_placement_violations.rpt
check_placement -verbose \
  -report_file_name $report_root/logic_die_normalization_hbm_top_v5_check_placement.rpt
report_design_area
write_db $report_root/logic_die_normalization_hbm_top_v5_bank_legal.odb
write_sdc $report_root/logic_die_normalization_hbm_top_v5_bank_legal.sdc
puts "V5_BANK_PLACE_PASS"
