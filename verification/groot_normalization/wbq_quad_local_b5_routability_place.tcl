foreach name {
  WBQ_PLATFORM_ROOT
  WBQ_B2_PLACE_ODB
  WBQ_B2_PLACE_SDC
  WBQ_B5_PLACE_ODB
  WBQ_B5_PLACE_SDC
} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}

# B5 changes only the legalization engine used after the deterministic B4 RUDY
# respread.  The sealed B2 checkpoint remains read-only and all writes use B5.
set platform_root $::env(WBQ_PLATFORM_ROOT)
read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $::env(WBQ_B2_PLACE_ODB)
read_sdc $::env(WBQ_B2_PLACE_SDC)
source $platform_root/setRC.tcl

puts "WBQ_B5_RUDY_PLACE_INPUT odb=$::env(WBQ_B2_PLACE_ODB)"
puts "WBQ_B5_RUDY_PLACE_POLICY skip_initial=1 density=0.49 estimator=RUDY"
set_placement_padding -global -left 0 -right 0

# Match the sealed B4 respread exactly.  RUDY is an estimator inside the
# placer; this command does not consume B5's single global-route allowance.
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
puts "WBQ_B5_RUDY_GLOBAL_PLACEMENT PASS"

# The sole B5 ECO: use the region-aware diamond search engine from a clean
# post-global-placement state.  B4's negotiation legalizer stopped with four
# illegal cells, including two tap overlaps.
detailed_placement -use_diamond_legalizer -max_displacement {1000 1000}
puts "WBQ_B5_DIAMOND_DETAIL_PLACEMENT DONE"
optimize_mirroring

set placement_violations [string trim [check_placement -verbose]]
puts "WBQ_B5_PLACE_LEGALITY violations={$placement_violations}"
if {$placement_violations ne ""} {
  error "B5 placement is not legal: $placement_violations"
}

write_db $::env(WBQ_B5_PLACE_ODB)
write_sdc -no_timestamp $::env(WBQ_B5_PLACE_SDC)
puts "WBQ_B5_RUDY_DIAMOND_PLACE PASS odb=$::env(WBQ_B5_PLACE_ODB)"
