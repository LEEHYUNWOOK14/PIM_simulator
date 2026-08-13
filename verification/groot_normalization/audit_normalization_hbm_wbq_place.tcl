# Independently reopen and audit the Phase-3 wbq placement checkpoint.
# Required environment variables are supplied by run_normalization_hbm_wbq_place_audit.sh.

foreach name {WBQ_PLATFORM_ROOT WBQ_PLACE_ODB WBQ_PLACE_SDC} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}

set platform_root $::env(WBQ_PLATFORM_ROOT)
read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $::env(WBQ_PLACE_ODB)
read_sdc $::env(WBQ_PLACE_SDC)

set block [ord::get_db_block]
set inst_count [llength [$block getInsts]]
set net_count [llength [$block getNets]]
set bterm_count [llength [$block getBTerms]]
set violations [check_placement -verbose]

puts "WBQ_PLACE_AUDIT_TOP [$block getName]"
puts "WBQ_PLACE_AUDIT_DIE_AREA [$block getDieArea]"
puts "WBQ_PLACE_AUDIT_CORE_AREA [$block getCoreArea]"
puts "WBQ_PLACE_AUDIT_INSTANCE_COUNT $inst_count"
puts "WBQ_PLACE_AUDIT_NET_COUNT $net_count"
puts "WBQ_PLACE_AUDIT_BTERM_COUNT $bterm_count"
puts "WBQ_PLACE_AUDIT_VIOLATIONS $violations"

if {$violations != 0} {
  error "wbq placement has $violations legalization violations"
}
puts "WBQ_PLACE_AUDIT_PASS"
