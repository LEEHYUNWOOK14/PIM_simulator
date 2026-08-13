set report_root /mnt/c/Users/Admin/OneDrive/2026-summer/STOB_semiconductor_pim/STOB_PIM2/reports/groot_normalization/physical_feasibility
read_db $report_root/logic_die_normalization_hbm_top_v2_repaired_legal.odb

set block [ord::get_db_block]
array set count {}
array set sum_x {}
array set sum_y {}
array set min_x {}
array set min_y {}
array set max_x {}
array set max_y {}

foreach inst [$block getInsts] {
  set name [$inst getName]
  set clean_name [string map {"\\" ""} $name]
  if {![regexp {g_bank\[([0-9]+)\]} $clean_name -> bank]} {
    continue
  }
  set bbox [$inst getBBox]
  set x [expr {([$bbox xMin] + [$bbox xMax]) / 2.0}]
  set y [expr {([$bbox yMin] + [$bbox yMax]) / 2.0}]
  if {![info exists count($bank)]} {
    set count($bank) 0
    set sum_x($bank) 0.0
    set sum_y($bank) 0.0
    set min_x($bank) $x
    set min_y($bank) $y
    set max_x($bank) $x
    set max_y($bank) $y
  }
  incr count($bank)
  set sum_x($bank) [expr {$sum_x($bank) + $x}]
  set sum_y($bank) [expr {$sum_y($bank) + $y}]
  if {$x < $min_x($bank)} { set min_x($bank) $x }
  if {$y < $min_y($bank)} { set min_y($bank) $y }
  if {$x > $max_x($bank)} { set max_x($bank) $x }
  if {$y > $max_y($bank)} { set max_y($bank) $y }
}

foreach bank [lsort -integer [array names count]] {
  puts [format "BANK %d CELLS %d CENTROID_UM %.1f %.1f BBOX_UM %.1f %.1f %.1f %.1f" \
    $bank $count($bank) \
    [expr {$sum_x($bank) / $count($bank) / 1000.0}] \
    [expr {$sum_y($bank) / $count($bank) / 1000.0}] \
    [expr {$min_x($bank) / 1000.0}] [expr {$min_y($bank) / 1000.0}] \
    [expr {$max_x($bank) / 1000.0}] [expr {$max_y($bank) / 1000.0}]]
}
