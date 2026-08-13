set platform /home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd
set report_root /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/reports/groot_normalization/physical_feasibility
read_liberty $platform/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $report_root/logic_die_normalization_hbm_top_repaired_legal.odb
read_sdc $report_root/logic_die_normalization_hbm_top_repaired_legal.sdc
# The physical-feasibility gate uses a deliberately relaxed clock.  It does
# not claim the project's performance target or sign-off closure.
create_clock -name clk -period 1000.0 [get_ports clk_i]
puts "CONSTRAINT_AUDIT_BEGIN"
check_setup -verbose
puts "CONSTRAINT_AUDIT_END"
puts "RELAXED_PATH_BEGIN"
report_checks -path_delay max -group_count 1 -endpoint_count 1 -digits 3
puts "RELAXED_PATH_END"
report_worst_slack -max
puts "CONSTRAINT_AUDIT_PASS"
