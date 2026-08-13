set flow_root /home/chandler/OpenROAD-flow-scripts/flow
set platform_root $flow_root/platforms/sky130hd
set report_root /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/reports/groot_normalization/physical_feasibility

read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $report_root/logic_die_normalization_hbm_top_v5_bank_gp.odb
read_sdc $report_root/logic_die_normalization_hbm_top_v2_repaired_legal.sdc

set block [ord::get_db_block]
set released_groups 0
set released_regions 0
set retained_tapcells 0
foreach inst [$block getInsts] {
  if {[string match "TAP_TAPCELL*" [$inst getName]]} {
    incr retained_tapcells
  }
}
foreach region [$block getRegions] {
  foreach group [$region getGroups] {
    odb::dbGroup_destroy $group
    incr released_groups
  }
  odb::dbRegion_destroy $region
  incr released_regions
}
puts "V5_RETAINED_TAPCELLS $retained_tapcells"
puts "V5_RELEASED_GROUPS $released_groups"
puts "V5_RELEASED_REGIONS $released_regions"
if {$retained_tapcells != 1080364} {
  error "unexpected legacy tapcell count"
}
if {$released_groups != 16 || $released_regions != 16} {
  error "expected 16 bank guides to release"
}

puts "V5_RELEASE_LEGALIZE_STAGE detailed_placement"
detailed_placement \
  -max_displacement {500 500} \
  -report_file_name $report_root/logic_die_normalization_hbm_top_v5_release_legalize_violations.rpt
check_placement -verbose \
  -report_file_name $report_root/logic_die_normalization_hbm_top_v5_release_legalize_check.rpt
report_design_area
write_db $report_root/logic_die_normalization_hbm_top_v5_bank_legal.odb
write_sdc $report_root/logic_die_normalization_hbm_top_v5_bank_legal.sdc
puts "V5_RELEASE_LEGALIZE_PASS"
