# Independently reopen and audit the post-CTS wbq checkpoint.

foreach name {WBQ_PLATFORM_ROOT WBQ_CTS_ODB WBQ_CTS_SDC} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}

set platform_root $::env(WBQ_PLATFORM_ROOT)
read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $::env(WBQ_CTS_ODB)
read_sdc $::env(WBQ_CTS_SDC)

set block [ord::get_db_block]
set violations [check_placement -verbose]
set clocks [get_clocks *]
set clock_count [llength $clocks]
set sourced_clock_count 0
foreach clock $clocks {
  if {[llength [get_property $clock sources]] > 0} {
    incr sourced_clock_count
  }
}
set clock_net_count 0
foreach net [$block getNets] {
  if {[$net getSigType] eq "CLOCK"} {
    incr clock_net_count
  }
}

puts "WBQ_PHASE6_CTS_AUDIT_TOP [$block getName]"
puts "WBQ_PHASE6_CTS_AUDIT_INSTANCE_COUNT [llength [$block getInsts]]"
puts "WBQ_PHASE6_CTS_AUDIT_NET_COUNT [llength [$block getNets]]"
puts "WBQ_PHASE6_CTS_AUDIT_CLOCK_COUNT $clock_count"
puts "WBQ_PHASE6_CTS_AUDIT_SOURCED_CLOCK_COUNT $sourced_clock_count"
puts "WBQ_PHASE6_CTS_AUDIT_CLOCK_NET_COUNT $clock_net_count"
puts "WBQ_PHASE6_CTS_AUDIT_VIOLATIONS $violations"

if {[$block getName] ne "logic_die_normalization_hbm_top"} {
  error "unexpected post-CTS top [$block getName]"
}
if {$clock_count < 1 || $sourced_clock_count < 1 || $clock_net_count < 1} {
  error "post-CTS checkpoint does not contain an explicit sourced clock network"
}
if {$violations != 0} {
  error "post-CTS checkpoint has $violations placement violations"
}
puts "WBQ_PHASE6_CTS_AUDIT_PASS"
