foreach name {WBQ_QUAD_PLACE_ODB WBQ_QUAD_PLACE_SDC} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "$name is required"
  }
}
read_db $::env(WBQ_QUAD_PLACE_ODB)
read_sdc $::env(WBQ_QUAD_PLACE_SDC)
set block [ord::get_db_block]
set regions [$block getRegions]
if {[llength $regions] != 4} { error "expected four quad fences" }
set outside 0
set grouped 0
foreach region $regions {
  if {[$region getRegionType] ne "EXCLUSIVE"} {
    error "non-exclusive region [$region getName]"
  }
  set box [lindex [$region getBoundaries] 0]
  foreach group [$region getGroups] {
    foreach inst [$group getInsts] {
      incr grouped
      set bbox [$inst getBBox]
      if {[$bbox xMin] < [$box xMin] || [$bbox yMin] < [$box yMin] ||
          [$bbox xMax] > [$box xMax] || [$bbox yMax] > [$box yMax]} {
        incr outside
      }
    }
  }
}
set unplaced 0
foreach inst [$block getInsts] {
  if {![$inst isPlaced]} { incr unplaced }
}
puts "WBQ_QUAD_PLACE_FENCES regions=[llength $regions] grouped=$grouped outside=$outside unplaced=$unplaced"
if {$grouped == 0 || $outside != 0 || $unplaced != 0} {
  error "quad-local placement fence audit failed"
}
set placement_violations [string trim [check_placement -verbose]]
puts "WBQ_QUAD_PLACE_LEGALITY violations={$placement_violations}"
if {$placement_violations ne ""} {
  error "quad-local detailed placement is not legal: $placement_violations"
}
puts "WBQ_QUAD_LOCAL_PLACEMENT_AUDIT PASS"
