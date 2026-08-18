# Keep the asynchronous reset out of generic placement repair.  Its 318K
# sinks require a dedicated hierarchical reset tree; generic slew/cap repair
# repeatedly rebuilds and reduces a prohibitively large placement RC network.
set reset_nets [get_nets -quiet rst_ni]
if {[llength $reset_nets] != 1} {
  utl::error RSZ 2002 "WBQ reset-policy net not found or ambiguous: rst_ni"
}
set_dont_touch $reset_nets
set reset_db_net [sta::sta_to_db_net [lindex $reset_nets 0]]
if {$reset_db_net == "NULL"} {
  utl::error EST 112 "WBQ reset-policy ODB net not found: rst_ni"
}
$reset_db_net setSigType RESET

# Keep the pre-CTS clock on the bounded Flute construction.  Ordinary nets
# retain the OpenROAD default routing alpha and therefore preserve QoR policy.
set clock_nets [get_nets -quiet clk_i]
if {[llength $clock_nets] != 1} {
  utl::error STT 100 "WBQ reset-policy clock not found or ambiguous: clk_i"
}
set_routing_alpha 0.0 -net $clock_nets

puts "WBQ_GUARDED_RESET_EXCLUSION rst_ni=dont_touch,placement_parasitics_skip clk_i_alpha=0.0 ordinary_alpha=inherited"
