if {![info exists ::env(WBQ_QUAD_FENCE_ODB)]} {
  error "WBQ_QUAD_FENCE_ODB is required"
}
set density 0.39
if {[info exists ::env(WBQ_QUAD_FENCE_DENSITY)]} {
  set density $::env(WBQ_QUAD_FENCE_DENSITY)
}
read_db $::env(WBQ_QUAD_FENCE_ODB)
set block [ord::get_db_block]
set dbu [$block getDbUnitsPerMicron]

proc overlap_area {left right} {
  set x0 [expr {max([$left xMin], [$right xMin])}]
  set y0 [expr {max([$left yMin], [$right yMin])}]
  set x1 [expr {min([$left xMax], [$right xMax])}]
  set y1 [expr {min([$left yMax], [$right yMax])}]
  if {$x1 <= $x0 || $y1 <= $y0} { return 0.0 }
  return [expr {double($x1-$x0) * double($y1-$y0)}]
}

set regions [$block getRegions]
if {[llength $regions] != 4} {
  error "expected exactly four regions, got [llength $regions]"
}
set total_row_area 0.0
foreach row [$block getRows] {
  set box [$row getBBox]
  set total_row_area [expr {$total_row_area +
    double([$box xMax]-[$box xMin]) * double([$box yMax]-[$box yMin])}]
}
set total_fence_row_area 0.0
set total_group_area 0.0
set pass 1
foreach region $regions {
  if {[$region getRegionType] ne "EXCLUSIVE"} {
    error "region [$region getName] is not EXCLUSIVE"
  }
  set boundaries [$region getBoundaries]
  if {[llength $boundaries] != 1} {
    error "region [$region getName] must have one rectangle"
  }
  set boundary [lindex $boundaries 0]
  set row_area 0.0
  foreach row [$block getRows] {
    set row_area [expr {$row_area + [overlap_area [$row getBBox] $boundary]}]
  }
  set groups [$region getGroups]
  if {[llength $groups] != 1} {
    error "region [$region getName] must have one group"
  }
  set group [lindex $groups 0]
  set inst_count 0
  set cell_area 0.0
  foreach inst [$group getInsts] {
    incr inst_count
    set master [$inst getMaster]
    set cell_area [expr {$cell_area + double([$master getWidth]) * double([$master getHeight])}]
  }
  set capacity [expr {$row_area * $density}]
  set utilization [expr {$cell_area / $row_area}]
  set margin [expr {$capacity - $cell_area}]
  if {$inst_count == 0 || $margin <= 0.0} { set pass 0 }
  puts [format "WBQ_QUAD_CAPACITY region=%s cells=%d row_area_um2=%.3f cell_area_um2=%.3f raw_util=%.6f density=%.3f margin_um2=%.3f result=%s" \
    [$region getName] $inst_count [expr {$row_area/($dbu*$dbu)}] \
    [expr {$cell_area/($dbu*$dbu)}] $utilization $density \
    [expr {$margin/($dbu*$dbu)}] [expr {$margin > 0.0 ? "PASS" : "FAIL"}]]
  set total_fence_row_area [expr {$total_fence_row_area + $row_area}]
  set total_group_area [expr {$total_group_area + $cell_area}]
}

set total_cell_area 0.0
foreach inst [$block getInsts] {
  set master [$inst getMaster]
  set total_cell_area [expr {$total_cell_area + double([$master getWidth]) * double([$master getHeight])}]
}
set central_cell_area [expr {$total_cell_area - $total_group_area}]
set central_row_area [expr {$total_row_area - $total_fence_row_area}]
set central_margin [expr {$central_row_area * $density - $central_cell_area}]
if {$central_margin <= 0.0} { set pass 0 }
puts [format "WBQ_CENTRAL_CAPACITY row_area_um2=%.3f cell_area_um2=%.3f raw_util=%.6f density=%.3f margin_um2=%.3f result=%s" \
  [expr {$central_row_area/($dbu*$dbu)}] [expr {$central_cell_area/($dbu*$dbu)}] \
  [expr {$central_cell_area/$central_row_area}] $density \
  [expr {$central_margin/($dbu*$dbu)}] [expr {$central_margin > 0.0 ? "PASS" : "FAIL"}]]
if {!$pass} { error "WBQ_QUAD_FENCE_CAPACITY FAIL" }
puts "WBQ_QUAD_FENCE_CAPACITY PASS regions=4 density=$density"
