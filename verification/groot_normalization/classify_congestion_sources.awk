/^violation type:/ {
  entries++
  has_clock = has_reduction = has_replay = has_writeback = 0
  has_adapter = has_global = has_bank = 0
}
/srcs:/ {
  has_clock = index($0, "net:clk_i") != 0
  has_reduction = index($0, "reduction_data") != 0
  has_replay = index($0, "replay_") != 0
  has_writeback = index($0, "writeback_") != 0
  has_adapter = index($0, "u_adapter/") != 0
  has_global = index($0, "u_global/") != 0
  has_bank = index($0, "g_bank") != 0
  clock_entries += has_clock
  reduction_entries += has_reduction
  replay_entries += has_replay
  writeback_entries += has_writeback
  adapter_entries += has_adapter
  global_entries += has_global
  bank_entries += has_bank
}
/comment: capacity:/ {
  capacity = $2; usage = $3
  sub(/capacity:/, "", capacity); sub(/usage:/, "", usage)
  if (usage > capacity) {
    overflow_entries++
    overflow_clock += has_clock
    overflow_reduction += has_reduction
    overflow_replay += has_replay
    overflow_writeback += has_writeback
    overflow_adapter += has_adapter
    overflow_global += has_global
    overflow_bank += has_bank
  }
}
END {
  print "entries=" entries
  print "clock_entries=" clock_entries
  print "reduction_entries=" reduction_entries
  print "replay_entries=" replay_entries
  print "writeback_entries=" writeback_entries
  print "adapter_entries=" adapter_entries
  print "global_entries=" global_entries
  print "bank_entries=" bank_entries
  print "overflow_entries=" overflow_entries
  print "overflow_clock=" overflow_clock
  print "overflow_reduction=" overflow_reduction
  print "overflow_replay=" overflow_replay
  print "overflow_writeback=" overflow_writeback
  print "overflow_adapter=" overflow_adapter
  print "overflow_global=" overflow_global
  print "overflow_bank=" overflow_bank
}
