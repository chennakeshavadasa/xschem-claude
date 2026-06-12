# integrated quick-open test: drives load_file_dialog headlessly.
# Sourced at global level by wrap.tcl (same directory), which provides
# `check` (writes PASS/FAIL to ::logfd) and `::qo_dir` (this directory).

### stub every modal dialog BEFORE any code path can reach one
set ::mb_calls {}
rename tk_messageBox _real_tk_messageBox
proc tk_messageBox {args} {lappend ::mb_calls $args; return ok}
rename tk_getOpenFile _real_tk_getOpenFile
proc tk_getOpenFile {args} {return {}}
catch {rename alert_ _real_alert_}
proc alert_ {args} {return 1}

### fixtures
set REPO [file normalize $::qo_dir/../..]
set TD [file normalize /tmp/qo_fixture]
file delete -force $TD
file mkdir $TD/projA $TD/projB
file copy -force $REPO/xschem_library/examples/LCC_instances.sch $TD/projA/a.sch
file copy -force $REPO/xschem_library/examples/LM5134A.sch $TD/projB/b.sch

puts $::logfd "USER_CONF_DIR=$USER_CONF_DIR"; flush $::logfd


# drive the dialog only once construction completed: the focus statement is
# the last thing load_file_dialog does before blocking in tkwait
proc qo_drive {script} {
  if { [winfo exists .load] &&
       ([focus -lastfor .load] eq {.load.buttons_bot.entry} ||
        [focus -lastfor .load] eq {.load.buttons_bot.src}) } {
    uplevel #0 $script
  } else {
    after 100 [list qo_drive $script]
  }
}

### A. tctx::recentdirs machinery
set tctx::recentfile {}
set tctx::recentdirs {}
update_recent_dir $TD/projA
check {A1 update_recent_dir adds normalized dir} \
  {$tctx::recentdirs eq [list [file normalize $TD/projA]]}
update_recent_dir $TD/projB
update_recent_dir $TD/projA
check {A2 update_recent_dir dedups and moves to front} \
  {$tctx::recentdirs eq [list $TD/projA $TD/projB]}
for {set i 0} {$i < 12} {incr i} {
  file mkdir $TD/d$i
  update_recent_dir $TD/d$i
}
check {A3 recentdirs capped at 10} {[llength $tctx::recentdirs] == 10}
set ::saved_dirs $tctx::recentdirs
set tctx::recentdirs {}
load_recent_file
check {A4 recentdirs round-trips through recent_files conf} \
  {$tctx::recentdirs eq $::saved_dirs}
set fd2 [open $USER_CONF_DIR/recent_files w]
puts $fd2 "set tctx::recentfile {$TD/projA/a.sch}"
close $fd2
load_recent_file
check {A5 old conf without recentdirs still loads, default empty} \
  {$tctx::recentdirs eq {} && $tctx::recentfile eq [list $TD/projA/a.sch]}

### B. Recent menu fill logic (on a scratch menu)
set tctx::recentfile [list $TD/projA/a.sch $TD/projB/b.sch]
set tctx::recentdirs [list $TD/projA]
catch {destroy .qom}
menu .qom -tearoff 0
file_dialog_fill_recent_menu .qom
check {B1 recent files listed with full-path labels} \
  {[.qom entrycget 0 -label] eq "$TD/projA/a.sch" &&
   [.qom entrycget 1 -label] eq "$TD/projB/b.sch"}
check {B2 separator between files and dirs} {[.qom type 2] eq {separator}}
check {B3 dirs deduped, trailing slash, file dirnames appended} \
  {[.qom entrycget 3 -label] eq "$TD/projA/" &&
   [.qom entrycget 4 -label] eq "$TD/projB/" && [.qom index end] == 4}
set tctx::recentfile {}
set tctx::recentdirs {}
file_dialog_fill_recent_menu .qom
check {B4 empty lists give single disabled placeholder} \
  {[.qom index end] == 0 && [.qom entrycget 0 -label] eq {(no recent files)} &&
   [.qom entrycget 0 -state] eq {disabled}}
