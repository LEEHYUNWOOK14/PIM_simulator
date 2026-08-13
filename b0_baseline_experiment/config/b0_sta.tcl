set lib $::env(B0_LIBERTY)
set tech_lef $::env(B0_TECH_LEF)
set netlist $::env(B0_NETLIST)
set top $::env(B0_TOP)
set period $::env(B0_CLOCK_PERIOD_NS)

read_liberty $lib
read_lef $tech_lef
read_verilog $netlist
link_design $top
create_clock -name clk -period $period [get_ports clk_i]
set_clock_uncertainty 0.2 [get_clocks clk]
set_false_path -from [get_ports rst_ni]

puts "B0_STA_CHECK_SETUP_BEGIN"
check_setup -verbose
puts "B0_STA_CHECK_SETUP_END"
puts "B0_STA_MAX_PATH_BEGIN"
report_checks -path_delay max -group_count 5 -endpoint_count 5 -format full_clock_expanded
puts "B0_STA_MAX_PATH_END"
report_worst_slack -max
report_check_types -max_slew -max_capacitance -max_fanout -violators
exit
