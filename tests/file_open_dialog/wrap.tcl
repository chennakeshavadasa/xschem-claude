# Headless scripted test for the file-open dialog enhancement
# (path entry + Recent drop-down in load_file_dialog).
#
# Run from the source tree (needs an X display, no rebuild required):
#
#   cd src && timeout -s KILL 120 ./xschem -q --script ../tests/file_open_dialog/wrap.tcl
#
# Results land in /tmp/qo_test.log: expect 33 PASS, 0 FAIL, final line DONE.
# Your $USER_CONF_DIR/recent_files is backed up before and restored after the
# run, even if the test body errors out.

set ::qo_dir [file normalize [file dirname [info script]]]
set ::logfd [open /tmp/qo_test.log w]

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

# protect the user's recent-files conf; restored below even on error
set ::qo_conf_bak {}
if { [info exists USER_CONF_DIR] && [file exists $USER_CONF_DIR/recent_files] } {
  set ::qo_conf_bak /tmp/qo_recent_files.bak
  file copy -force $USER_CONF_DIR/recent_files $::qo_conf_bak
}

if { [catch {source $::qo_dir/test_body.tcl} err] } {
  puts $::logfd "ERROR: $err"
  puts $::logfd $::errorInfo
}

if { $::qo_conf_bak ne {} } {
  catch {file copy -force $::qo_conf_bak $USER_CONF_DIR/recent_files}
}
catch {file delete -force /tmp/qo_fixture}

puts $::logfd "DONE"
flush $::logfd
close $::logfd
exit
