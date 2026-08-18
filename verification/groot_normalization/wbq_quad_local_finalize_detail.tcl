foreach name {
  WBQ_PLATFORM_ROOT
  WBQ_QUAD_PRE_INCREMENTAL_ODB
  WBQ_QUAD_FLOORPLAN_SDC
  WBQ_QUAD_PLACE_ODB
  WBQ_QUAD_PLACE_SDC
} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}

set platform_root $::env(WBQ_PLATFORM_ROOT)
read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $::env(WBQ_QUAD_PRE_INCREMENTAL_ODB)
read_sdc $::env(WBQ_QUAD_FLOORPLAN_SDC)
source $platform_root/setRC.tcl

set block [ord::get_db_block]
array set group_by_quad {}
array set region_box_by_quad {}
array set grouped {}
foreach region [$block getRegions] {
  if {![regexp {wbq_quad_fence_([0-3])} [$region getName] -> quad]} {
    continue
  }
  set region_box_by_quad($quad) [lindex [$region getBoundaries] 0]
  foreach group [$region getGroups] {
    set group_by_quad($quad) $group
    foreach inst [$group getInsts] {
      set grouped([$inst getName]) 1
    }
  }
}

# A 10.12 um buf_16 cannot fit in the 10.0 um strip between the right-hand
# fence and core boundary.  The first detailed pass moves the two affected
# adapter buffers just inside Q1 while leaving them ungrouped.  Attach any
# ungrouped adapter buffer whose center is inside exactly one fence (falling
# back to a unique bbox intersection) before the incremental retry.
set boundary_assigned 0
foreach inst [$block getInsts] {
  set name [$inst getName]
  if {[info exists grouped($name)]} {
    continue
  }
  regsub -all {\\} $name {} normalized_name
  if {![string match "*u_quad_local_adapter/*" $normalized_name] ||
      ![regexp -nocase {__buf_[0-9]+$} [[$inst getMaster] getName]]} {
    continue
  }
  set bbox [$inst getBBox]
  set cx [expr {([$bbox xMin] + [$bbox xMax]) / 2}]
  set cy [expr {([$bbox yMin] + [$bbox yMax]) / 2}]
  set center_owner -1
  set intersections {}
  for {set quad 0} {$quad < 4} {incr quad} {
    set box $region_box_by_quad($quad)
    if {$cx >= [$box xMin] && $cx <= [$box xMax] &&
        $cy >= [$box yMin] && $cy <= [$box yMax]} {
      set center_owner $quad
    }
    if {[$bbox xMax] > [$box xMin] && [$bbox xMin] < [$box xMax] &&
        [$bbox yMax] > [$box yMin] && [$bbox yMin] < [$box yMax]} {
      lappend intersections $quad
    }
  }
  set owner $center_owner
  if {$owner < 0 && [llength $intersections] == 1} {
    set owner [lindex $intersections 0]
  }
  if {$owner >= 0} {
    $group_by_quad($owner) addInst $inst
    incr boundary_assigned
    puts "WBQ_QUAD_BOUNDARY_OWNERSHIP name=$name quad=$owner"
  }
}
puts "WBQ_QUAD_BOUNDARY_OWNERSHIP_TOTAL total=$boundary_assigned"
if {$boundary_assigned > 16} {
  error "unexpectedly large boundary adapter recovery set: $boundary_assigned"
}

set_placement_padding -global -left 0 -right 0
detailed_placement -incremental \
  -max_displacement {1000 1000} \
  -site_search_window 100 -row_search_window 20 -drc_penalty 20
puts "WBQ_QUAD_BOUNDARY_INCREMENTAL_DONE"
optimize_mirroring
write_db "$::env(WBQ_QUAD_PLACE_ODB).finalize_candidate.odb"
check_placement -verbose

write_db $::env(WBQ_QUAD_PLACE_ODB)
write_sdc -no_timestamp $::env(WBQ_QUAD_PLACE_SDC)
puts "WBQ_QUAD_RESPREAD_DETAIL PASS odb=$::env(WBQ_QUAD_PLACE_ODB)"
