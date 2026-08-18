foreach name {WBQ_PLATFORM_ROOT WBQ_B7_RUDY_ODB WBQ_B2_PLACE_SDC WBQ_B8_SMOKE_ODB} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}

read_liberty $::env(WBQ_PLATFORM_ROOT)/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $::env(WBQ_B7_RUDY_ODB)
read_sdc $::env(WBQ_B2_PLACE_SDC)
source $::env(WBQ_PLATFORM_ROOT)/setRC.tcl
set_placement_padding -global -left 0 -right 0
set block [ord::get_db_block]
if {[$block getName] ne "logic_die_normalization_hbm_quad_local_b2_top"} {
  error "unexpected B8 smoke top [$block getName]"
}
if {[llength [$block getRegions]] != 4} { error "B8 smoke expected four quad fences" }

set anchor_specs {
  {u_b2_implementation/u_pcu/u_quad_datapath/load_slew427175 6347540 2535040 MX}
  {u_b2_implementation/u_quad_local_adapter/wire440835 4686940 1468800 R180}
}
foreach spec $anchor_specs {
  lassign $spec name expected_x expected_y expected_orient
  set inst [$block findInst $name]
  if {$inst eq "NULL"} { error "missing B8 smoke anchor: $name" }
  lassign [$inst getOrigin] actual_x actual_y
  if {$actual_x != $expected_x || $actual_y != $expected_y ||
      [$inst getOrient] ne $expected_orient || [$inst getPlacementStatus] ne "LOCKED"} {
    error "B8 smoke anchor mismatch: $name"
  }
  puts "WBQ_B8_SMOKE_ANCHOR name={$name} origin_dbu={$actual_x $actual_y} orient={[$inst getOrient]} status={[$inst getPlacementStatus]}"
}

set offenders {
  u_b2_implementation/u_quad_local_adapter/wire440455
  u_b2_implementation/u_quad_local_adapter/wire440867
  u_b2_implementation/u_quad_local_adapter/wire440876
  u_b2_implementation/u_quad_local_adapter/wire441097
  u_b2_implementation/u_quad_local_adapter/wire441921
  u_b2_implementation/u_quad_local_adapter/wire441940
  u_b2_implementation/u_quad_local_adapter/wire441994
}
foreach name $offenders {
  set inst [$block findInst $name]
  if {$inst eq "NULL" || [$inst getPlacementStatus] ne "PLACED"} {
    error "missing B8 smoke offender: $name"
  }
  puts "WBQ_B8_SMOKE_OFFENDER name={$name}"
}
write_db $::env(WBQ_B8_SMOKE_ODB)
puts "WBQ_B8_SMOKE_INPUT_REOPEN_AND_CHECKPOINT PASS anchors=2 offenders=7"
