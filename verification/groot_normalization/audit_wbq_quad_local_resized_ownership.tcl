if {![info exists ::env(WBQ_QUAD_RESIZED_ODB)] ||
    $::env(WBQ_QUAD_RESIZED_ODB) eq ""} {
  error "WBQ_QUAD_RESIZED_ODB is required"
}
read_db $::env(WBQ_QUAD_RESIZED_ODB)
set block [ord::get_db_block]

array set grouped {}
array set group_by_quad {}
array set region_box_by_quad {}
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

set total 0
set grouped_count 0
set ungrouped_count 0
set ungrouped_buffer_count 0
array set buffer_master_count {}
array set buffer_inside_count {0 0 1 0 2 0 3 0 outside 0}
array set buffer_name_owner_count {0 0 1 0 2 0 3 0 unmatched 0}
set buffer_owner_location_mismatch 0
set samples 0
set unmatched_samples 0
set adapter_samples 0
set bare_samples 0
array set adapter_buffer_location_count {0 0 1 0 2 0 3 0 outside 0}
array set bare_buffer_location_count {0 0 1 0 2 0 3 0 outside 0}
array set unmatched_inside_category_count {}
foreach inst [$block getInsts] {
  incr total
  set name [$inst getName]
  if {[info exists grouped($name)]} {
    incr grouped_count
    continue
  }
  incr ungrouped_count
  set master_name [[$inst getMaster] getName]
  if {![regexp -nocase {__buf_[0-9]+$} $master_name]} {
    continue
  }
  incr ungrouped_buffer_count
  if {![info exists buffer_master_count($master_name)]} {
    set buffer_master_count($master_name) 0
  }
  incr buffer_master_count($master_name)
  set bbox [$inst getBBox]
  set cx [expr {([$bbox xMin] + [$bbox xMax]) / 2}]
  set cy [expr {([$bbox yMin] + [$bbox yMax]) / 2}]
  set owner outside
  for {set quad 0} {$quad < 4} {incr quad} {
    set box $region_box_by_quad($quad)
    if {$cx >= [$box xMin] && $cx <= [$box xMax] &&
        $cy >= [$box yMin] && $cy <= [$box yMax]} {
      set owner $quad
      break
    }
  }
  incr buffer_inside_count($owner)
  regsub -all {\\} $name {} normalized_name
  set name_owner unmatched
  if {[regexp {g_quad_reset\[([0-3])\]} $normalized_name -> matched]} {
    set name_owner $matched
  } elseif {[regexp {g_quad\[([0-3])\]} $normalized_name -> matched]} {
    set name_owner $matched
  }
  incr buffer_name_owner_count($name_owner)
  if {$name_owner ne "unmatched" && $owner ne $name_owner} {
    incr buffer_owner_location_mismatch
  }
  if {$name_owner eq "unmatched" && $unmatched_samples < 64} {
    set connected_nets {}
    foreach iterm [$inst getITerms] {
      set net [$iterm getNet]
      if {$net ne "NULL"} {
        lappend connected_nets [$net getName]
      }
    }
    puts "WBQ_RESIZED_UNMATCHED_BUFFER_SAMPLE owner=$owner master=$master_name name=$name nets={$connected_nets}"
    incr unmatched_samples
  }
  if {$name_owner eq "unmatched" &&
      [string match "u_quad_local_adapter/*" $normalized_name]} {
    incr adapter_buffer_location_count($owner)
    if {$adapter_samples < 64} {
      set connected_nets {}
      foreach iterm [$inst getITerms] {
        set net [$iterm getNet]
        if {$net ne "NULL"} {
          lappend connected_nets [$net getName]
        }
      }
      puts "WBQ_RESIZED_ADAPTER_BUFFER_SAMPLE owner=$owner master=$master_name name=$name nets={$connected_nets}"
      incr adapter_samples
    }
  }
  if {$name_owner eq "unmatched" && [string first "/" $normalized_name] < 0} {
    incr bare_buffer_location_count($owner)
    if {$owner ne "outside" && $bare_samples < 64} {
      set connected_nets {}
      foreach iterm [$inst getITerms] {
        set net [$iterm getNet]
        if {$net ne "NULL"} {
          lappend connected_nets [$net getName]
        }
      }
      puts "WBQ_RESIZED_BARE_BUFFER_SAMPLE owner=$owner master=$master_name name=$name nets={$connected_nets}"
      incr bare_samples
    }
  }
  if {$name_owner eq "unmatched" && $owner ne "outside"} {
    if {[string match "u_quad_local_adapter/*" $normalized_name]} {
      set category adapter
    } elseif {[string first "/" $normalized_name] < 0} {
      set category bare
    } elseif {[string match "u_pcu/u_quad_datapath/u_scalar_array/*" $normalized_name]} {
      set category scalar_array
    } elseif {[string match "u_pcu/u_quad_datapath/u_packet_reducer/*" $normalized_name]} {
      set category packet_reducer
    } elseif {[string match "u_pcu/*" $normalized_name]} {
      set category pcu_other
    } elseif {[string match "u_writeback*" $normalized_name]} {
      set category writeback
    } else {
      set category other
    }
    if {![info exists unmatched_inside_category_count($category)]} {
      set unmatched_inside_category_count($category) 0
    }
    incr unmatched_inside_category_count($category)
  }
  if {$samples < 32} {
    puts "WBQ_RESIZED_UNGROUPED_BUFFER_SAMPLE owner=$owner master=$master_name name=$name"
    incr samples
  }
}

foreach master [lsort [array names buffer_master_count]] {
  puts "WBQ_RESIZED_UNGROUPED_BUFFER_MASTER master=$master count=$buffer_master_count($master)"
}
puts "WBQ_RESIZED_OWNERSHIP total=$total grouped=$grouped_count ungrouped=$ungrouped_count ungrouped_buffers=$ungrouped_buffer_count q0=$buffer_inside_count(0) q1=$buffer_inside_count(1) q2=$buffer_inside_count(2) q3=$buffer_inside_count(3) outside=$buffer_inside_count(outside)"
puts "WBQ_RESIZED_BUFFER_NAME_OWNERS q0=$buffer_name_owner_count(0) q1=$buffer_name_owner_count(1) q2=$buffer_name_owner_count(2) q3=$buffer_name_owner_count(3) unmatched=$buffer_name_owner_count(unmatched) owner_location_mismatch=$buffer_owner_location_mismatch"
puts "WBQ_RESIZED_ADAPTER_BUFFER_LOCATIONS q0=$adapter_buffer_location_count(0) q1=$adapter_buffer_location_count(1) q2=$adapter_buffer_location_count(2) q3=$adapter_buffer_location_count(3) outside=$adapter_buffer_location_count(outside)"
puts "WBQ_RESIZED_BARE_BUFFER_LOCATIONS q0=$bare_buffer_location_count(0) q1=$bare_buffer_location_count(1) q2=$bare_buffer_location_count(2) q3=$bare_buffer_location_count(3) outside=$bare_buffer_location_count(outside)"
foreach category [lsort [array names unmatched_inside_category_count]] {
  puts "WBQ_RESIZED_UNMATCHED_INSIDE_CATEGORY category=$category count=$unmatched_inside_category_count($category)"
}
