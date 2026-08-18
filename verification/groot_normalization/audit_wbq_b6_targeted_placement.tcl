foreach name {WBQ_B6_PLACE_ODB WBQ_B6_PLACE_SDC} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}
read_db $::env(WBQ_B6_PLACE_ODB)
read_sdc $::env(WBQ_B6_PLACE_SDC)
set block [ord::get_db_block]
if {[$block getName] ne "logic_die_normalization_hbm_quad_local_b2_top"} {
  error "unexpected B6 placement top [$block getName]"
}

set anchor_specs {
  {u_b2_implementation/u_pcu/u_quad_datapath/load_slew427175 6347540 2535040 MX}
  {u_b2_implementation/u_quad_local_adapter/wire440835 4686940 1468800 R180}
}
set anchors_verified 0
foreach spec $anchor_specs {
  lassign $spec name expected_x expected_y expected_orient
  set inst [$block findInst $name]
  if {$inst eq "NULL"} { error "B6 reopen audit anchor missing: $name" }
  lassign [$inst getOrigin] actual_x actual_y
  set actual_orient [$inst getOrient]
  set actual_status [$inst getPlacementStatus]
  puts "WBQ_B6_TARGETED_AUDIT_ANCHOR name={$name} origin_dbu={$actual_x $actual_y} orient={$actual_orient} status={$actual_status}"
  if {$actual_x != $expected_x || $actual_y != $expected_y ||
      $actual_orient ne $expected_orient || $actual_status ne "LOCKED"} {
    error "B6 reopen audit anchor mismatch: $name"
  }
  incr anchors_verified
}

set regions [$block getRegions]
if {[llength $regions] != 4} { error "expected four B6 quad fences" }
set grouped 0
set outside 0
foreach region $regions {
  if {[$region getRegionType] ne "EXCLUSIVE"} {
    error "B6 non-exclusive region [$region getName]"
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
set violations [string trim [check_placement -verbose]]
puts "WBQ_B6_TARGETED_AUDIT_FENCES regions=[llength $regions] grouped=$grouped outside=$outside unplaced=$unplaced"
puts "WBQ_B6_TARGETED_AUDIT_LEGALITY violations={$violations}"
puts "WBQ_B6_TARGETED_AUDIT_ANCHORS_VERIFIED $anchors_verified"
if {$anchors_verified != 2 || $grouped == 0 || $outside != 0 || $unplaced != 0 || $violations ne ""} {
  error "B6 targeted placement reopen audit failed"
}
puts "WBQ_B6_TARGETED_PLACEMENT_REOPEN_AUDIT PASS"
