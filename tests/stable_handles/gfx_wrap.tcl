# Characterization suite for the GRAPHICAL object lifecycle (rect/line/poly/arc)
# — Phase A of the stable-object-handles step-3 (graphical types) work,
# mirroring the wire and instance suites. Locks today's per-LAYER behavior
# through the Tcl surface so the upcoming lifecycle funnel refactor is provably
# behavior-identical, and the Phase D identity work is RED-first.
#
# Run from the source tree (needs an X display, no rebuild for Tcl changes):
#
#   cd src && timeout -s KILL 120 ./xschem -q --script ../tests/stable_handles/gfx_wrap.tcl
#
# Results in /tmp/sh_gfx_test.log. PASS/FAIL per check, final line DONE.
# The user's recent_files is backed up/restored; all edits happen on a /tmp
# copy of the fixture — the repo tree is never written to.

set ::qo_dir [file normalize [file dirname [info script]]]
set ::logfd [open /tmp/sh_gfx_test.log w]

proc check {what cond} {
  if { [catch {uplevel 1 [list expr $cond]} res] } {
    puts $::logfd "FAIL: $what (eval error: $res)"
  } elseif { $res } {
    puts $::logfd "PASS: $what"
  } else {
    puts $::logfd "FAIL: $what"
  }
  flush $::logfd
}
# expected-failure variant for the Phase D TDD red tests
proc xcheck {what cond} {
  if { [catch {uplevel 1 [list expr $cond]} res] } {
    puts $::logfd "XFAIL: $what (eval error: $res)"
  } elseif { $res } {
    puts $::logfd "PASS (was XFAIL — flip to check): $what"
  } else {
    puts $::logfd "XFAIL: $what"
  }
  flush $::logfd
}

set ::qo_conf_bak {}
if { [info exists USER_CONF_DIR] && [file exists $USER_CONF_DIR/recent_files] } {
  set ::qo_conf_bak /tmp/sh_gfx_recent_files.bak
  file copy -force $USER_CONF_DIR/recent_files $::qo_conf_bak
}

if { [catch {source $::qo_dir/gfx_body.tcl} err] } {
  puts $::logfd "ERROR: $err"
  puts $::logfd $::errorInfo
}

if { $::qo_conf_bak ne {} } {
  catch {file copy -force $::qo_conf_bak $USER_CONF_DIR/recent_files}
}
foreach f [glob -nocomplain /tmp/sh_gfx_fixture.sch /tmp/sh_gfx_snap_*.sch /tmp/sh_gfx_save_*.sch] {
  catch {file delete -force $f}
}

puts $::logfd "DONE"
flush $::logfd
close $::logfd
exit
