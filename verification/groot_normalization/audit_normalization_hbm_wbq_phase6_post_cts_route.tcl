# Independently reopen and audit the Phase-6 post-CTS global-route checkpoint.

foreach name {WBQ_PLATFORM_ROOT WBQ_ROUTED_ODB WBQ_ROUTED_SDC} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}

set platform_root $::env(WBQ_PLATFORM_ROOT)
read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $::env(WBQ_ROUTED_ODB)
read_sdc $::env(WBQ_ROUTED_SDC)

set block [ord::get_db_block]
set violations [check_placement -verbose]
set clock_net_count 0
foreach net [$block getNets] {
  if {[$net getSigType] eq "CLOCK"} {
    incr clock_net_count
  }
}
set has_global_routes [grt::have_routes]

puts "WBQ_PHASE6_ROUTE_AUDIT_TOP [$block getName]"
puts "WBQ_PHASE6_ROUTE_AUDIT_INSTANCE_COUNT [llength [$block getInsts]]"
puts "WBQ_PHASE6_ROUTE_AUDIT_NET_COUNT [llength [$block getNets]]"
puts "WBQ_PHASE6_ROUTE_AUDIT_CLOCK_NET_COUNT $clock_net_count"
puts "WBQ_PHASE6_ROUTE_AUDIT_HAS_GLOBAL_ROUTES $has_global_routes"
puts "WBQ_PHASE6_ROUTE_AUDIT_VIOLATIONS $violations"

if {[$block getName] ne "logic_die_normalization_hbm_top"} {
  error "unexpected post-CTS routed top [$block getName]"
}
if {$clock_net_count < 1} {
  error "post-CTS routed checkpoint has no explicit CLOCK nets"
}
if {!$has_global_routes} {
  error "post-CTS routed checkpoint does not retain global routes"
}
if {$violations != 0} {
  error "post-CTS routed checkpoint has $violations placement violations"
}
puts "WBQ_PHASE6_ROUTE_AUDIT_PASS"
