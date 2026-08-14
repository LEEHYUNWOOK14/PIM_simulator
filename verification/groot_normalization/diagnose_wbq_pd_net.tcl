# Reproduce Prim-Dijkstra Steiner construction for one placed WBQ net.
foreach name {WBQ_DIAG_ODB WBQ_DIAG_NET} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}

read_db $::env(WBQ_DIAG_ODB)
set block [ord::get_db_block]
set net [$block findNet $::env(WBQ_DIAG_NET)]
if {$net eq "NULL"} {
  error "net not found: $::env(WBQ_DIAG_NET)"
}

set xs {}
set ys {}
set unplaced 0
foreach iterm [$net getITerms] {
  lassign [$iterm getAvgXY] placed x y
  if {$placed} {
    lappend xs $x
    lappend ys $y
  } else {
    incr unplaced
  }
}

set pin_count [llength $xs]
puts "WBQ_PD_DIAG_BEGIN net=[$net getName] terminals=[$net getTermCount] placed_points=$pin_count unplaced=$unplaced alpha=0.3"
flush stdout
if {$pin_count < 2} {
  error "net has fewer than two placed points"
}

set start_ms [clock milliseconds]
stt::report_pd_tree $xs $ys 0 0.3
set elapsed_ms [expr {[clock milliseconds] - $start_ms}]
puts "WBQ_PD_DIAG_END net=[$net getName] placed_points=$pin_count elapsed_ms=$elapsed_ms"
flush stdout
