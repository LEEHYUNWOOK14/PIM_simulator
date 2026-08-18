# Build four exclusive placement fences from the mapped hierarchy.  The fence
# size is derived from the largest quad-local cell area at 38.5% raw utilization,
# leaving the cross-shaped remainder for the central packet/scalar/control path.
set block [ord::get_db_block]
set dbu [$block getDbUnitsPerMicron]
set core [$block getCoreArea]
set target_util 0.385
set edge_guard [expr {10.0 * $dbu}]

array set quad_area {0 0.0 1 0.0 2 0.0 3 0.0}
array set quad_count {0 0 1 0 2 0 3 0}
array set quad_insts {0 {} 1 {} 2 {} 3 {}}
set total_area 0.0

foreach inst [$block getInsts] {
  set master [$inst getMaster]
  set area [expr {double([$master getWidth]) * double([$master getHeight])}]
  set total_area [expr {$total_area + $area}]
  regsub -all {\\} [$inst getName] {} name
  set quad -1
  if {[regexp {g_quad_reset\[([0-3])\]} $name -> matched]} {
    set quad $matched
  } elseif {[regexp {g_quad\[([0-3])\]} $name -> matched]} {
    set quad $matched
  }
  if {$quad >= 0} {
    lappend quad_insts($quad) $inst
    incr quad_count($quad)
    set quad_area($quad) [expr {$quad_area($quad) + $area}]
  }
}

set max_quad_area 0.0
for {set quad 0} {$quad < 4} {incr quad} {
  if {$quad_count($quad) == 0} {
    utl::error ODB 9200 "quad $quad has no hierarchy-matched cells"
  }
  set max_quad_area [expr {max($max_quad_area, $quad_area($quad))}]
}

set side [expr {ceil(sqrt($max_quad_area / $target_util))}]
set available_w [expr {[$core xMax] - [$core xMin] - 2.0 * $edge_guard}]
set available_h [expr {[$core yMax] - [$core yMin] - 2.0 * $edge_guard}]
if {2.0 * $side >= $available_w || 2.0 * $side >= $available_h} {
  utl::error ODB 9201 "four quad fences do not fit: side_dbu=$side available=${available_w}x${available_h}"
}

for {set quad 0} {$quad < 4} {incr quad} {
  set column [expr {$quad % 2}]
  set row [expr {$quad / 2}]
  if {$column == 0} {
    set x0 [expr {round([$core xMin] + $edge_guard)}]
    set x1 [expr {round($x0 + $side)}]
  } else {
    set x1 [expr {round([$core xMax] - $edge_guard)}]
    set x0 [expr {round($x1 - $side)}]
  }
  if {$row == 0} {
    set y0 [expr {round([$core yMin] + $edge_guard)}]
    set y1 [expr {round($y0 + $side)}]
  } else {
    set y1 [expr {round([$core yMax] - $edge_guard)}]
    set y0 [expr {round($y1 - $side)}]
  }
  set region [odb::dbRegion_create $block "wbq_quad_fence_$quad"]
  odb::dbBox_create $region $x0 $y0 $x1 $y1
  $region setRegionType EXCLUSIVE
  set group [odb::dbGroup_create $region "wbq_quad_group_$quad"]
  $group setType PHYSICAL_CLUSTER
  foreach inst $quad_insts($quad) {
    $group addInst $inst
  }
  puts [format "WBQ_QUAD_FENCE quad=%d cells=%d cell_area_um2=%.3f bbox_um=%.3f,%.3f,%.3f,%.3f raw_util=%.6f" \
    $quad $quad_count($quad) [expr {$quad_area($quad)/($dbu*$dbu)}] \
    [expr {$x0/double($dbu)}] [expr {$y0/double($dbu)}] \
    [expr {$x1/double($dbu)}] [expr {$y1/double($dbu)}] \
    [expr {$quad_area($quad)/($side*$side)}]]
}
puts [format "WBQ_QUAD_FENCE_CREATE PASS total_cell_area_um2=%.3f side_um=%.3f target_util=%.3f" \
  [expr {$total_area/($dbu*$dbu)}] [expr {$side/double($dbu)}] $target_util]
