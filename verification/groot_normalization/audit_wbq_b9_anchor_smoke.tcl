foreach name {WBQ_B9_SMOKE_ODB WBQ_B2_PLACE_SDC} {
  if {![info exists ::env($name)] || $::env($name) eq ""} { error "missing required environment variable $name" }
}
read_db $::env(WBQ_B9_SMOKE_ODB)
read_sdc $::env(WBQ_B2_PLACE_SDC)
set block [ord::get_db_block]
set anchor_specs {
  {u_b2_implementation/u_pcu/u_quad_datapath/load_slew427175 6347540 2535040 MX}
  {u_b2_implementation/u_quad_local_adapter/wire440835 4686940 1468800 R180}
  {u_b2_implementation/u_quad_local_adapter/wire440455 7308480 4417280 MY}
  {u_b2_implementation/u_quad_local_adapter/wire440867 4287200 1392640 MY}
  {u_b2_implementation/u_quad_local_adapter/wire440876 4285360 1479680 R180}
  {u_b2_implementation/u_quad_local_adapter/wire441097 4723740 6636800 R0}
  {u_b2_implementation/u_quad_local_adapter/wire441921 4376900 2186880 MX}
  {u_b2_implementation/u_quad_local_adapter/wire441940 4345620 2208640 R0}
  {u_b2_implementation/u_quad_local_adapter/wire441994 4293640 2224960 MX}
}
foreach spec $anchor_specs {
  lassign $spec name x y orient
  set inst [$block findInst $name]
  if {$inst eq "NULL"} { error "B9 smoke audit missing anchor $name" }
  lassign [$inst getOrigin] actual_x actual_y
  if {$actual_x != $x || $actual_y != $y || [$inst getOrient] ne $orient || [$inst getPlacementStatus] ne "LOCKED"} {
    error "B9 smoke audit anchor mismatch $name"
  }
}
if {[llength [$block getRegions]] != 4} { error "B9 smoke audit expected four fences" }
puts "WBQ_B9_SMOKE_INDEPENDENT_REOPEN PASS anchors=9 offenders=7 fences=4"
