foreach name {
  WBQ_PLATFORM_ROOT
  WBQ_QUAD_RESIZED_ODB
  WBQ_QUAD_FLOORPLAN_SDC
  WBQ_QUAD_RESPREAD_ODB
  WBQ_QUAD_PLACE_ODB
  WBQ_QUAD_PLACE_SDC
} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}

set platform_root $::env(WBQ_PLATFORM_ROOT)
read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
set reuse_respread [file exists $::env(WBQ_QUAD_RESPREAD_ODB)]
if {$reuse_respread} {
  read_db $::env(WBQ_QUAD_RESPREAD_ODB)
  puts "WBQ_QUAD_RESPREAD_REUSE_CHECKPOINT odb=$::env(WBQ_QUAD_RESPREAD_ODB)"
} else {
  read_db $::env(WBQ_QUAD_RESIZED_ODB)
}
read_sdc $::env(WBQ_QUAD_FLOORPLAN_SDC)
source $platform_root/setRC.tcl

if {!$reuse_respread} {
# Resizer-created buffers do not inherit the dbGroup of their hierarchical
# driver/sinks.  Recover ownership from the retained g_quad hierarchy before
# GPL; leave buffers without an unambiguous quad path in the central scope.
set block [ord::get_db_block]
array set group_by_quad {}
array set region_box_by_quad {}
array set grouped {}
array set assigned {0 0 1 0 2 0 3 0}
array set assigned_by_location {0 0 1 0 2 0 3 0}
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
for {set quad 0} {$quad < 4} {incr quad} {
  if {![info exists group_by_quad($quad)]} {
    error "missing physical group for quad $quad"
  }
}
set unmatched_buffers 0
foreach inst [$block getInsts] {
  set name [$inst getName]
  if {[info exists grouped($name)]} {
    continue
  }
  set master_name [[$inst getMaster] getName]
  if {![regexp -nocase {__buf_[0-9]+$} $master_name]} {
    continue
  }
  regsub -all {\\} $name {} normalized_name
  set owner -1
  if {[regexp {g_quad_reset\[([0-3])\]} $normalized_name -> matched]} {
    set owner $matched
  } elseif {[regexp {g_quad\[([0-3])\]} $normalized_name -> matched]} {
    set owner $matched
  }
  # The interface adapter and top-level cmd_write_data repair chains lose
  # their generated-quad hierarchy during synthesis.  Their resized
  # coordinates retain the physical slice association.  Infer ownership only
  # when such a buffer is already inside one of the four fences; central
  # adapter/control buffers outside the fences remain deliberately ungrouped.
  # B2 adds one transparent implementation wrapper around the frozen B
  # hierarchy.  Treat direct children of that wrapper like the bare top-level
  # repair chains in B, and accept the adapter at either hierarchy depth.
  set adapter_like [string match "*u_quad_local_adapter/*" $normalized_name]
  set top_level_like [expr {
    [string first "/" $normalized_name] < 0 ||
    [regexp {^u_b2_implementation/[^/]+$} $normalized_name]
  }]
  if {$owner < 0 && ($adapter_like || $top_level_like)} {
    set bbox [$inst getBBox]
    set cx [expr {([$bbox xMin] + [$bbox xMax]) / 2}]
    set cy [expr {([$bbox yMin] + [$bbox yMax]) / 2}]
    for {set quad 0} {$quad < 4} {incr quad} {
      set box $region_box_by_quad($quad)
      if {$cx >= [$box xMin] && $cx <= [$box xMax] &&
          $cy >= [$box yMin] && $cy <= [$box yMax]} {
        set owner $quad
        incr assigned_by_location($quad)
        break
      }
    }
  }
  if {$owner < 0} {
    incr unmatched_buffers
    continue
  }
  $group_by_quad($owner) addInst $inst
  incr assigned($owner)
}
set assigned_total [expr {$assigned(0) + $assigned(1) + $assigned(2) + $assigned(3)}]
set location_total [expr {$assigned_by_location(0) + $assigned_by_location(1) + $assigned_by_location(2) + $assigned_by_location(3)}]
set classified_total [expr {$assigned_total + $unmatched_buffers}]
puts "WBQ_QUAD_RESPREAD_OWNERSHIP q0=$assigned(0) q1=$assigned(1) q2=$assigned(2) q3=$assigned(3) total=$assigned_total inferred_by_location=$location_total unmatched_buffers=$unmatched_buffers"
if {$assigned_total < 55000 || $classified_total < 62000} {
  error "resized buffer ownership classification incomplete: assigned=$assigned_total unmatched=$unmatched_buffers classified=$classified_total"
}

# repair_design inserts tens of thousands of buffers at locally clustered
# coordinates.  With four exclusive fences, detailed placement's sequential
# diamond fallback is both pathological and unable to spread enough of those
# new cells.  Re-run GPL from the saved resized netlist/ODB using the same
# force-center initialization that converged in the original final GPL.  This
# retains synthesis, floorplan, IO placement, fences, sizing, and buffering,
# while recomputing coordinates for the resized cell population.
# 0.49 is above the repaired design's measured 0.4802 density at 90% use of
# fence free area; it avoids the unstable minimum-feasible 0.44 setting.
puts "WBQ_QUAD_RESPREAD_START density=0.49 input=$::env(WBQ_QUAD_RESIZED_ODB)"
global_placement \
  -force_center_initial_place -density 0.49 \
  -pad_left 0 -pad_right 0 \
  -min_phi_coef 0.95 -max_phi_coef 1.05
puts "WBQ_QUAD_RESPREAD_GLOBAL_PLACEMENT PASS"
write_db $::env(WBQ_QUAD_RESPREAD_ODB)
puts "WBQ_QUAD_RESPREAD_CHECKPOINT odb=$::env(WBQ_QUAD_RESPREAD_ODB)"
}

