# TC4 (Issue B, RED today) — sub-grid endpoint follows: near end is 1 unit off the
# pin; a stretch move should still carry it (tolerant match, Phase 2).
source [file join [file dirname [info script]] fixtures.tcl]
we_reset 1 1
we_device 0 0                ;# pin M (0,30)
we_wire 0 31 0 131           ;# near end (0,31): 1 unit off pin M
xschem unselect_all; xschem select instance 0
we_move_stretch 0 40
check "TC4 near endpoint follows to (0,71)" [has_seg 0 71 0 131]
check "TC4 nothing left at the old (0,31)" [expr {![has_endpoint 0 31]}]
we_result
