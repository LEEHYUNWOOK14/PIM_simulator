set report_root /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/reports/groot_normalization/physical_feasibility

read_db $report_root/logic_die_normalization_hbm_top_v5_bank_regions.odb

set block [ord::get_db_block]
set total_region_area 0.0
foreach region [$block getRegions] {
  set region_area 0.0
  set boundaries [$region getBoundaries]
  foreach boundary $boundaries {
    set width [expr {([$boundary xMax] - [$boundary xMin]) / 1000.0}]
    set height [expr {([$boundary yMax] - [$boundary yMin]) / 1000.0}]
    set region_area [expr {$region_area + $width * $height}]
  }
  set total_region_area [expr {$total_region_area + $region_area}]
  foreach group [$region getGroups] {
    set inst_count 0
    set inst_area 0.0
    foreach inst [$group getInsts] {
      incr inst_count
      set master [$inst getMaster]
      set inst_area [expr {$inst_area + ([$master getWidth] / 1000.0) * ([$master getHeight] / 1000.0)}]
    }
    set first_boundary [lindex $boundaries 0]
    puts [format "REGION %s TYPE %s BOUNDARIES %d BBOX_UM %.3f %.3f %.3f %.3f AREA_UM2 %.3f GROUP %s INSTANCES %d INST_AREA_UM2 %.3f RAW_UTIL %.6f" \
      [$region getName] [$region getRegionType] [llength $boundaries] \
      [expr {[$first_boundary xMin] / 1000.0}] [expr {[$first_boundary yMin] / 1000.0}] \
      [expr {[$first_boundary xMax] / 1000.0}] [expr {[$first_boundary yMax] / 1000.0}] \
      $region_area [$group getName] $inst_count $inst_area [expr {$inst_area / $region_area}]]
  }
}
puts [format "TOTAL_REGION_AREA_UM2 %.3f" $total_region_area]

array set status_count {}
array set status_area {}
foreach inst [$block getInsts] {
  set status [$inst getPlacementStatus]
  if {![info exists status_count($status)]} {
    set status_count($status) 0
    set status_area($status) 0.0
  }
  incr status_count($status)
  set master [$inst getMaster]
  set status_area($status) [expr {$status_area($status) + ([$master getWidth] / 1000.0) * ([$master getHeight] / 1000.0)}]
}
foreach status [lsort [array names status_count]] {
  puts [format "PLACEMENT_STATUS %s INSTANCES %d AREA_UM2 %.3f" \
    $status $status_count($status) $status_area($status)]
}

set blockage_count 0
set blockage_area 0.0
foreach blockage [$block getBlockages] {
  incr blockage_count
  set box [$blockage getBBox]
  set blockage_area [expr {$blockage_area + \
    (($box xMax) - ($box xMin)) / 1000.0 * (($box yMax) - ($box yMin)) / 1000.0}]
}
puts [format "PLACEMENT_BLOCKAGES %d RECTANGLE_AREA_UM2 %.3f" $blockage_count $blockage_area]

set row_count 0
set row_area 0.0
foreach row [$block getRows] {
  incr row_count
  set box [$row getBBox]
  set row_area [expr {$row_area + \
    (($box xMax) - ($box xMin)) / 1000.0 * (($box yMax) - ($box yMin)) / 1000.0}]
}
puts [format "PLACEMENT_ROWS %d RECTANGLE_AREA_UM2 %.3f" $row_count $row_area]

puts BANK_REGION_AUDIT_PASS
