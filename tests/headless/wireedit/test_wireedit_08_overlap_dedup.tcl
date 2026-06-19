# TC8 (R11, RED today) — duplicate/overlap removal: a wire fully included in another
# should be removed, leaving one copy (Phase 5).
source [file join [file dirname [info script]] fixtures.tcl]
we_reset 1 1
we_wire 0 0 100 0
we_wire 0 0 60 0             ;# included in the first
check "TC8 included duplicate removed, (0,0)-(100,0) remains" \
  [expr {[nwires] == 1 && [has_seg 0 0 100 0]}]
we_result
