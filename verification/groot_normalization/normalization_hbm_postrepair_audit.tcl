set flow_root /home/chandler/OpenROAD-flow-scripts/flow
set platform_root $flow_root/platforms/sky130hd
set report_root /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/reports/groot_normalization/physical_feasibility
read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $report_root/logic_die_normalization_hbm_top_repaired_legal.odb
read_sdc $report_root/logic_die_normalization_hbm_top_repaired_legal.sdc
source $platform_root/setRC.tcl

set max_data_fanout -1
set max_data_name ""
set violations 0
set fh [open $report_root/integrated_fanout_after.rpt w]
puts $fh "FANOUT_AFTER_REPAIR_BEGIN"
set block [ord::get_db_block]
foreach net [$block getNets] {
  set name [$net getName]
  if { $name == "clk_i" || $name == "rst_ni" } { continue }
  set fanout 0
  foreach iterm [$net getITerms] {
    if { [$iterm getIoType] == "INPUT" } { incr fanout }
  }
  if { $fanout > $max_data_fanout } { set max_data_fanout $fanout; set max_data_name $name }
  if { $fanout > 64 } { incr violations; puts $fh "$fanout\t$name" }
}
puts $fh "FANOUT_AFTER_REPAIR_END"
close $fh
puts "POSTREPAIR_MAX_DATA_FANOUT $max_data_fanout $max_data_name"
puts "POSTREPAIR_DATA_FANOUT_VIOLATIONS $violations"
check_placement -report_file_name $report_root/coarse_legal_placement_recheck.rpt
check_setup -verbose
puts "POSTREPAIR_CHECK_SETUP_DONE"
