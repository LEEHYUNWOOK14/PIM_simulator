foreach name {
  WBQ_PLATFORM_ROOT
  WBQ_B7_RUDY_ODB
  WBQ_B2_PLACE_SDC
  WBQ_B8_POST_LEGALIZE_ODB
  WBQ_B8_PLACE_ODB
  WBQ_B8_PLACE_SDC
} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}

set platform_root $::env(WBQ_PLATFORM_ROOT)
read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $::env(WBQ_B7_RUDY_ODB)
read_sdc $::env(WBQ_B2_PLACE_SDC)
source $platform_root/setRC.tcl

set block [ord::get_db_block]
set anchor_specs {
  {u_b2_implementation/u_pcu/u_quad_datapath/load_slew427175 6347540 2535040 MX}
  {u_b2_implementation/u_quad_local_adapter/wire440835 4686940 1468800 R180}
}
foreach spec $anchor_specs {
  lassign $spec name anchor_x anchor_y anchor_orient
  set inst [$block findInst $name]
  if {$inst eq "NULL"} { error "B8 anchor target is missing: $name" }
  lassign [$inst getOrigin] actual_x actual_y
  if {$actual_x != $anchor_x || $actual_y != $anchor_y ||
      [$inst getOrient] ne $anchor_orient || [$inst getPlacementStatus] ne "LOCKED"} {
    error "B8 sealed B7 RUDY anchor mismatch for $name"
  }
  puts "WBQ_B8_ANCHOR_VERIFIED name={$name} origin_dbu={$actual_x $actual_y} orient={[$inst getOrient]} status={[$inst getPlacementStatus]}"
}

set offender_names {
  u_b2_implementation/u_quad_local_adapter/wire440455
  u_b2_implementation/u_quad_local_adapter/wire440867
  u_b2_implementation/u_quad_local_adapter/wire440876
  u_b2_implementation/u_quad_local_adapter/wire441097
  u_b2_implementation/u_quad_local_adapter/wire441921
  u_b2_implementation/u_quad_local_adapter/wire441940
  u_b2_implementation/u_quad_local_adapter/wire441994
}
foreach name $offender_names {
  set inst [$block findInst $name]
  if {$inst eq "NULL" || [$inst getPlacementStatus] ne "PLACED"} {
    error "B8 sealed offender target is missing or not movable: $name"
  }
  puts "WBQ_B8_OFFENDER_TARGET name={$name}"
}

puts "WBQ_B8_DRC_RECOVERY_INPUT odb=$::env(WBQ_B7_RUDY_ODB)"
puts "WBQ_B8_DRC_RECOVERY_POLICY max_displacement={1000 1000} site_window=100 row_window=20 drc_penalty=100 full_design_diamond=0"
set_placement_padding -global -left 0 -right 0
detailed_placement \
  -max_displacement {1000 1000} \
  -site_search_window 100 -row_search_window 20 -drc_penalty 100
puts "WBQ_B8_HIGHER_DRC_NEGOTIATION DONE"
write_db $::env(WBQ_B8_POST_LEGALIZE_ODB)
puts "WBQ_B8_POST_LEGALIZE_CHECKPOINT PASS odb=$::env(WBQ_B8_POST_LEGALIZE_ODB)"

foreach spec $anchor_specs {
  lassign $spec name anchor_x anchor_y anchor_orient
  set inst [$block findInst $name]
  lassign [$inst getOrigin] actual_x actual_y
  if {$actual_x != $anchor_x || $actual_y != $anchor_y ||
      [$inst getOrient] ne $anchor_orient || [$inst getPlacementStatus] ne "LOCKED"} {
    error "B8 detailed placement moved or unlocked anchor $name"
  }
}

optimize_mirroring
set placement_violations [string trim [check_placement -verbose]]
puts "WBQ_B8_PLACE_LEGALITY violations={$placement_violations}"
if {$placement_violations ne ""} {
  error "B8 placement is not legal: $placement_violations"
}

write_db $::env(WBQ_B8_PLACE_ODB)
write_sdc -no_timestamp $::env(WBQ_B8_PLACE_SDC)
puts "WBQ_B8_HIGHER_DRC_PLACE PASS odb=$::env(WBQ_B8_PLACE_ODB)"
