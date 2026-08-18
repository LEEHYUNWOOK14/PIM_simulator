# Independently reopen the completed Phase 3.4 checkpoint before legalization.

foreach name {WBQ_PHASE34_ODB} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}

read_db $::env(WBQ_PHASE34_ODB)
set block [ord::get_db_block]

if {$block eq "NULL"} {
  error "Phase 3.4 ODB did not produce a database block"
}

set top [$block getName]
set inst_count [llength [$block getInsts]]
set net_count [llength [$block getNets]]
set bterm_count [llength [$block getBTerms]]

if {$top ne "logic_die_normalization_hbm_top"} {
  error "unexpected Phase 3.4 top: $top"
}
if {$inst_count <= 0 || $net_count <= 0 || $bterm_count <= 0} {
  error "invalid Phase 3.4 database counts: inst=$inst_count net=$net_count bterm=$bterm_count"
}

puts "WBQ_PHASE34_REOPEN_TOP $top"
puts "WBQ_PHASE34_REOPEN_INSTANCE_COUNT $inst_count"
puts "WBQ_PHASE34_REOPEN_NET_COUNT $net_count"
puts "WBQ_PHASE34_REOPEN_BTERM_COUNT $bterm_count"
puts "WBQ_PHASE34_REOPEN_PASS"
