if {![info exists ::env(WBQ_B7_SMOKE_ODB)] || $::env(WBQ_B7_SMOKE_ODB) eq ""} {
  error "missing WBQ_B7_SMOKE_ODB"
}
read_db $::env(WBQ_B7_SMOKE_ODB)
set block [ord::get_db_block]
if {[$block getName] ne "logic_die_normalization_hbm_quad_local_b2_top"} {
  error "unexpected B7 smoke reopen top [$block getName]"
}
set anchor_specs {
  {u_b2_implementation/u_pcu/u_quad_datapath/load_slew427175 6347540 2535040 MX}
  {u_b2_implementation/u_quad_local_adapter/wire440835 4686940 1468800 R180}
}
set verified 0
foreach spec $anchor_specs {
  lassign $spec name x y orient
  set inst [$block findInst $name]
  if {$inst eq "NULL"} { error "B7 smoke reopen anchor missing: $name" }
  lassign [$inst getOrigin] actual_x actual_y
  set status [$inst getPlacementStatus]
  puts "WBQ_B7_SMOKE_REOPEN_ANCHOR name={$name} origin_dbu={$actual_x $actual_y} orient={[$inst getOrient]} status={$status}"
  if {$actual_x != $x || $actual_y != $y || [$inst getOrient] ne $orient || $status ne "LOCKED"} {
    error "B7 smoke reopen anchor mismatch: $name"
  }
  incr verified
}
if {$verified != 2} { error "B7 smoke did not verify both targets" }
puts "WBQ_B7_SMOKE_INDEPENDENT_REOPEN PASS anchors=$verified"
