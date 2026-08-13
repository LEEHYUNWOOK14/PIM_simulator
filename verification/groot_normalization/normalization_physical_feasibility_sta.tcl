set lib $::env(NORM_LIBERTY)
set tech_lef $::env(NORM_TECH_LEF)
set netlist $::env(NORM_NETLIST)
set top $::env(NORM_TOP)
set period $::env(NORM_CLOCK_PERIOD_NS)

read_liberty $lib
read_lef $tech_lef
read_verilog $netlist
link_design $top
create_clock -name clk -period $period [get_ports clk_i]
set_false_path -from [get_ports rst_ni]
set data_inputs [all_inputs]
if {[llength $data_inputs] > 0} { set_input_delay 2.0 -clock clk $data_inputs }
if {[llength [all_outputs]] > 0} { set_output_delay 2.0 -clock clk [all_outputs] }

puts "PHYS_FEAS_CHECK_SETUP_BEGIN"
check_setup -verbose
puts "PHYS_FEAS_CHECK_SETUP_END"
puts "PHYS_FEAS_MAX_PATH_BEGIN"
report_checks -path_delay max -group_count 5 -endpoint_count 5 -format full_clock_expanded
puts "PHYS_FEAS_MAX_PATH_END"
report_worst_slack -max
report_check_types -max_slew -max_capacitance -max_fanout -violators
exit
