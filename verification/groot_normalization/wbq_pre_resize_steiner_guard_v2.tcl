# Avoid quadratic Prim-Dijkstra construction on the pre-CTS clock/reset nets.
set block [ord::get_db_block]
set guarded_nets {clk_i rst_ni}
foreach net_name $guarded_nets {
  set net [$block findNet $net_name]
  if {$net eq "NULL"} {
    utl::error STT 100 "WBQ Steiner guard net not found: {}" $net_name
  }
  stt::set_net_alpha $net 0.0
}
puts "WBQ_STEINER_GUARD alpha=0.0 nets=$guarded_nets"
