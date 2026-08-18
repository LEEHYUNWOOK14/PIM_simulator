foreach name {WBQ_PLATFORM_ROOT WBQ_DRT_ODB WBQ_DRT_SDC} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}
set platform_root $::env(WBQ_PLATFORM_ROOT)
read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $::env(WBQ_DRT_ODB)
read_sdc $::env(WBQ_DRT_SDC)
set block [ord::get_db_block]
set clock_net_count 0
set signal_wire_count 0
foreach net [$block getNets] {
  if {[$net getSigType] eq "CLOCK"} { incr clock_net_count }
  if {[$net getSigType] eq "SIGNAL" && [$net getWire] ne "NULL"} { incr signal_wire_count }
}
set fully_routed [design_is_routed]
puts "WBQ_B5_PHASE7_AUDIT_TOP [$block getName]"
puts "WBQ_B5_PHASE7_AUDIT_CLOCK_NET_COUNT $clock_net_count"
puts "WBQ_B5_PHASE7_AUDIT_SIGNAL_WIRE_COUNT $signal_wire_count"
puts "WBQ_B5_PHASE7_AUDIT_DESIGN_IS_ROUTED $fully_routed"
if {[$block getName] ne "logic_die_normalization_hbm_quad_local_b2_top"} {
  error "unexpected B5 Phase 7 top"
}
if {$clock_net_count < 1 || $signal_wire_count < 1 || !$fully_routed} {
  error "B5 Phase 7 detailed-route audit failed"
}
puts "WBQ_B5_PHASE7_DETAILED_ROUTE_AUDIT PASS"
