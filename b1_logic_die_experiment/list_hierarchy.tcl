read_liberty /home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db b1_logic_die_experiment/orfs/results/sky130hd/b1_logic_die_baseline/base/5_1_grt.odb
foreach pattern {g_logic_die_enabled.u_logic_die* g_logic_die_enabled/u_logic_die* *u_logic_die* g_channel*} {
  set cells [get_cells -hierarchical -quiet $pattern]
  puts "PATTERN=$pattern COUNT=[llength $cells]"
}
exit
