foreach name {
  WBQ_PLATFORM_ROOT
  WBQ_B2_PLACE_ODB
  WBQ_B2_PLACE_SDC
  WBQ_B4_PLACE_ODB
  WBQ_B4_PLACE_SDC
} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}

# B4 changes placement only.  The sealed B2 checkpoint is read-only and every
# write goes to an isolated B4 path.
set platform_root $::env(WBQ_PLATFORM_ROOT)
read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $::env(WBQ_B2_PLACE_ODB)
read_sdc $::env(WBQ_B2_PLACE_SDC)
source $platform_root/setRC.tcl

puts "WBQ_B4_RUDY_PLACE_INPUT odb=$::env(WBQ_B2_PLACE_ODB)"
puts "WBQ_B4_RUDY_PLACE_POLICY skip_initial=1 density=0.49 estimator=RUDY"
set_placement_padding -global -left 0 -right 0

# Start from B2's legal coordinates instead of force-centering millions of
# cells.  RUDY is the placer's estimator and does not invoke global_route.
global_placement \
  -skip_initial_place \
  -routability_driven \
  -density 0.49 \
  -pad_left 0 -pad_right 0 \
  -min_phi_coef 0.95 -max_phi_coef 1.05 \
  -routability_check_overflow 0.30 \
  -routability_snapshot_overflow 0.60 \
  -routability_target_rc_metric 1.01 \
  -routability_max_density 0.99 \
  -routability_inflation_ratio_coef 2.0 \
  -routability_max_inflation_ratio 3.0 \
  -routability_rc_coefficients {1.0 1.0 0.0 0.0}
puts "WBQ_B4_RUDY_GLOBAL_PLACEMENT PASS"

# Use the same large-design legalization settings that produced the sealed B2
# legal checkpoint.  A second incremental pass absorbs any remaining local
# displacement after inflation is removed.
detailed_placement \
  -max_displacement {1000 1000} \
  -site_search_window 100 -row_search_window 20 -drc_penalty 20
puts "WBQ_B4_DETAIL_PLACEMENT_PRIMARY DONE"
detailed_placement -incremental \
  -max_displacement {1000 1000} \
  -site_search_window 100 -row_search_window 20 -drc_penalty 20
puts "WBQ_B4_DETAIL_PLACEMENT_INCREMENTAL DONE"
optimize_mirroring

set placement_violations [string trim [check_placement -verbose]]
puts "WBQ_B4_PLACE_LEGALITY violations={$placement_violations}"
if {$placement_violations ne ""} {
  error "B4 placement is not legal: $placement_violations"
}

write_db $::env(WBQ_B4_PLACE_ODB)
write_sdc -no_timestamp $::env(WBQ_B4_PLACE_SDC)
puts "WBQ_B4_RUDY_PLACE PASS odb=$::env(WBQ_B4_PLACE_ODB)"
