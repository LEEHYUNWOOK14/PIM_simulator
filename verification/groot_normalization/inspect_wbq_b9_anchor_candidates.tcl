if {![info exists ::env(WBQ_B2_PLACE_ODB)] || $::env(WBQ_B2_PLACE_ODB) eq ""} {
  error "missing WBQ_B2_PLACE_ODB"
}
read_db $::env(WBQ_B2_PLACE_ODB)
set block [ord::get_db_block]
if {[$block getName] ne "logic_die_normalization_hbm_quad_local_b2_top"} {
  error "unexpected B9 anchor source top [$block getName]"
}
set candidates {
  u_b2_implementation/u_quad_local_adapter/wire440455
  u_b2_implementation/u_quad_local_adapter/wire440867
  u_b2_implementation/u_quad_local_adapter/wire440876
  u_b2_implementation/u_quad_local_adapter/wire441097
  u_b2_implementation/u_quad_local_adapter/wire441921
  u_b2_implementation/u_quad_local_adapter/wire441940
  u_b2_implementation/u_quad_local_adapter/wire441994
}
foreach name $candidates {
  set inst [$block findInst $name]
  if {$inst eq "NULL"} { error "B9 candidate is missing: $name" }
  lassign [$inst getOrigin] x y
  set bbox [$inst getBBox]
  puts "WBQ_B9_B2_ANCHOR_CANDIDATE name={$name} origin_dbu={$x $y} orient={[$inst getOrient]} status={[$inst getPlacementStatus]} bbox_dbu={[$bbox xMin] [$bbox yMin] [$bbox xMax] [$bbox yMax]}"
}
set violations [string trim [check_placement -verbose]]
puts "WBQ_B9_B2_SOURCE_LEGALITY violations={$violations}"
if {$violations ne ""} { error "B2 source placement is not legal" }
puts "WBQ_B9_B2_ANCHOR_CANDIDATES PASS count=[llength $candidates]"
