foreach name {WBQ_PLATFORM_ROOT WBQ_B2_PLACE_ODB WBQ_B2_PLACE_SDC WBQ_B7_SMOKE_ODB} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}
set platform_root $::env(WBQ_PLATFORM_ROOT)
read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $::env(WBQ_B2_PLACE_ODB)
read_sdc $::env(WBQ_B2_PLACE_SDC)
source $platform_root/setRC.tcl
set block [ord::get_db_block]
if {[$block getName] ne "logic_die_normalization_hbm_quad_local_b2_top"} {
  error "unexpected B7 smoke top [$block getName]"
}
set anchor_specs {
  {u_b2_implementation/u_pcu/u_quad_datapath/load_slew427175 6347540 2535040 MX}
  {u_b2_implementation/u_quad_local_adapter/wire440835 4686940 1468800 R180}
}
foreach spec $anchor_specs {
  lassign $spec name x y orient
  set inst [$block findInst $name]
  if {$inst eq "NULL"} { error "B7 smoke anchor missing: $name" }
  lassign [$inst getOrigin] actual_x actual_y
  if {$actual_x != $x || $actual_y != $y || [$inst getOrient] ne $orient} {
    error "B7 smoke anchor mismatch: $name"
  }
  $inst setPlacementStatus LOCKED
  puts "WBQ_B7_SMOKE_ANCHOR name={$name} origin_dbu={$x $y} orient={$orient} status={[$inst getPlacementStatus]}"
}
write_db $::env(WBQ_B7_SMOKE_ODB)
puts "WBQ_B7_SMOKE_INPUT_REOPEN_AND_CHECKPOINT PASS odb=$::env(WBQ_B7_SMOKE_ODB)"
