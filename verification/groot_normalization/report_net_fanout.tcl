set lib $::env(NORM_LIBERTY)
set netlist $::env(NORM_NETLIST)
set top $::env(NORM_TOP)
read_lef $::env(NORM_TECH_LEF)
read_lef $::env(NORM_SC_LEF)
read_liberty $lib
read_verilog $netlist
link_design $top
set ranked {}
set block [ord::get_db_block]
foreach net [$block getNets] {
  set fanout 0
  foreach iterm [$net getITerms] {
    if { [$iterm getIoType] == "INPUT" } { incr fanout }
  }
  lappend ranked [list $fanout [$net getName]]
}
set ranked [lsort -integer -decreasing -index 0 $ranked]
puts "FANOUT_REPORT_BEGIN"
foreach item [lrange $ranked 0 49] {
  set net_name [lindex $item 1]
  set net [$block findNet $net_name]
  set driver "PORT"
  foreach iterm [$net getITerms] {
    if { [$iterm getIoType] == "OUTPUT" } {
      set inst [$iterm getInst]
      set driver "[$inst getName]/[[$iterm getMTerm] getName]:[[$inst getMaster] getName]"
    }
  }
  puts "[lindex $item 0]\t$net_name\t$driver"
}
puts "FANOUT_REPORT_END"
