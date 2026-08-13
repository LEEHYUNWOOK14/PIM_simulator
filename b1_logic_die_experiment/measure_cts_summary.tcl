read_liberty /home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db b1_logic_die_experiment/orfs/results/sky130hd/b1_logic_die_baseline/base/4_cts.odb
read_sdc b1_logic_die_experiment/orfs/results/sky130hd/b1_logic_die_baseline/base/4_cts.sdc
source /home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd/setRC.tcl
estimate_parasitics -placement
report_worst_slack -max
report_tns
report_wns
exit
