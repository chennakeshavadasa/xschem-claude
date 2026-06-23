# descend_readonly: descending opens the child schematic READ-ONLY by default when
# the flag is set (Cadence browse mode), editable otherwise; ascending restores the
# parent's own mode; "Descend (edit)" / set-readonly-0 overrides. specs: actions.c
# descend_schematic(), utils/cadence_nav.tcl.
#
# Run TRUE HEADLESS from the repo root:
#   src/xschem --nogui --pipe -q --nolog --script tests/headless/test_descend_readonly.tcl

set fixdir [file normalize [file join [file dirname [info script]] fixtures descend]]
set work /tmp/dro_work
file delete -force $work; file mkdir $work
foreach fn {descend_parent.sch descend_child.sch descend_child.sym} {
  file copy -force $fixdir/$fn $work/$fn   ;# writable copy: readonly reflects the flag, not file perms
}
if {![info exists XSCHEM_LIBRARY_PATH]} { set XSCHEM_LIBRARY_PATH {} }
set XSCHEM_LIBRARY_PATH "$work:$fixdir:$XSCHEM_LIBRARY_PATH"

set fails 0
proc check {name ok detail} {
  puts "[expr {$ok ? {ok:  } : {FAIL:}}] $name $detail"; flush stdout
  if {!$ok} {incr ::fails}
}

# descend into the child and report (child name, child readonly), leaving us in the child
proc descend_child {flag} {
  global work
  set ::descend_readonly $flag
  xschem load $work/descend_parent.sch
  xschem unselect_all; xschem select instance 0
  xschem descend
  return [list [file tail [xschem get schname]] [xschem get readonly]]
}

# DRO1 — flag off: descend stays editable (the child file is writable)
lassign [descend_child 0] ch ro
check "DRO1 descend_readonly=0 -> child editable" \
  [expr {$ch eq "descend_child.sch" && $ro == 0}] "(child=$ch ro=$ro)"
xschem go_back

# DRO2 — flag on: descend opens the child READ-ONLY
lassign [descend_child 1] ch ro
check "DRO2 descend_readonly=1 -> child read-only" \
  [expr {$ch eq "descend_child.sch" && $ro == 1}] "(child=$ch ro=$ro)"

# DRO3 — ascending restores the parent's own (writable) mode, not the forced RO
xschem go_back
check "DRO3 go_back restores the parent's editable mode" \
  [expr {[file tail [xschem get schname]] eq "descend_parent.sch" && [xschem get readonly] == 0}] \
  "(parent ro=[xschem get readonly])"

# DRO4 — "Descend (edit)" override: descend read-only, then force editable
descend_child 1
xschem set readonly 0
check "DRO4 forcing readonly 0 after a read-only descend makes it editable" \
  [expr {[xschem get readonly] == 0}] "(ro=[xschem get readonly])"

puts [expr {$fails == 0 ? "RESULT: ALL PASS" : "RESULT: $fails FAILED"}]
flush stdout
exit [expr {$fails != 0}]
