set flow_root /home/chandler/OpenROAD-flow-scripts/flow
set platform_root $flow_root/platforms/sky130hd
set report_root /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/reports/groot_normalization/physical_feasibility
read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $report_root/logic_die_normalization_hbm_top_repaired_legal.odb
read_sdc $report_root/logic_die_normalization_hbm_top_repaired_legal.sdc
source $platform_root/setRC.tcl
estimate_parasitics -placement
puts "STA_AUDIT_CHECK_SETUP_BEGIN"
check_setup -verbose
puts "STA_AUDIT_CHECK_SETUP_END"
puts "STA_AUDIT_WORST_PATH_BEGIN"
report_checks -path_delay max -group_count 5 -endpoint_count 1 -digits 3
puts "STA_AUDIT_WORST_PATH_END"
report_worst_slack -max
report_check_types -max_fanout -violators
puts "STA_AUDIT_PASS"
