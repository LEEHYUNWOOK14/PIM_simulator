read_liberty /home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db b1_logic_die_experiment/orfs/results/sky130hd/b1_logic_die_baseline/base/5_1_grt.odb
read_sdc b1_logic_die_experiment/orfs/results/sky130hd/b1_logic_die_baseline/base/5_1_grt.sdc
source /home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd/setRC.tcl
estimate_parasitics -global_routing
report_design_area
report_wire_length -global_route -summary
report_checks -path_delay max -format full_clock_expanded -fields {slew cap input_pins} -digits 4 -group_path_count 1
report_worst_slack -max
report_tns
report_wns
read_vcd -scope b1_hierarchical_tb.dut b1_logic_die_experiment/artifacts/b1_hierarchical.vcd
report_activity_annotation -report_annotated
report_activity_annotation -report_unannotated
report_power -highest_power_instances 20
exit
