read_liberty /home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db b1_logic_die_experiment/orfs/results/sky130hd/b1_logic_die_baseline/base/3_place.odb
read_sdc b1_logic_die_experiment/orfs/results/sky130hd/b1_logic_die_baseline/base/3_place.sdc
source /home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd/setRC.tcl
estimate_parasitics -placement
report_design_area
check_placement -verbose
report_checks -path_delay max -format full_clock_expanded -fields {slew cap input_pins} -digits 4 -group_path_count 1
report_worst_slack -max
report_tns
report_wns
exit

