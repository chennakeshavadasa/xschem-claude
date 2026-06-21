# Efficiency invariant for the in-memory descend snapshot.
# Spec: specs/descend_hierarchy_in_memory.md
#
# The full-schematic snapshot taken on descend is only ever CONSUMED by go_back
# when the parent had unsaved edits (a clean parent is restored from disk). So the
# snapshot must only be TAKEN when the parent is modified -- otherwise a plain
# browse down through an unmodified hierarchy would deep-copy each parent for
# nothing. `xschem get hier_slots` reports the number of live snapshots.
#
# Run: src/xschem --nogui --pipe -q --nolog --script tests/headless/test_descend_efficiency.tcl

set fixdir [file normalize [file join [file dirname [info script]] fixtures descend]]
if {![info exists XSCHEM_LIBRARY_PATH]} { set XSCHEM_LIBRARY_PATH {} }
set XSCHEM_LIBRARY_PATH "$fixdir:$XSCHEM_LIBRARY_PATH"

set ::f 0
proc ck {name ok} { puts "[expr {$ok ? {ok:  } : {FAIL:}}] $name"; if {!$ok} {incr ::f} }
proc ask_save {{c {}}} { return no }

# unmodified parent: descending must NOT snapshot (no wasted deep copy)
xschem load $fixdir/descend_parent.sch
xschem unselect_all; xschem select instance 0; xschem descend
ck "unmodified descend takes NO snapshot (hier_slots==0)" [expr {[xschem get hier_slots] == 0}]
xschem go_back

# modified parent: exactly one snapshot while descended, freed on return
xschem load $fixdir/descend_parent.sch
xschem wire 200 300 300 300
xschem unselect_all; xschem select instance 0; xschem descend
ck "modified descend takes ONE snapshot (hier_slots==1)" [expr {[xschem get hier_slots] == 1}]
xschem go_back
ck "snapshot freed after go_back (hier_slots==0)" [expr {[xschem get hier_slots] == 0}]

puts [expr {$::f == 0 ? "RESULT: ALL PASS" : "RESULT: $::f FAILED"}]
exit [expr {$::f != 0}]
