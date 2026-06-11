# Action-log Phase 1, Layer A first slice: Tcl-backed actions dispatched through
# the binding table (dispatch_input_action, callback.c) are recorded in the
# action log -- the canonical d->tcl command verbatim on success, a
# '# failed: <cmd>' comment on error (recorded AFTER evaluation, same rule as
# CIW-typed commands, so the file stays source-able). C-backed actions are NOT
# logged yet (that is the next slice -- needs the canonical command surfaced
# from actions.csv).
# Run under X with --pipe; pass --logdir so the log lands in a temp dir:
#   DISPLAY=:0 ./src/xschem --pipe -q --logdir $(mktemp -d) \
#       --script tests/headless/test_action_log_dispatch.tcl
update idletasks
focus -force .drw
update idletasks

proc check {name ok} {
  puts "[expr {$ok ? {ok:  } : {FAIL:}}] $name"
  if {!$ok} {incr ::fails}
}
set ::fails 0

proc key {ks {st 0}} { xschem callback .drw 2 400 300 $ks 0 0 $st; update idletasks }
proc loglines {} {
  set fd [open [xschem get actionlog_filename] r]
  set body [read $fd]
  close $fd
  return [split [string trimright $body \n] \n]
}

check "action log open" [expr {[xschem get actionlog_filename] ne {}}]

# 1) success path: K (keysym 75) -> hilight.un_highlight_all_net_pins, Tcl-backed
#    "xschem unhilight_all". The exact command must appear in the file, raw.
set n0 [llength [loglines]]
key 75
set lines [loglines]
check "Tcl-backed key logged verbatim" \
  [expr {[lsearch -exact $lines {xschem unhilight_all}] >= $n0}]

# 2) idle gate still respected upstream: at semaphore>=2 the chord is skipped
#    entirely, so nothing new may be logged either.
xschem set semaphore 2
set n0 [llength [loglines]]
key 75
check "idle_only chord skipped while busy -> not logged" \
  [expr {[llength [loglines]] == $n0}]
xschem set semaphore 0

# 3) failure path: make `=` (keysym 61 -> tools.execute_tcl_command, Tcl-backed
#    "tclcmd") fail by renaming the proc away; the log must get a comment, not
#    the raw command (replaying a failing line would abort `source`).
rename tclcmd __saved_tclcmd
set n0 [llength [loglines]]
key 61
set lines [loglines]
check "failed action logged as comment" \
  [expr {[lsearch -exact $lines {# failed: tclcmd}] >= $n0}]
check "failed action not logged raw" \
  [expr {[lsearch -exact $lines {tclcmd}] < 0}]
rename __saved_tclcmd tclcmd

# 4) C-backed actions are not logged yet (this slice is Tcl-backed only):
#    wheel-up on the canvas runs view.zoom_in (C fn) and must add no line.
set n0 [llength [loglines]]
xschem callback .drw 4 400 300 0 4 0 0
update idletasks
check "C-backed action adds no line (yet)" [expr {[llength [loglines]] == $n0}]

# 5) the whole file stays source-able (header comment, raw commands, # comments)
check "file is source-able" \
  [expr {![catch {uplevel #0 [list source [xschem get actionlog_filename]]} err]}]

puts [expr {$::fails == 0 ? "RESULT: ALL PASS" : "RESULT: $::fails FAILED"}]
flush stdout
exit [expr {$::fails != 0}]
