if {![info exists ::env(WBQ_B16_SMOKE_OUTPUT_ODB)] || $::env(WBQ_B16_SMOKE_OUTPUT_ODB) eq ""} { error "missing B16 smoke ODB" }
read_db $::env(WBQ_B16_SMOKE_OUTPUT_ODB)
set block [ord::get_db_block]
set count 0
foreach bterm [$block getBTerms] {
  set name [$bterm getName]
  if {[string match "cmd_*" $name] || [string match "read_*" $name]} { incr count }
}
if {$count != 565} { error "B16 smoke reopen bump count mismatch: $count" }
puts "WBQ_B16_SMOKE_INDEPENDENT_REOPEN PASS bump_terms=$count columns=23"
