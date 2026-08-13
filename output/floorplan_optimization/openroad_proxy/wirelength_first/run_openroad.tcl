read_lef /home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd/lef/sky130_fd_sc_hd.tlef
read_lef /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/output/floorplan_optimization/openroad_proxy/wirelength_first/floorplan_macros.lef
read_liberty /home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_verilog /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/output/floorplan_optimization/openroad_proxy/wirelength_first/floorplan_proxy.v
link_design STOB_FLOORPLAN_PROXY
initialize_floorplan -die_area {0 0 800.000000 1200.000000} -core_area {2 2 798.000000 1198.000000} -site unithd
source /home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd/make_tracks.tcl
place_inst -name u_block_0 -location {267.500000 102.500000} -orientation R0 -status FIRM
place_inst -name u_block_1 -location {467.500000 657.500000} -orientation R180 -status FIRM
place_inst -name u_block_2 -location {167.500000 657.500000} -orientation MX -status FIRM
place_inst -name u_block_3 -location {67.500000 102.500000} -orientation R0 -status FIRM
place_inst -name u_block_4 -location {267.500000 642.500000} -orientation R0 -status FIRM
place_inst -name u_block_5 -location {60.000000 657.500000} -orientation R0 -status FIRM
place_inst -name u_block_6 -location {167.500000 117.500000} -orientation R180 -status FIRM
place_inst -name u_block_7 -location {467.500000 110.000000} -orientation MX -status FIRM
place_inst -name u_tsv_ch0 -location {48.500000 137.500000} -orientation R0 -status FIRM
place_inst -name u_tsv_ch1 -location {148.500000 137.500000} -orientation R0 -status FIRM
place_inst -name u_tsv_ch2 -location {248.500000 137.500000} -orientation R0 -status FIRM
place_inst -name u_tsv_ch3 -location {348.500000 137.500000} -orientation R0 -status FIRM
place_inst -name u_tsv_ch4 -location {448.500000 137.500000} -orientation R0 -status FIRM
place_inst -name u_tsv_ch5 -location {548.500000 137.500000} -orientation R0 -status FIRM
place_inst -name u_tsv_ch6 -location {648.500000 137.500000} -orientation R0 -status FIRM
place_inst -name u_tsv_ch7 -location {748.500000 137.500000} -orientation R0 -status FIRM
source /home/chandler/OpenROAD-flow-scripts/flow/platforms/sky130hd/setRC.tcl
set_routing_layers -signal met2-met5 -clock met3-met5
global_route -allow_congestion -guide_file /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/output/floorplan_optimization/openroad_proxy/wirelength_first/route.guide -congestion_report_file /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/output/floorplan_optimization/openroad_proxy/wirelength_first/congestion.rpt
report_wire_length -global_route -summary -file /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/output/floorplan_optimization/openroad_proxy/wirelength_first/wire_length.rpt
check_placement -verbose -report_file_name /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/output/floorplan_optimization/openroad_proxy/wirelength_first/placement_check.rpt
write_def /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/output/floorplan_optimization/openroad_proxy/wirelength_first/floorplan_proxy.def
write_db /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/output/floorplan_optimization/openroad_proxy/wirelength_first/floorplan_proxy.odb
puts "STOB_OPENROAD_PROXY PASS"
exit
