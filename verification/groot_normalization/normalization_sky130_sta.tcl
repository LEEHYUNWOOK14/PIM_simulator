set lib $::env(NORM_LIBERTY)
set tech_lef $::env(NORM_TECH_LEF)
set netlist $::env(NORM_NETLIST)
set top $::env(NORM_TOP)
read_liberty $lib
read_lef $tech_lef
read_verilog $netlist
link_design $top
create_clock -name clk -period 10.0 [get_ports clk_i]
set_false_path -from [get_ports rst_ni]
report_checks -path_delay max -group_count 1 -endpoint_count 1 -format full_clock_expanded
report_worst_slack -max
exit
