# Independently reopen and audit the Phase-3 wbq placement checkpoint.
# Required environment variables are supplied by run_normalization_hbm_wbq_place_audit.sh.

foreach name {WBQ_PLATFORM_ROOT WBQ_PLACE_ODB WBQ_PLACE_SDC} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}

set platform_root $::env(WBQ_PLATFORM_ROOT)
read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $::env(WBQ_PLACE_ODB)
read_sdc $::env(WBQ_PLACE_SDC)

set block [ord::get_db_block]
set inst_count [llength [$block getInsts]]
set net_count [llength [$block getNets]]
set bterm_count [llength [$block getBTerms]]
# Current OpenROAD's check_placement command returns no numeric value.  It
# raises DPL-0033 when any placement check fails, so reaching the next command
# is the authoritative zero-violation result.
check_placement -verbose
set violations 0

# Preserve physical evidence for the hierarchy that motivated this wbq run.
# Yosys/OpenROAD flatten hierarchy into instance names, so measure every placed
# standard cell carrying a generated bank/quad scope rather than inferring
# locality from the RTL alone.
proc report_locality {block kind pattern expected_groups} {
  array set count {}
  array set sum_x {}
  array set sum_y {}
  array set min_x {}
  array set min_y {}
  array set max_x {}
  array set max_y {}
  set dbu_per_um [$block getDbUnitsPerMicron]

  foreach inst [$block getInsts] {
    set clean_name [string map {"\\" ""} [$inst getName]]
    if {![regexp $pattern $clean_name -> group]} {
      continue
    }
    set bbox [$inst getBBox]
    set x [expr {([$bbox xMin] + [$bbox xMax]) / 2.0}]
    set y [expr {([$bbox yMin] + [$bbox yMax]) / 2.0}]
    if {![info exists count($group)]} {
      set count($group) 0
      set sum_x($group) 0.0
      set sum_y($group) 0.0
      set min_x($group) $x
      set min_y($group) $y
      set max_x($group) $x
      set max_y($group) $y
    }
    incr count($group)
    set sum_x($group) [expr {$sum_x($group) + $x}]
    set sum_y($group) [expr {$sum_y($group) + $y}]
    if {$x < $min_x($group)} { set min_x($group) $x }
    if {$y < $min_y($group)} { set min_y($group) $y }
    if {$x > $max_x($group)} { set max_x($group) $x }
    if {$y > $max_y($group)} { set max_y($group) $y }
  }

  set groups [lsort -integer [array names count]]
  puts "WBQ_PLACE_AUDIT_LOCALITY_SUMMARY $kind [llength $groups] $expected_groups"
  foreach group $groups {
    puts [format "WBQ_PLACE_AUDIT_LOCALITY %s %d %d %.3f %.3f %.3f %.3f %.3f %.3f" \
      $kind $group $count($group) \
      [expr {$sum_x($group) / $count($group) / $dbu_per_um}] \
      [expr {$sum_y($group) / $count($group) / $dbu_per_um}] \
      [expr {$min_x($group) / $dbu_per_um}] [expr {$min_y($group) / $dbu_per_um}] \
      [expr {$max_x($group) / $dbu_per_um}] [expr {$max_y($group) / $dbu_per_um}]]
  }
}

report_locality $block BANK {g_bank\[([0-9]+)\]} 16
report_locality $block QUAD {g_quad\[([0-9]+)\]} 4

puts "WBQ_PLACE_AUDIT_TOP [$block getName]"
puts "WBQ_PLACE_AUDIT_DIE_AREA [$block getDieArea]"
puts "WBQ_PLACE_AUDIT_CORE_AREA [$block getCoreArea]"
puts "WBQ_PLACE_AUDIT_INSTANCE_COUNT $inst_count"
puts "WBQ_PLACE_AUDIT_NET_COUNT $net_count"
puts "WBQ_PLACE_AUDIT_BTERM_COUNT $bterm_count"
puts "WBQ_PLACE_AUDIT_VIOLATIONS $violations"

if {$violations != 0} {
  error "wbq placement has $violations legalization violations"
}
puts "WBQ_PLACE_AUDIT_PASS"
