# Smoke-test the WBQ pre-resize Steiner guard against the placed database.
foreach name {WBQ_DIAG_ODB WBQ_STEINER_GUARD} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "missing required environment variable $name"
  }
}
read_db $::env(WBQ_DIAG_ODB)
source $::env(WBQ_STEINER_GUARD)
puts "WBQ_STEINER_GUARD_SMOKE PASS"
