# TC9 (R12, RED today) — move-orphaned dangling stub removed: a degree-1 stub on no
# pin (a bad2-style residue) should be cleaned up (Phase 5, move-scoped removal).
# Baseline: nothing removes it yet.
source [file join [file dirname [info script]] fixtures.tcl]
we_reset 1 1
we_wire 1360 -900 1360 -870  ;# degree-1 stub, both ends on nothing
check "TC9 orphaned stub removed" [expr {[nwires] == 0}]
we_result
