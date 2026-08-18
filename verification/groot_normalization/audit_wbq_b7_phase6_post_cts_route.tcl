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
set violations [string trim [check_placement -verbose]]
set clock_net_count 0
foreach net [$block getNets] {
  if {[$net getSigType] eq "CLOCK"} { incr clock_net_count }
}
set has_routes [grt::have_routes]
puts "WBQ_B7_PHASE6_ROUTE_AUDIT_TOP [$block getName]"
puts "WBQ_B7_PHASE6_ROUTE_AUDIT_CLOCK_NET_COUNT $clock_net_count"
puts "WBQ_B7_PHASE6_ROUTE_AUDIT_HAS_GLOBAL_ROUTES $has_routes"
puts "WBQ_B7_PHASE6_ROUTE_AUDIT_VIOLATIONS {$violations}"
if {[$block getName] ne "logic_die_normalization_hbm_quad_local_b2_top"} {
  error "unexpected B7 Phase 6 post-CTS top"
}
if {$clock_net_count < 1 || !$has_routes || $violations ne ""} {
  error "B7 Phase 6 post-CTS route audit failed"
}
puts "WBQ_B7_PHASE6_POST_CTS_ROUTE_AUDIT PASS"

