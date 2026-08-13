set flow_root /home/chandler/OpenROAD-flow-scripts/flow
set platform_root $flow_root/platforms/sky130hd
set report_root /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/reports/groot_normalization/physical_feasibility
read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $report_root/logic_die_normalization_hbm_top_repaired_legal.odb
read_sdc $report_root/logic_die_normalization_hbm_top_repaired_legal.sdc
source $platform_root/setRC.tcl
set_routing_layers -signal met1-met5 -clock met2-met5
puts "ROUTE_FROM_LEGAL_STAGE global_route"
global_route \
  -guide_file $report_root/logic_die_normalization_hbm_top.route_guide \
  -congestion_report_file $report_root/logic_die_normalization_hbm_top.congestion.rpt \
  -congestion_iterations 1 \
  -congestion_report_iter_step 1 \
  -critical_nets_percentage 0 \
  -snapshot_batched_width 0 \
  -skip_large_fanout_nets 5000 \
  -use_cugr \
  -allow_congestion
report_design_area
puts "ROUTE_FROM_LEGAL_PASS"
