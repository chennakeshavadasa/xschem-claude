# TC7 (R10, Phase 5) — colinear degree-2 merge: two colinear wires meeting at a free
# degree-2 point should tidy into one wire via the release-time cleanup that runs at
# the end of a STRETCH move (Issue D3). Per the plan (option A) the fixture builds the
# residue then performs a stretch move so the in-gesture cleanup fires; it runs
# regardless of the autotrim_wires preference (autotrim left OFF here on purpose).
source [file join [file dirname [info script]] fixtures.tcl]
we_reset 1 1
we_wire 0 0 100 0
we_wire 100 0 200 0          ;# colinear, meet at free point (100,0)
# trigger the stretch-move release cleanup (no-op move; the merge is what we assert)
xschem select wire 0
we_move_stretch 0 0
check "TC7 merged into one wire (0,0)-(200,0)" \
  [expr {[nwires] == 1 && [has_seg 0 0 200 0]}]
we_result
