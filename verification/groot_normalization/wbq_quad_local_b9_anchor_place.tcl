foreach name {WBQ_PLATFORM_ROOT WBQ_B7_RUDY_ODB WBQ_B2_PLACE_SDC WBQ_B9_POST_LEGALIZE_ODB WBQ_B9_PLACE_ODB WBQ_B9_PLACE_SDC} {
  if {![info exists ::env($name)] || $::env($name) eq ""} { error "missing required environment variable $name" }
}
set platform_root $::env(WBQ_PLATFORM_ROOT)
read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $::env(WBQ_B7_RUDY_ODB)
read_sdc $::env(WBQ_B2_PLACE_SDC)
source $platform_root/setRC.tcl
set block [ord::get_db_block]
set anchor_specs {
  {u_b2_implementation/u_pcu/u_quad_datapath/load_slew427175 6347540 2535040 MX existing}
  {u_b2_implementation/u_quad_local_adapter/wire440835 4686940 1468800 R180 existing}
  {u_b2_implementation/u_quad_local_adapter/wire440455 7308480 4417280 MY added}
  {u_b2_implementation/u_quad_local_adapter/wire440867 4287200 1392640 MY added}
  {u_b2_implementation/u_quad_local_adapter/wire440876 4285360 1479680 R180 added}
  {u_b2_implementation/u_quad_local_adapter/wire441097 4723740 6636800 R0 added}
  {u_b2_implementation/u_quad_local_adapter/wire441921 4376900 2186880 MX added}
  {u_b2_implementation/u_quad_local_adapter/wire441940 4345620 2208640 R0 added}
  {u_b2_implementation/u_quad_local_adapter/wire441994 4293640 2224960 MX added}
}
foreach spec $anchor_specs {
  lassign $spec name anchor_x anchor_y anchor_orient mode
  set inst [$block findInst $name]
  if {$inst eq "NULL"} { error "B9 anchor target is missing: $name" }
  lassign [$inst getOrigin] input_x input_y
  if {$mode eq "existing" && ($input_x != $anchor_x || $input_y != $anchor_y ||
      [$inst getOrient] ne $anchor_orient || [$inst getPlacementStatus] ne "LOCKED")} {
    error "B9 sealed existing anchor mismatch for $name"
  }
  $inst setOrigin $anchor_x $anchor_y
  $inst setOrient $anchor_orient
  $inst setPlacementStatus LOCKED
  puts "WBQ_B9_ANCHOR_LOCKED name={$name} origin_dbu={$anchor_x $anchor_y} orient={$anchor_orient} mode={$mode}"
}
puts "WBQ_B9_ANCHOR_RECOVERY_INPUT odb=$::env(WBQ_B7_RUDY_ODB)"
puts "WBQ_B9_ANCHOR_RECOVERY_POLICY anchor_targets=9 added_targets=7 max_displacement={1000 1000} site_window=100 row_window=20 drc_penalty=100 full_design_diamond=0"
set_placement_padding -global -left 0 -right 0
detailed_placement \
  -max_displacement {1000 1000} \
  -site_search_window 100 -row_search_window 20 -drc_penalty 100
puts "WBQ_B9_NINE_ANCHOR_NEGOTIATION DONE"
write_db $::env(WBQ_B9_POST_LEGALIZE_ODB)
puts "WBQ_B9_POST_LEGALIZE_CHECKPOINT PASS odb=$::env(WBQ_B9_POST_LEGALIZE_ODB)"
foreach spec $anchor_specs {
  lassign $spec name anchor_x anchor_y anchor_orient mode
  set inst [$block findInst $name]
  lassign [$inst getOrigin] actual_x actual_y
  puts "WBQ_B9_ANCHOR_VERIFIED name={$name} origin_dbu={$actual_x $actual_y} orient={[$inst getOrient]} status={[$inst getPlacementStatus]} mode={$mode}"
  if {$actual_x != $anchor_x || $actual_y != $anchor_y || [$inst getOrient] ne $anchor_orient || [$inst getPlacementStatus] ne "LOCKED"} {
    error "B9 detailed placement moved or unlocked anchor $name"
  }
}
optimize_mirroring
set placement_violations [string trim [check_placement -verbose]]
puts "WBQ_B9_PLACE_LEGALITY violations={$placement_violations}"
if {$placement_violations ne ""} { error "B9 placement is not legal: $placement_violations" }
write_db $::env(WBQ_B9_PLACE_ODB)
write_sdc -no_timestamp $::env(WBQ_B9_PLACE_SDC)
puts "WBQ_B9_NINE_ANCHOR_PLACE PASS odb=$::env(WBQ_B9_PLACE_ODB)"
