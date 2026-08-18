foreach name {WBQ_B2_PLACE_ODB} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}
read_db $::env(WBQ_B2_PLACE_ODB)
set block [ord::get_db_block]
set targets {
  u_b2_implementation/u_pcu/u_quad_datapath/load_slew427175
  TAP_TAPCELL_ROW_916_299625
  u_b2_implementation/u_quad_local_adapter/wire440835
  TAP_TAPCELL_ROW_573_187675
}
foreach name $targets {
  set inst [$block findInst $name]
  if {$inst eq "NULL"} { error "missing target $name" }
  set bbox [$inst getBBox]
  set master [$inst getMaster]
  puts "WBQ_B6_TARGET name={$name} master={[$master getName]} status={[$inst getPlacementStatus]} orient={[$inst getOrient]} origin={[$inst getOrigin]} bbox={[ord::dbu_to_microns [$bbox xMin]] [ord::dbu_to_microns [$bbox yMin]] [ord::dbu_to_microns [$bbox xMax]] [ord::dbu_to_microns [$bbox yMax]]}"
}
foreach group [$block getGroups] {
  set region [$group getRegion]
  if {$region eq "NULL"} { continue }
  set boxes {}
  foreach boundary [$region getBoundaries] {
    lappend boxes [list [ord::dbu_to_microns [$boundary xMin]] [ord::dbu_to_microns [$boundary yMin]] [ord::dbu_to_microns [$boundary xMax]] [ord::dbu_to_microns [$boundary yMax]]]
  }
  puts "WBQ_B6_GROUP name={[$group getName]} boxes={$boxes}"
}
puts "WBQ_B6_TARGET_INSPECTION PASS"
