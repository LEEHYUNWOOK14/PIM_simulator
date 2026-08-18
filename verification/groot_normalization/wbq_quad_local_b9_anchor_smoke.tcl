foreach name {WBQ_PLATFORM_ROOT WBQ_B7_RUDY_ODB WBQ_B2_PLACE_SDC WBQ_B9_SMOKE_ODB} {
  if {![info exists ::env($name)] || $::env($name) eq ""} { error "missing required environment variable $name" }
}
read_liberty $::env(WBQ_PLATFORM_ROOT)/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db $::env(WBQ_B7_RUDY_ODB)
read_sdc $::env(WBQ_B2_PLACE_SDC)
source $::env(WBQ_PLATFORM_ROOT)/setRC.tcl
set block [ord::get_db_block]
if {[$block getName] ne "logic_die_normalization_hbm_quad_local_b2_top" || [llength [$block getRegions]] != 4} {
  error "unexpected B9 smoke design or fences"
}
set anchor_specs {
  {u_b2_implementation/u_pcu/u_quad_datapath/load_slew427175 6347540 2535040 MX existing}
  {u_b2_implementation/u_quad_local_adapter/wire440835 4686940 1468800 R180 existing}
  {u_b2_implementation/u_quad_local_adapter/wire440455 7308480 4417280 MY added}
  {u_b2_implementation/u_quad_local_adapter/wire440867 4287200 1392640 MY added}
  {u_b2_implementation/u_quad_local_adapter/wire440876 4285360 1479680 R180 added}
  {u_b2_implementation/u_quad_local_adapter/wire441097 4723740 6636800 R0 added}
  {u_b2_implementation/u_quad_local_adapter/wire441921 4376900 2186880 MX added}
  {u_b2_implementation/u_quad_local_adapter/wire441940 4345620 2208640 R0 added}
  {u_b2_implementation/u_quad_local_adapter/wire441994 4293640 2224960 MX added}
}
set added 0
foreach spec $anchor_specs {
  lassign $spec name x y orient mode
  set inst [$block findInst $name]
  if {$inst eq "NULL"} { error "B9 smoke missing anchor $name" }
  $inst setOrigin $x $y
  $inst setOrient $orient
  $inst setPlacementStatus LOCKED
  if {$mode eq "added"} { incr added; puts "WBQ_B9_SMOKE_OFFENDER name={$name}" }
  puts "WBQ_B9_SMOKE_ANCHOR name={$name} origin_dbu={$x $y} orient={$orient} status={[$inst getPlacementStatus]} mode={$mode}"
}
if {$added != 7} { error "B9 smoke added-anchor count mismatch" }
write_db $::env(WBQ_B9_SMOKE_ODB)
puts "WBQ_B9_SMOKE_INPUT_REOPEN_AND_CHECKPOINT PASS anchors=9 offenders=7"
