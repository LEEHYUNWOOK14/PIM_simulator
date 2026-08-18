if {![info exists ::env(WBQ_QUAD_RESPREAD_ODB)] ||
    $::env(WBQ_QUAD_RESPREAD_ODB) eq ""} {
  error "WBQ_QUAD_RESPREAD_ODB is required"
}

read_db $::env(WBQ_QUAD_RESPREAD_ODB)
set block [ord::get_db_block]

array set group_of {}
array set region_box_by_quad {}
foreach region [$block getRegions] {
  if {![regexp {wbq_quad_fence_([0-3])} [$region getName] -> quad]} {
    continue
  }
  set region_box_by_quad($quad) [lindex [$region getBoundaries] 0]
  foreach group [$region getGroups] {
    foreach inst [$group getInsts] {
      set group_of([$inst getName]) $quad
    }
  }
}

set targets {
  u_pcu/u_quad_datapath/wire428268
  u_quad_local_adapter/wire418281
  u_quad_local_adapter/wire418296
  u_quad_local_adapter/wire418359
  u_quad_local_adapter/wire440951
  u_quad_local_adapter/wire441044
  u_quad_local_adapter/wire441396
  u_quad_local_adapter/wire441453
  u_quad_local_adapter/wire441499
  u_quad_local_adapter/wire441654
  u_quad_local_adapter/wire442188
  u_quad_local_adapter/wire442254
  u_quad_local_adapter/wire442315
  u_quad_local_adapter/wire442355
  u_quad_local_adapter/wire442544
  u_quad_local_adapter/wire443021
  u_writeback_slice/wire425071
}

foreach name $targets {
  set inst [$block findInst $name]
  if {$inst eq "NULL"} {
    puts "WBQ_STUCK_CELL_MISSING name=$name"
    continue
  }
  set bbox [$inst getBBox]
  set cx [expr {([$bbox xMin] + [$bbox xMax]) / 2}]
  set cy [expr {([$bbox yMin] + [$bbox yMax]) / 2}]
  set fence outside
  for {set quad 0} {$quad < 4} {incr quad} {
    set box $region_box_by_quad($quad)
    if {$cx >= [$box xMin] && $cx <= [$box xMax] &&
        $cy >= [$box yMin] && $cy <= [$box yMax]} {
      set fence $quad
      break
    }
  }
  set group ungrouped
  if {[info exists group_of($name)]} {
    set group $group_of($name)
  }
  set nets {}
  foreach iterm [$inst getITerms] {
    set net [$iterm getNet]
    if {$net ne "NULL"} {
      lappend nets [$net getName]
    }
  }
  puts "WBQ_STUCK_CELL name=$name master=[[$inst getMaster] getName] group=$group fence=$fence center={$cx $cy} size={[expr {[$bbox xMax] - [$bbox xMin]}] [expr {[$bbox yMax] - [$bbox yMin]}]} nets={$nets}"
}
