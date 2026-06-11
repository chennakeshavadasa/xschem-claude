# Integration smoke for the CIW (Command Interpreter Window, src/ciw.tcl) and
# the log_action CIW mirror / `xschem log_action` plumbing.
# Run under X with --pipe; pass --logdir so the log file lands in a temp dir:
#   DISPLAY=:0 ./src/xschem --pipe -q --logdir $(mktemp -d) \
#       --script tests/headless/test_ciw.tcl
update idletasks

proc check {name ok} {
  puts "[expr {$ok ? {ok:  } : {FAIL:}}] $name"
  if {!$ok} {incr ::fails}
}
set ::fails 0

# 1) the CIW auto-opened at startup: panedwindow, read-only log pane, entry
check "CIW toplevel exists"      [winfo exists .ciw]
check "panedwindow split"        [expr {[winfo exists .ciw.p] && [winfo class .ciw.p] eq {Panedwindow}}]
check "log pane is a text"       [expr {[winfo exists .ciw.l.t] && [winfo class .ciw.l.t] eq {Text}}]
check "log pane is read-only"    [expr {[.ciw.l.t cget -state] eq {disabled}}]
check "entry pane exists"        [expr {[winfo exists .ciw.c.e] && [winfo class .ciw.c.e] eq {Entry}}]

# 2) the action log is open (interactive session) and its path is queryable
set logf [xschem get actionlog_filename]
check "actionlog_filename set"   [expr {$logf ne {}}]

# 3) C mirror: an xschem log_action line lands in the pane (file checked below)
xschem log_action {xschem zoom_full}
update idletasks
set pane [.ciw.l.t get 1.0 end]
check "log_action mirrored to pane" [expr {[string first {xschem zoom_full} $pane] >= 0}]

# 4) mirror is substitution-safe: braces / brackets / $ pass through verbatim
set tricky {# marker {with braces} $dollar [brackets]}
xschem log_action $tricky
set pane [.ciw.l.t get 1.0 end]
check "tricky line verbatim in pane" [expr {[string first $tricky $pane] >= 0}]

# 5) typed command: echoed input-tagged, result shown result-tagged, entry cleared
.ciw.c.e insert 0 { xschem get instances }
ciw_exec
set pane [.ciw.l.t get 1.0 end]
check "typed cmd echoed with > prefix" [expr {[string first {> xschem get instances} $pane] >= 0}]
check "input tag used"             [expr {[llength [.ciw.l.t tag ranges input]] > 0}]
check "result tag used"            [expr {[llength [.ciw.l.t tag ranges result]] > 0}]
check "entry cleared after exec"   [expr {[.ciw.c.e get] eq {}}]

# 6) error path: error text shown error-tagged
.ciw.c.e insert 0 {this_is_not_a_command}
ciw_exec
set pane [.ciw.l.t get 1.0 end]
check "error text shown"           [expr {[string first {invalid command name} $pane] >= 0}]
check "error tag used"             [expr {[llength [.ciw.l.t tag ranges error]] > 0}]

# 7) the file: header, log_action lines, raw typed command (no "> ", no result),
#    failed command as '# failed:' comment -- the whole file stays source-able
set fd [open $logf r]
set body [read $fd]
close $fd
set lines [split [string trimright $body \n] \n]
check "file header comment"        [expr {[string match {# xschem action log*} [lindex $lines 0]]}]
check "log_action line in file"    [expr {[lsearch -exact $lines {xschem zoom_full}] >= 0}]
check "tricky line verbatim in file" [expr {[lsearch -exact $lines $tricky] >= 0}]
check "typed cmd recorded raw"     [expr {[lsearch -exact $lines {xschem get instances}] >= 0}]
check "failed cmd is a comment"    [expr {[lsearch -exact $lines {# failed: this_is_not_a_command}] >= 0}]
check "no echo prefix in file"     [expr {[lsearch -glob $lines {> *}] < 0}]
check "no result/error text in file" [expr {[string first {invalid command name} $body] < 0}]
# source-ability: every line must be a comment or a known-good command here,
# so replaying the file into this same interpreter must not error
check "file is source-able"        [expr {![catch {uplevel #0 [list source $logf]} err]}]

# 8) closing the CIW withdraws (xschem survives); ciw_create re-shows it
eval [wm protocol .ciw WM_DELETE_WINDOW]
update idletasks
check "close withdraws, not destroys" [expr {[winfo exists .ciw] && [wm state .ciw] eq {withdrawn}}]
ciw_create
update idletasks
check "ciw_create re-shows"        [expr {[wm state .ciw] eq {normal}}]

puts [expr {$::fails == 0 ? "RESULT: ALL PASS" : "RESULT: $::fails FAILED"}]
flush stdout
exit [expr {$::fails != 0}]
