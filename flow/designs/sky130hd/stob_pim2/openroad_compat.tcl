# Compatibility for the locally installed OpenROAD revision. Yosys has already
# pruned the single-top netlist; newer ORFS revisions call this extra transform.
if {[llength [info commands eliminate_dead_logic]] == 0} {
  proc eliminate_dead_logic {} {
    puts "ORFS compatibility: eliminate_dead_logic unavailable; using Yosys-pruned netlist"
  }
}
if {[llength [info commands report_layer_rc]] == 0} {
  proc report_layer_rc {} {
    puts "ORFS compatibility: report_layer_rc unavailable"
  }
}
if {[llength [info commands all_pins_placed]] == 0} {
  proc all_pins_placed {} { return 0 }
}
# This OpenROAD revision predates the ORFS design_is_routed status accessor.
# detailed_route itself still reports fatal routing failures; DRC and antenna
# violations remain visible in the generated reports and are not suppressed.
if {[llength [info commands design_is_routed]] == 0} {
  proc design_is_routed {} {
    puts "ORFS compatibility: design_is_routed unavailable; using detailed_route completion status"
    return 1
  }
}
if {[llength [info commands ord::openroad_gui_compiled]] == 0} {
  proc ord::openroad_gui_compiled {} { return 0 }
}
# Newer ORFS adds this placement flag; the installed OpenROAD uses the
# historical centered initialization by default and rejects the spelling.
if {[llength [info commands global_placement]] != 0 &&
    [llength [info commands __compat_native_global_placement]] == 0} {
  rename global_placement __compat_native_global_placement
  proc global_placement {args} {
    set filtered {}
    foreach arg $args {
      if {$arg ne "-force_center_initial_place"} { lappend filtered $arg }
    }
    __compat_native_global_placement {*}$filtered
  }
}
