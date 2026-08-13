read_liberty /home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db b1_logic_die_experiment/orfs/results/sky130hd/b1_logic_die_baseline/base/1_synth.odb
read_sdc b1_logic_die_experiment/orfs/results/sky130hd/b1_logic_die_baseline/base/1_synth.sdc
source /home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd/setRC.tcl
report_design_area
report_checks -path_delay max -format full_clock_expanded -fields {slew cap input_pins} -digits 4 -group_count 10
report_worst_slack -max
report_tns
report_wns
exit
