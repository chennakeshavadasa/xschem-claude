# Characterization suite for the INSTANCE lifecycle — Phase A of the
# stable-object-handles step-2 (instances) work, mirroring the wire suite
# (wrap.tcl / test_body.tcl). Locks today's instance behavior through the Tcl
# surface so the upcoming lifecycle funnel refactor is provably
# behavior-identical.
#
# Run from the source tree (needs an X display, no rebuild for Tcl changes):
#
#   cd src && timeout -s KILL 120 ./xschem -q --script ../tests/stable_handles/inst_wrap.tcl
#
# Results in /tmp/sh_inst_test.log. PASS/FAIL per check, final line DONE.
# The user's recent_files is backed up/restored; all edits happen on a /tmp
# copy of the fixture — the repo tree is never written to.

set ::qo_dir [file normalize [file dirname [info script]]]
set ::logfd [open /tmp/sh_inst_test.log w]

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
# expected-failure variant for the eventual TDD red tests (Phase D)
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
  set ::qo_conf_bak /tmp/sh_inst_recent_files.bak
  file copy -force $USER_CONF_DIR/recent_files $::qo_conf_bak
}

if { [catch {source $::qo_dir/inst_body.tcl} err] } {
  puts $::logfd "ERROR: $err"
  puts $::logfd $::errorInfo
}

if { $::qo_conf_bak ne {} } {
  catch {file copy -force $::qo_conf_bak $USER_CONF_DIR/recent_files}
}
foreach f [glob -nocomplain /tmp/sh_inst_fixture.sch /tmp/sh_inst_snap_*.sch /tmp/sh_inst_save_*.sch] {
  catch {file delete -force $f}
}

puts $::logfd "DONE"
flush $::logfd
close $::logfd
exit
