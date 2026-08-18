foreach name {WBQ_B11_SMOKE_INPUT_ODB WBQ_B11_SMOKE_INPUT_SDC WBQ_B11_SMOKE_OUTPUT_ODB WBQ_PLATFORM_ROOT} {
  if {![info exists ::env($name)] || $::env($name) eq ""} { error "missing required environment variable $name" }
}
read_liberty $::env(WBQ_PLATFORM_ROOT)/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $::env(WBQ_B11_SMOKE_INPUT_ODB)
read_sdc $::env(WBQ_B11_SMOKE_INPUT_SDC)
set block [ord::get_db_block]
set bump_terms {}
foreach bterm [$block getBTerms] {
  set name [$bterm getName]
  if {[string match "cmd_*" $name] || [string match "read_*" $name]} { lappend bump_terms $name }
}
set bump_terms [lsort $bump_terms]
set columns 21
set pitch 250.0
set x0 1500.0
set y0 1500.0
if {[llength $bump_terms] != 565} { error "unexpected B11 bump count [llength $bump_terms]" }
set index 0
foreach name $bump_terms {
  set column [expr {$index % $columns}]
  set row [expr {$index / $columns}]
  place_pin -pin_name $name -layer met5 \
    -location [list [expr {$x0 + $column*$pitch}] [expr {$y0 + $row*$pitch}]] \
    -pin_size {20.0 20.0} -placed_status
  incr index
}
write_db $::env(WBQ_B11_SMOKE_OUTPUT_ODB)
puts "WBQ_B11_SMOKE_INPUT_REOPEN_AND_CHECKPOINT PASS bump_terms=[llength $bump_terms] columns=$columns"
