# Avoid quadratic Prim-Dijkstra construction on the pre-CTS clock/reset nets.
set guarded_nets {clk_i rst_ni}
foreach net_name $guarded_nets {
  if {[llength [get_nets -quiet $net_name]] != 1} {
    utl::error STT 100 "WBQ Steiner guard net not found or ambiguous: {}" $net_name
  }
}
set_routing_alpha 0.0 -net $guarded_nets
puts "WBQ_STEINER_GUARD alpha=0.0 nets=$guarded_nets"
