# TC7 (R10, RED today) — colinear degree-2 merge: two colinear wires meeting at a
# free degree-2 point should tidy into one wire (Phase 5).
source [file join [file dirname [info script]] fixtures.tcl]
we_reset 1 1
we_wire 0 0 100 0
we_wire 100 0 200 0          ;# colinear, meet at free point (100,0)
check "TC7 merged into one wire (0,0)-(200,0)" \
  [expr {[nwires] == 1 && [has_seg 0 0 200 0]}]
we_result
