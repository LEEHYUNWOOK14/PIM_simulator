/^violation type:/ {
  type = $0
  sub(/^violation type: /, "", type)
  types[type]++
  entries++
}
/comment: capacity:/ {
  capacity = $2
  usage = $3
  congestion = $4
  sub(/capacity:/, "", capacity)
  sub(/usage:/, "", usage)
  sub(/congestion:/, "", congestion)
  comments++
  if (usage > capacity) {
    overflow_edges++
    total_overflow_tracks += usage - capacity
  } else if (usage == capacity) {
    at_capacity++
  }
  if (congestion > max_congestion) {
    max_congestion = congestion
    max_capacity = capacity
    max_usage = usage
  }
}
/on Layer / { layers[$NF]++ }
/bbox =/ {
  x1 = $3; y1 = $4; x2 = $6; y2 = $7
  gsub(/[(),]/, "", x1); gsub(/[(),]/, "", y1)
  gsub(/[(),]/, "", x2); gsub(/[(),]/, "", y2)
  if (x1 <= 7.0 || y1 <= 7.0 || x2 >= 9022.9 || y2 >= 9022.9) boundary_entries++
  bx = int(((x1 + x2) / 2.0) / 1003.3223)
  by = int(((y1 + y2) / 2.0) / 1003.3223)
  if (bx < 0) bx = 0; if (bx > 8) bx = 8
  if (by < 0) by = 0; if (by > 8) by = 8
  bins[bx "," by]++
}
END {
  print "entries=" entries
  print "comments=" comments
  print "overflow_edges=" overflow_edges
  print "at_capacity=" at_capacity
  print "total_overflow_tracks=" total_overflow_tracks
  print "max_congestion=" max_congestion
  print "max_capacity=" max_capacity
  print "max_usage=" max_usage
  print "boundary_entries=" boundary_entries
  for (key in types) print "type[" key "]=" types[key]
  for (key in layers) print "layer[" key "]=" layers[key]
  for (key in bins) print "bin[" key "]=" bins[key]
}
