foreach name {
  WBQ_PLATFORM_ROOT
  WBQ_B2_PLACE_ODB
  WBQ_B2_PLACE_SDC
  WBQ_B6_RUDY_ODB
  WBQ_B6_POST_LEGALIZE_ODB
  WBQ_B6_PLACE_ODB
  WBQ_B6_PLACE_SDC
} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}

set platform_root $::env(WBQ_PLATFORM_ROOT)
read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $::env(WBQ_B2_PLACE_ODB)
read_sdc $::env(WBQ_B2_PLACE_SDC)
source $platform_root/setRC.tcl

# B4's only remaining violations were two movable buffers placed on fixed
# tapcells. Preserve their exact legal B2 origins and orientations before RUDY
# so global and detailed placement treat them as local fixed anchors.
set block [ord::get_db_block]
set anchor_specs {
  {u_b2_implementation/u_pcu/u_quad_datapath/load_slew427175 6347540 2535040 MX}
  {u_b2_implementation/u_quad_local_adapter/wire440835 4686940 1468800 R180}
}
foreach spec $anchor_specs {
  lassign $spec name anchor_x anchor_y anchor_orient
  set inst [$block findInst $name]
  if {$inst eq "NULL"} { error "B6 anchor target is missing: $name" }
  lassign [$inst getOrigin] input_x input_y
  set input_orient [$inst getOrient]
  if {$input_x != $anchor_x || $input_y != $anchor_y || $input_orient ne $anchor_orient} {
    error "B6 sealed B2 anchor mismatch for $name"
  }
  $inst setOrigin $anchor_x $anchor_y
  $inst setOrient $anchor_orient
  $inst setPlacementStatus LOCKED
  puts "WBQ_B6_ANCHOR_LOCKED name={$name} origin_dbu={$anchor_x $anchor_y} orient={$anchor_orient}"
}

puts "WBQ_B6_RUDY_PLACE_INPUT odb=$::env(WBQ_B2_PLACE_ODB)"
puts "WBQ_B6_RUDY_PLACE_POLICY skip_initial=1 density=0.49 estimator=RUDY"
set_placement_padding -global -left 0 -right 0
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
puts "WBQ_B6_RUDY_GLOBAL_PLACEMENT PASS"
write_db $::env(WBQ_B6_RUDY_ODB)
puts "WBQ_B6_RUDY_CHECKPOINT PASS odb=$::env(WBQ_B6_RUDY_ODB)"

foreach spec $anchor_specs {
  lassign $spec name anchor_x anchor_y anchor_orient
  set inst [$block findInst $name]
  lassign [$inst getOrigin] actual_x actual_y
  if {$actual_x != $anchor_x || $actual_y != $anchor_y ||
      [$inst getOrient] ne $anchor_orient || [$inst getPlacementStatus] ne "LOCKED"} {
    error "B6 RUDY moved or unlocked anchor $name"
  }
}

# Reproduce B4's fast negotiation result. It reduced 440 illegal cells to two
# movable-vs-fixed-tap overlaps in 315 seconds; unlike B5, no full-design
# diamond search is allowed here.
detailed_placement \
  -max_displacement {1000 1000} \
  -site_search_window 100 -row_search_window 20 -drc_penalty 20
puts "WBQ_B6_NEGOTIATION_PRIMARY DONE"
write_db $::env(WBQ_B6_POST_LEGALIZE_ODB)
puts "WBQ_B6_POST_LEGALIZE_CHECKPOINT PASS odb=$::env(WBQ_B6_POST_LEGALIZE_ODB)"

foreach spec $anchor_specs {
  lassign $spec name anchor_x anchor_y anchor_orient
  set inst [$block findInst $name]
  lassign [$inst getOrigin] actual_x actual_y
  puts "WBQ_B6_ANCHOR_VERIFIED name={$name} origin_dbu={$actual_x $actual_y} orient={[$inst getOrient]} status={[$inst getPlacementStatus]}"
  if {$actual_x != $anchor_x || $actual_y != $anchor_y ||
      [$inst getOrient] ne $anchor_orient || [$inst getPlacementStatus] ne "LOCKED"} {
    error "B6 detailed placement moved or unlocked anchor $name"
  }
}

optimize_mirroring
set placement_violations [string trim [check_placement -verbose]]
puts "WBQ_B6_PLACE_LEGALITY violations={$placement_violations}"
if {$placement_violations ne ""} {
  error "B6 placement is not legal: $placement_violations"
}

write_db $::env(WBQ_B6_PLACE_ODB)
write_sdc -no_timestamp $::env(WBQ_B6_PLACE_SDC)
puts "WBQ_B6_TARGETED_ANCHOR_PLACE PASS odb=$::env(WBQ_B6_PLACE_ODB)"