# GPL can place a small number of otherwise central repair buffers inside an
# exclusive fence even though they have no synthesized g_quad name.  Preserve
# that connectivity-driven locality by attaching only buffers whose checkpoint
# center is already inside a fence.  The measured checkpoint has 128 such
# buffers; the other 3,688 central buffers remain outside all groups.
if {$reuse_respread} {
  set block [ord::get_db_block]
  array set late_group_by_quad {}
  array set late_region_box_by_quad {}
  array set late_grouped {}
  array set late_assigned {0 0 1 0 2 0 3 0}
  foreach region [$block getRegions] {
    if {![regexp {wbq_quad_fence_([0-3])} [$region getName] -> quad]} {
      continue
    }
    set late_region_box_by_quad($quad) [lindex [$region getBoundaries] 0]
    foreach group [$region getGroups] {
      set late_group_by_quad($quad) $group
      foreach inst [$group getInsts] {
        set late_grouped([$inst getName]) 1
      }
    }
  }
  foreach inst [$block getInsts] {
    set name [$inst getName]
    if {[info exists late_grouped($name)]} {
      continue
    }
    if {![regexp -nocase {__buf_[0-9]+$} [[$inst getMaster] getName]]} {
      continue
    }
    set bbox [$inst getBBox]
    set cx [expr {([$bbox xMin] + [$bbox xMax]) / 2}]
    set cy [expr {([$bbox yMin] + [$bbox yMax]) / 2}]
    for {set quad 0} {$quad < 4} {incr quad} {
      set box $late_region_box_by_quad($quad)
      if {$cx >= [$box xMin] && $cx <= [$box xMax] &&
          $cy >= [$box yMin] && $cy <= [$box yMax]} {
        $late_group_by_quad($quad) addInst $inst
        incr late_assigned($quad)
        break
      }
    }
  }
  set late_total [expr {$late_assigned(0) + $late_assigned(1) +
                        $late_assigned(2) + $late_assigned(3)}]
  puts "WBQ_QUAD_RESPREAD_LATE_OWNERSHIP q0=$late_assigned(0) q1=$late_assigned(1) q2=$late_assigned(2) q3=$late_assigned(3) total=$late_total"
  if {$late_total > 512} {
    error "unexpected checkpoint-local ungrouped buffer count: $late_total"
  }
  write_db "$::env(WBQ_QUAD_PLACE_ODB).ownership.odb"
}

# Rebuild the canonical ownership tables after either the fresh-respread or
# checkpoint-reuse branch.  The latter uses temporary late_* tables above.
set block [ord::get_db_block]
unset -nocomplain group_by_quad region_box_by_quad grouped
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

set_placement_padding -global -left 0 -right 0
detailed_placement -max_displacement {1000 1000} \
  -site_search_window 100 -row_search_window 20 -drc_penalty 20

# A wide adapter repair buffer can be moved just inside an exclusive fence by
# the first legalization pass while still being logically ungrouped.  Attach
# every such unambiguous adapter buffer before the incremental pass.  This is
# the same recovery previously performed by a separate finalize invocation,
# but keeping it here makes a failed ORFS detailed-place stage resumable in one
# continuation from the saved resized ODB.
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
    set grouped($name) 1
    incr boundary_assigned
    puts "WBQ_QUAD_BOUNDARY_OWNERSHIP name=$name quad=$owner"
  }
}
puts "WBQ_QUAD_BOUNDARY_OWNERSHIP_TOTAL total=$boundary_assigned"
write_db "$::env(WBQ_QUAD_PLACE_ODB).pre_incremental.odb"
puts "WBQ_QUAD_DETAIL_INCREMENTAL_RETRY_START"
detailed_placement -incremental \
  -max_displacement {1000 1000} \
  -site_search_window 100 -row_search_window 20 -drc_penalty 20
puts "WBQ_QUAD_DETAIL_INCREMENTAL_RETRY_DONE"
optimize_mirroring
check_placement -verbose

write_db $::env(WBQ_QUAD_PLACE_ODB)
write_sdc -no_timestamp $::env(WBQ_QUAD_PLACE_SDC)
puts "WBQ_QUAD_RESPREAD_DETAIL PASS odb=$::env(WBQ_QUAD_PLACE_ODB)"
