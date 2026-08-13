set odb $::env(B0_FINAL_ODB)
set vcd $::env(B0_VCD)
set scope $::env(B0_VCD_SCOPE)
set lib $::env(B0_LIBERTY)
set sdc $::env(B0_FINAL_SDC)

read_liberty $lib
read_db $odb
read_sdc $sdc
puts "B0_POWER_VCD_BEGIN"
read_vcd -scope $scope $vcd
puts "B0_POWER_VCD_END"
puts "B0_POWER_REPORT_BEGIN"
report_power -digits 9
puts "B0_POWER_REPORT_END"
exit
