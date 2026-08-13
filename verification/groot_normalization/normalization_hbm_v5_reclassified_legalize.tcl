set report_root /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/reports/groot_normalization/physical_feasibility

read_db $report_root/logic_die_normalization_hbm_top_v5_bank_gp_reclassified.odb
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
puts "V5_RECLASSIFIED_REMOVED_TAPCELLS $removed"
if {$removed == 0} {
  error "no legacy tapcells were removed"
}

puts "V5_RECLASSIFIED_STAGE standard_cell_legalize"
detailed_placement \
  -max_displacement {500 500} \
  -report_file_name $report_root/logic_die_normalization_hbm_top_v5_reclassified_violations.rpt
check_placement -verbose \
  -report_file_name $report_root/logic_die_normalization_hbm_top_v5_reclassified_tapless_check.rpt
write_db $report_root/logic_die_normalization_hbm_top_v5_reclassified_tapless_legal.odb

puts "V5_RECLASSIFIED_STAGE tapcell_insert"
tapcell \
  -distance 14 \
  -tapcell_master sky130_fd_sc_hd__tapvpwrvgnd_1
check_placement -verbose \
  -report_file_name $report_root/logic_die_normalization_hbm_top_v5_reclassified_check.rpt
report_design_area
write_db $report_root/logic_die_normalization_hbm_top_v5_bank_legal.odb
write_sdc $report_root/logic_die_normalization_hbm_top_v5_bank_legal.sdc
puts "V5_RECLASSIFIED_LEGALIZE_PASS"
