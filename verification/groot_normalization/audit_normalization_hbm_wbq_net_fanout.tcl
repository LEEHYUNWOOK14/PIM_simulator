# Read-only db-level fanout audit for diagnosing long repair_design vertices.
foreach name {WBQ_FANOUT_ODB} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}

read_db $::env(WBQ_FANOUT_ODB)
set block [ord::get_db_block]
set ranked {}
set scanned 0
set over_1000 0
set over_5000 0
foreach net [$block getNets] {
  incr scanned
  set terminals [$net getTermCount]
  if {$terminals > 1000} {
    incr over_1000
  }
  if {$terminals > 5000} {
    incr over_5000
  }
  if {$terminals > 1000} {
    lappend ranked [list $terminals [$net getName] [$net getSigType]]
  }
}
set ranked [lsort -integer -decreasing -index 0 $ranked]
puts "WBQ_FANOUT_AUDIT_SCANNED $scanned"
puts "WBQ_FANOUT_AUDIT_OVER_1000 $over_1000"
puts "WBQ_FANOUT_AUDIT_OVER_5000 $over_5000"
set rank 0
foreach item [lrange $ranked 0 49] {
  incr rank
  puts "WBQ_FANOUT_AUDIT_TOP $rank [lindex $item 0] [lindex $item 2] [lindex $item 1]"
}
puts "WBQ_FANOUT_AUDIT_PASS"
