set report_root /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/reports/groot_normalization/physical_feasibility
read_db $report_root/logic_die_normalization_hbm_top_v5_bank_gp.odb

puts "V5_RELEGALIZE_STAGE detailed_placement_pass1"
detailed_placement \
  -max_displacement {500 500} \
  -report_file_name $report_root/logic_die_normalization_hbm_top_v5_relegalize_pass1_violations.rpt
write_db $report_root/logic_die_normalization_hbm_top_v5_relegalize_pass1.odb

# The first legalizer pass removes more than 99.99% of conflicts.  Re-seed a
# second local pass from those improved coordinates so the small set trapped
# against fixed tapcells can negotiate different nearby sites.
puts "V5_RELEGALIZE_STAGE detailed_placement_pass2"
detailed_placement \
  -incremental \
  -max_displacement {500 500} \
  -drc_penalty 20 \
  -report_file_name $report_root/logic_die_normalization_hbm_top_v5_relegalize_pass2_violations.rpt
check_placement -verbose \
  -report_file_name $report_root/logic_die_normalization_hbm_top_v5_relegalize_check.rpt
report_design_area
write_db $report_root/logic_die_normalization_hbm_top_v5_bank_legal.odb
puts "V5_RELEGALIZE_PASS"
