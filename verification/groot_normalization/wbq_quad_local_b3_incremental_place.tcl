foreach name {
  WBQ_PLATFORM_ROOT
  WBQ_B2_PLACE_ODB
  WBQ_B2_PLACE_SDC
  WBQ_B3_PLACE_ODB
  WBQ_B3_PLACE_SDC
} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}

# B3 is intentionally netlist-equivalent to B2.  Read the sealed B2 placement
# as an immutable checkpoint and write every B3 artifact to a separate path.
set platform_root $::env(WBQ_PLATFORM_ROOT)
read_liberty $platform_root/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $::env(WBQ_B2_PLACE_ODB)
read_sdc $::env(WBQ_B2_PLACE_SDC)
source $platform_root/setRC.tcl

puts "WBQ_B3_INCREMENTAL_PLACE_INPUT odb=$::env(WBQ_B2_PLACE_ODB)"
set_placement_padding -global -left 0 -right 0
detailed_placement -incremental \
  -max_displacement {1000 1000} \
  -site_search_window 100 -row_search_window 20 -drc_penalty 20
optimize_mirroring
check_placement -verbose

write_db $::env(WBQ_B3_PLACE_ODB)
write_sdc -no_timestamp $::env(WBQ_B3_PLACE_SDC)
puts "WBQ_B3_INCREMENTAL_PLACE PASS odb=$::env(WBQ_B3_PLACE_ODB)"
