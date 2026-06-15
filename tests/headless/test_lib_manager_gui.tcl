# Phase 7a (library-manager) — headless smoke of the Library Manager tree wiring.
# Drives the real ttk::treeview logic (build + lazy expand) against the committed
# xschem_library_oa registry, asserting the tree populates Library -> Cell -> View
# correctly. Pixels / interaction remain a manual eyeball item.
#
# Run under X with --pipe from src/:
#   DISPLAY=:0 ./xschem --pipe -q --script ../tests/headless/test_lib_manager_gui.tcl

set fail 0
proc check {name ok detail} {
  global fail
  if {$ok} { puts "ok:   $name $detail" } else { puts "FAIL: $name $detail"; incr fail }
}
# child item of $parent whose -text is $txt, or "" if none
proc child_with_text {t parent txt} {
  foreach c [$t children $parent] { if {[$t item $c -text] eq $txt} { return $c } }
  return {}
}
proc texts {t parent} {
  set out {}; foreach c [$t children $parent] { lappend out [$t item $c -text] }
  return [lsort $out]
}

set repo [file normalize [file join [pwd] ..]]
set ::XSCHEM_LIBRARY_DEFS [file join $repo xschem_library_oa library.defs]

# build the window + tree
library_manager
update idletasks
set t .libmgr.f.t
check "GUI1 window + tree created" [winfo exists $t] {}

# top level = the registered libraries
set libs [texts $t {}]
check "GUI2 libraries at top level" [expr {[lsearch $libs devices] >= 0 && [lsearch $libs examples] >= 0}] \
  "(=> [llength $libs] libs)"

# expand 'devices' -> cells appear (lazy population via on_open)
set dev [child_with_text $t {} devices]
check "GUI3 devices node present" [expr {$dev ne {}}] {}
libmgr::on_open $dev
update idletasks
set devcells [texts $t $dev]
check "GUI4 devices expands to cells" [expr {[llength $devcells] > 20 && [lsearch $devcells res] >= 0}] \
  "(=> [llength $devcells] cells)"

# expand the 'res' cell -> its views appear
set resitem [child_with_text $t $dev res]
libmgr::on_open $resitem
update idletasks
check "GUI5 res expands to its view(s)" [expr {[lsearch [texts $t $resitem] symbol] >= 0}] \
  "(=> [texts $t $resitem])"

# selecting a view updates the status line; current_cell resolves it
$t focus $resitem
$t selection set $resitem
libmgr::on_select $t
check "GUI6 current_cell resolves selection" [expr {[libmgr::current_cell] eq {devices res}}] \
  "(=> [libmgr::current_cell])"

destroy .libmgr
if {$fail == 0} { puts "RESULT: ALL PASS" } else { puts "RESULT: $fail FAILED" }
flush stdout
exit [expr {$fail == 0 ? 0 : 1}]
