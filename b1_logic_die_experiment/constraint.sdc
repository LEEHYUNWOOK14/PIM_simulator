create_clock -name clk -period 10.0 [get_ports clk_i]
set_clock_uncertainty 0.2 [get_clocks clk]
set_false_path -from [get_ports rst_ni]

