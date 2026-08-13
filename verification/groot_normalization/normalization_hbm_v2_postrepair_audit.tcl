set flow_root /home/chandler/OpenROAD-flow-scripts/flow
set platform_root $flow_root/platforms/sky130hd
set report_root /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/reports/groot_normalization/physical_feasibility
read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $report_root/logic_die_normalization_hbm_top_v2_repaired_legal.odb
read_sdc $report_root/logic_die_normalization_hbm_top_v2_repaired_legal.sdc

set max_data_fanout -1
set max_data_name ""
set violations 0
set block [ord::get_db_block]
foreach net [$block getNets] {
  set name [$net getName]
  if { $name == "clk_i" || $name == "rst_ni" } { continue }
  set fanout 0
  foreach iterm [$net getITerms] {
    if { [$iterm getIoType] == "INPUT" } { incr fanout }
  }
  if { $fanout > $max_data_fanout } {
    set max_data_fanout $fanout
    set max_data_name $name
  }
  if { $fanout > 64 } { incr violations }
}
puts "POSTREPAIR_MAX_DATA_FANOUT $max_data_fanout $max_data_name"
puts "POSTREPAIR_DATA_FANOUT_VIOLATIONS $violations"
check_placement -report_file_name $report_root/coarse_v2_legal_placement_recheck.rpt
puts "V2_POSTREPAIR_AUDIT_PASS"
