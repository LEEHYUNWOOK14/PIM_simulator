set flow_root /home/chandler/OpenROAD-flow-scripts/flow
set platform_root $flow_root/platforms/sky130hd
set report_root /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/reports/groot_normalization/physical_feasibility

read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $report_root/logic_die_normalization_hbm_top_v5_bank_gp.odb
read_sdc $report_root/logic_die_normalization_hbm_top_v2_repaired_legal.sdc

set block [ord::get_db_block]
set removed 0
foreach inst [$block getInsts] {
  set name [$inst getName]
  if {[string match "TAP_TAPCELL*" $name]} {
    odb::dbInst_destroy $inst
    incr removed
  }
}
puts "V5_REMOVED_TAPCELLS $removed"
if {$removed == 0} {
  error "no legacy tapcells were removed"
}

# Region groups are soft locality guides for global placement.  Release them
# before legalization so a small number of boundary cells can cross the guide
# edge to the nearest legal site while the converged bank-local coordinates
# remain the legalization starting point.
set released_groups 0
set released_regions 0
foreach region [$block getRegions] {
  foreach group [$region getGroups] {
    odb::dbGroup_destroy $group
    incr released_groups
  }
  odb::dbRegion_destroy $region
  incr released_regions
}
puts "V5_RELEASED_GROUPS $released_groups"
puts "V5_RELEASED_REGIONS $released_regions"
if {$released_groups != 16 || $released_regions != 16} {
  error "expected 16 bank guides to release"
}

puts "V5_TAP_REBUILD_STAGE standard_cell_legalize"
detailed_placement \
  -max_displacement {500 500} \
  -report_file_name $report_root/logic_die_normalization_hbm_top_v5_tapless_violations.rpt
check_placement -verbose \
  -report_file_name $report_root/logic_die_normalization_hbm_top_v5_tapless_check.rpt
write_db $report_root/logic_die_normalization_hbm_top_v5_tapless_legal.odb

puts "V5_TAP_REBUILD_STAGE tapcell_insert"
tapcell \
  -distance 14 \
  -tapcell_master sky130_fd_sc_hd__tapvpwrvgnd_1
check_placement -verbose \
  -report_file_name $report_root/logic_die_normalization_hbm_top_v5_tap_rebuilt_check.rpt
report_design_area
write_db $report_root/logic_die_normalization_hbm_top_v5_bank_legal.odb
write_sdc $report_root/logic_die_normalization_hbm_top_v5_bank_legal.sdc
puts "V5_TAP_REBUILD_PASS"
