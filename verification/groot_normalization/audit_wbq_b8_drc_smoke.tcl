foreach name {WBQ_B8_SMOKE_ODB WBQ_B2_PLACE_SDC} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}
read_db $::env(WBQ_B8_SMOKE_ODB)
read_sdc $::env(WBQ_B2_PLACE_SDC)
set block [ord::get_db_block]
if {[$block getName] ne "logic_die_normalization_hbm_quad_local_b2_top"} {
  error "unexpected B8 smoke audit top [$block getName]"
}
if {[llength [$block getRegions]] != 4} { error "B8 smoke audit expected four fences" }
set anchors {
  {u_b2_implementation/u_pcu/u_quad_datapath/load_slew427175 6347540 2535040 MX}
  {u_b2_implementation/u_quad_local_adapter/wire440835 4686940 1468800 R180}
}
foreach spec $anchors {
  lassign $spec name x y orient
  set inst [$block findInst $name]
  if {$inst eq "NULL"} { error "B8 smoke audit missing anchor $name" }
  lassign [$inst getOrigin] actual_x actual_y
  if {$actual_x != $x || $actual_y != $y || [$inst getOrient] ne $orient ||
      [$inst getPlacementStatus] ne "LOCKED"} { error "B8 smoke audit anchor mismatch $name" }
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
  if {[$block findInst $name] eq "NULL"} { error "B8 smoke audit missing offender $name" }
}
puts "WBQ_B8_SMOKE_INDEPENDENT_REOPEN PASS anchors=2 offenders=7 fences=4"
