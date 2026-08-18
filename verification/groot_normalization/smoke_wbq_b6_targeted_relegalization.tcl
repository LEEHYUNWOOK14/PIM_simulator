foreach name {WBQ_PLATFORM_ROOT WBQ_B2_PLACE_ODB WBQ_B2_PLACE_SDC} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}

read_liberty $::env(WBQ_PLATFORM_ROOT)/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $::env(WBQ_B2_PLACE_ODB)
read_sdc $::env(WBQ_B2_PLACE_SDC)
source $::env(WBQ_PLATFORM_ROOT)/setRC.tcl
set_placement_padding -global -left 0 -right 0

set block [ord::get_db_block]
set anchor_specs {
  {u_b2_implementation/u_pcu/u_quad_datapath/load_slew427175 6347540 2535040 MX}
  {u_b2_implementation/u_quad_local_adapter/wire440835 4686940 1468800 R180}
}
foreach spec $anchor_specs {
  lassign $spec name anchor_x anchor_y anchor_orient
  set inst [$block findInst $name]
  if {$inst eq "NULL"} { error "missing B6 smoke target: $name" }
  lassign [$inst getOrigin] actual_x actual_y
  if {$actual_x != $anchor_x || $actual_y != $anchor_y || [$inst getOrient] ne $anchor_orient} {
    error "B6 smoke input anchor mismatch: $name"
  }
  $inst setOrigin $anchor_x $anchor_y
  $inst setOrient $anchor_orient
  $inst setPlacementStatus LOCKED
  puts "WBQ_B6_SMOKE_ANCHOR name={$name} origin_dbu={$actual_x $actual_y} orient={[$inst getOrient]} status={[$inst getPlacementStatus]}"
}
set violations [string trim [check_placement -verbose]]
puts "WBQ_B6_SMOKE_LEGALITY violations={$violations}"
if {$violations ne ""} { error "B6 targeted anchor smoke check failed" }
puts "WBQ_B6_TARGETED_ANCHOR_SMOKE PASS"
