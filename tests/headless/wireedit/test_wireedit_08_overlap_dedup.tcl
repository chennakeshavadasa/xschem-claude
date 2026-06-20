# TC8 (R11, Phase 5) — duplicate/overlap removal: a wire fully included in another
# should be removed by the release-time cleanup that runs at the end of a STRETCH
# move (Issue D3), leaving one copy. Per the plan (option A) the fixture builds the
# residue then performs a stretch move so the in-gesture cleanup fires; the cleanup
# runs regardless of the autotrim_wires preference (autotrim left OFF here on purpose).
source [file join [file dirname [info script]] fixtures.tcl]
we_reset 1 1
we_wire 0 0 100 0
we_wire 0 0 60 0             ;# included in the first
# trigger the stretch-move release cleanup (no-op move; the dedup is what we assert)
xschem select wire 0
we_move_stretch 0 0
check "TC8 included duplicate removed, (0,0)-(100,0) remains" \
  [expr {[nwires] == 1 && [has_seg 0 0 100 0]}]
we_result
