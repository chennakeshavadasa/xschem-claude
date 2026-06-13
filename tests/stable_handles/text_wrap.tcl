# Suite for the TEXT object type's stable handle — the 7th and last drawable
# type to get a session-stable id, completing the set. text is a FLAT array
# (xctx->text[], count xctx->texts), so this mirrors the wire treatment, not the
# per-layer graphical one.
#
# Run from the source tree (needs an X display, no rebuild for Tcl changes):
#
#   cd src && timeout -s KILL 120 ./xschem -q --script ../tests/stable_handles/text_wrap.tcl
#
# Results in /tmp/sh_text_test.log. PASS/FAIL per check, final line DONE.

set ::qo_dir [file normalize [file dirname [info script]]]
set ::logfd [open /tmp/sh_text_test.log w]

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
  set ::qo_conf_bak /tmp/sh_text_recent_files.bak
  file copy -force $USER_CONF_DIR/recent_files $::qo_conf_bak
}

if { [catch {source $::qo_dir/text_body.tcl} err] } {
  puts $::logfd "ERROR: $err"
  puts $::logfd $::errorInfo
}

if { $::qo_conf_bak ne {} } {
  catch {file copy -force $::qo_conf_bak $USER_CONF_DIR/recent_files}
}

puts $::logfd "DONE"
flush $::logfd
close $::logfd
exit