# stale entries are skipped at post time (stored lists untouched)
set tctx::recentfile [list $TD/gone/missing.sch $TD/projA/a.sch \
  https://example.com/x.sch]
set tctx::recentdirs [list $TD/gone_dir $TD/projA]
file_dialog_fill_recent_menu .qom
# expect: a.sch, url, separator, projA/ (gone/missing.sch + gone_dir dropped,
# dirname of the stale file doesn't exist either, dirname of a.sch dedups)
check {B5 stale file and dir entries skipped, urls kept} \
  {[.qom entrycget 0 -label] eq "$TD/projA/a.sch" &&
   [.qom entrycget 1 -label] eq {https://example.com/x.sch} &&
   [.qom type 2] eq {separator} &&
   [.qom entrycget 3 -label] eq "$TD/projA/" && [.qom index end] == 3}
check {B6 filtering does not rewrite the stored lists} \
  {[llength $tctx::recentfile] == 3 && [llength $tctx::recentdirs] == 2}
# stale file whose parent dir still exists: dir offered, file not
file delete $TD/projB/b.sch
set tctx::recentfile [list $TD/projB/b.sch]
set tctx::recentdirs {}
file_dialog_fill_recent_menu .qom
check {B7 deleted file dropped but its existing dir still offered} \
  {[.qom index end] == 0 && [.qom entrycget 0 -label] eq "$TD/projB/"}
file copy -force $REPO/xschem_library/examples/LM5134A.sch $TD/projB/b.sch
# all entries stale -> placeholder
set tctx::recentfile [list $TD/gone/missing.sch]
set tctx::recentdirs [list $TD/gone_dir]
file_dialog_fill_recent_menu .qom
check {B8 all-stale lists give disabled placeholder} \
  {[.qom index end] == 0 && [.qom entrycget 0 -label] eq {(no recent files)} &&
   [.qom entrycget 0 -state] eq {disabled}}
destroy .qom

### C. dialog, load mode (loadfile == 1)
# T1: widget properties + Enter on absolute existing path
set ::probe1 {}
set INITIALLOADDIR $TD/projA
qo_drive {
  lappend ::probe1 [.load.buttons_bot.entry cget -takefocus]
  lappend ::probe1 [winfo exists .load.buttons_bot.recent]
  lappend ::probe1 [focus -lastfor .load]
  lappend ::probe1 [bind .load.buttons_bot.entry <Return>]
  .load.buttons_bot.entry delete 0 end
  .load.buttons_bot.entry insert 0 $TD/projA/a.sch
  file_dialog_entry_enter
}
set r [load_file_dialog {T1} {*} INITIALLOADDIR 1]
check {C1 File entry is focusable (no -takefocus 0)} {[lindex $::probe1 0] eq {}}
check {C2 Recent menubutton exists in load mode} {[lindex $::probe1 1] == 1}
check {C3 File entry has initial focus in load mode} \
  {[lindex $::probe1 2] eq {.load.buttons_bot.entry}}
check {C4 File entry has a Return binding} {[lindex $::probe1 3] ne {}}
check {C5 Enter on absolute existing file accepted as result} \
  {$r eq "$TD/projA/a.sch" && ![winfo exists .load]}

# T2: name relative to the browsed directory
set INITIALLOADDIR $TD/projA
qo_drive {
  .load.buttons_bot.entry delete 0 end
  .load.buttons_bot.entry insert 0 a.sch
  file_dialog_entry_enter
}
set r [load_file_dialog {T2} {*} INITIALLOADDIR 1]
check {C6 browsed-dir-relative name resolves} {$r eq "$TD/projA/a.sch"}

# T3: library-search-path-relative name (devices/nmos.sym style)
set ::saved_pathlist $pathlist
set pathlist [list $REPO/xschem_library]
set INITIALLOADDIR $TD
qo_drive {
  .load.buttons_bot.entry delete 0 end
  .load.buttons_bot.entry insert 0 devices/nmos.sym
  file_dialog_entry_enter
}
set r [load_file_dialog {T3} {*} INITIALLOADDIR 1]
set pathlist $::saved_pathlist
check {C7 pathlist-relative name resolves} \
  {$r eq "$REPO/xschem_library/devices/nmos.sym"}

# T4: cwd-relative name (browsed dir is elsewhere)
set ::old_pwd [pwd]
cd $TD
set INITIALLOADDIR $TD/projB
qo_drive {
  .load.buttons_bot.entry delete 0 end
  .load.buttons_bot.entry insert 0 projA/a.sch
  file_dialog_entry_enter
}
set r [load_file_dialog {T4} {*} INITIALLOADDIR 1]
cd $::old_pwd
check {C8 cwd-relative name resolves} {$r eq "$TD/projA/a.sch"}

# T5: directory navigation, nonexistent path, recent-pick of a directory
set tctx::recentfile {}
set tctx::recentdirs {}
set ::probe5 {}
set INITIALLOADDIR $TD
qo_drive {
  .load.buttons_bot.entry delete 0 end
  .load.buttons_bot.entry insert 0 $TD/projA
  file_dialog_entry_enter
  lappend ::probe5 [winfo exists .load] $file_dialog_dir1 \
    [.load.buttons_bot.entry get] \
    [expr {[lsearch -exact $file_dialog_files2 a.sch] >= 0}] \
    [lindex $tctx::recentdirs 0]
  set ::mb_calls {}
  .load.buttons_bot.entry delete 0 end
  .load.buttons_bot.entry insert 0 /no/such/file_qo_xyz.sch
  file_dialog_entry_enter
  lappend ::probe5 [winfo exists .load] [llength $::mb_calls]
  file_dialog_recent_pick $TD/projB
  lappend ::probe5 [winfo exists .load] $file_dialog_dir1
  .load.buttons_bot.cancel invoke
}
set r [load_file_dialog {T5} {*} INITIALLOADDIR 1]
check {C9 Enter on dir keeps dialog open, sets dir1, clears entry} \
  {[lindex $::probe5 0] == 1 && [lindex $::probe5 1] eq "$TD/projA" &&
   [lindex $::probe5 2] eq {}}
check {C10 Enter on dir refreshes file list} {[lindex $::probe5 3] == 1}
check {C11 Enter on dir records it in tctx::recentdirs} \
  {[lindex $::probe5 4] eq "$TD/projA"}
check {C12 nonexistent path: error popup, dialog stays open} \
  {[lindex $::probe5 5] == 1 && [lindex $::probe5 6] == 1}
check {C13 picking a recent directory navigates} \
  {[lindex $::probe5 7] == 1 && [lindex $::probe5 8] eq "$TD/projB"}
check {C14 cancel after navigation returns empty} {$r eq {}}

# T6: recent-pick of a file accepts and closes
set ::probe6 {}
set INITIALLOADDIR $TD
qo_drive {
  file_dialog_recent_pick $TD/projB/b.sch
  lappend ::probe6 [winfo exists .load]
}
set r [load_file_dialog {T6} {*} INITIALLOADDIR 1]
check {C15 picking a recent file accepts it and closes} \
  {$r eq "$TD/projB/b.sch" && [lindex $::probe6 0] == 0}

### D. other modes must not regress
# T7: save-as (loadfile == 0)
set ::probe7 {}
set INITIALSAVEDIR $TD
qo_drive {
  lappend ::probe7 [winfo exists .load.buttons_bot.recent]
  .load.buttons_bot.entry delete 0 end
  .load.buttons_bot.entry insert 0 newfile_qo.sch
  file_dialog_entry_enter
}
set r [load_file_dialog {T7} {*} INITIALSAVEDIR 0 1 initial.sch]
check {D1 save mode: no Recent button} {[lindex $::probe7 0] == 0}
check {D2 save mode: nonexistent new name still accepted} \
  {$r eq "$TD/newfile_qo.sch"}

# T8: insert symbol (loadfile == 2), non-blocking
set INITIALINSTDIR $TD
load_file_dialog {T8} {*} INITIALINSTDIR 2
check {D3 insert mode: dialog open, no Recent button} \
  {[winfo exists .load] && ![winfo exists .load.buttons_bot.recent]}
.load.buttons_bot.entry delete 0 end
.load.buttons_bot.entry insert 0 $TD/projA/a.sch
file_dialog_entry_enter
check {D4 insert mode: Enter on a file does not close (old behavior)} \
  {[winfo exists .load]}
.load.buttons_bot.entry delete 0 end
.load.buttons_bot.entry insert 0 $TD/projB
file_dialog_entry_enter
check {D5 insert mode: Enter on a dir navigates} \
  {[winfo exists .load] && $file_dialog_dir1 eq "$TD/projB"}
.load.buttons_bot.cancel invoke
