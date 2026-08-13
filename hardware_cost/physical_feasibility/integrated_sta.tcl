set lib $::env(PF_LIBERTY)
set netlist $::env(PF_NETLIST)
set top $::env(PF_TOP)
set period $::env(PF_CLOCK_PERIOD_NS)

read_liberty $lib
read_verilog $netlist
link_design $top

create_clock -name clk -period $period [get_ports clk_i]
set_false_path -from [get_ports rst_ni]
set data_inputs [all_inputs]
if {[llength $data_inputs] > 0} {
  set_input_delay 2.0 -clock clk $data_inputs
}
if {[llength [all_outputs]] > 0} {
  set_output_delay 2.0 -clock clk [all_outputs]
}

puts "PHYS_FEAS_CHECK_SETUP_BEGIN"
check_setup -verbose
puts "PHYS_FEAS_CHECK_SETUP_END"

puts "PHYS_FEAS_UNCONSTRAINED_BEGIN"
# In OpenSTA, -unconstrained means that unconstrained paths are eligible for
# report_checks; it does not restrict the report to unconstrained paths.
# check_setup is the authoritative endpoint audit and prints an exact count.
check_setup -verbose -unconstrained_endpoints
puts "PHYS_FEAS_UNCONSTRAINED_END"

puts "PHYS_FEAS_MAX_PATH_BEGIN"
report_checks -path_delay max -group_path_count 5 -endpoint_path_count 5 -format full_clock_expanded
puts "PHYS_FEAS_MAX_PATH_END"
report_worst_slack -max
exit
