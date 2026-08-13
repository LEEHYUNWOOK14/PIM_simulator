read_liberty /home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db b1_logic_die_experiment/orfs/results/sky130hd/b1_logic_die_baseline/base/5_1_grt.odb
read_sdc b1_logic_die_experiment/orfs/results/sky130hd/b1_logic_die_baseline/base/5_1_grt.sdc
source /home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd/setRC.tcl
estimate_parasitics -global_routing
set_power_activity -input -activity 0.001210915761485666 -duty 0.305581033452192
set logic_cells [get_cells -hierarchical -quiet {g_logic_die_enabled.u_logic_die*}]
set bank_cells [get_cells -hierarchical -quiet {g_channel*}]
puts "LOGIC_DIE_LEAF_CELLS=[llength $logic_cells]"
report_power -instances $logic_cells
puts "BANK_HIERARCHY_LEAF_CELLS=[llength $bank_cells]"
report_power -instances $bank_cells
exit
