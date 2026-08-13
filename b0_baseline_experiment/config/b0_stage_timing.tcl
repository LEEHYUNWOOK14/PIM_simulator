read_liberty $::env(B0_LIBERTY)
read_db $::env(B0_STAGE_ODB)
read_sdc $::env(B0_STAGE_SDC)
if {[info exists ::env(B0_STAGE_SPEF)] && $::env(B0_STAGE_SPEF) ne ""} {
  read_spef $::env(B0_STAGE_SPEF)
} else {
  estimate_parasitics -placement
}
puts "B0_STAGE_TIMING_BEGIN $::env(B0_STAGE_NAME)"
report_worst_slack -max
report_worst_slack -min
report_tns
report_clock_skew
report_checks -path_delay max -fields {slew cap input_pin net fanout} -format full_clock_expanded -digits 4 -group_count 1 -endpoint_count 1
puts "B0_STAGE_TIMING_END $::env(B0_STAGE_NAME)"
exit
