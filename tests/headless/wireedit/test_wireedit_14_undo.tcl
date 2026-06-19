# TC14 (R17, guard) — undo restores geometry exactly after a stretch move.
source [file join [file dirname [info script]] fixtures.tcl]
we_reset 1 1
we_device 1360 -930          ;# pin M (1360,-900)
we_wire 1270 -900 1360 -900  ;# stub
we_wire 1270 -900 1270 -680  ;# riser
we_wire 1110 -680 1270 -680  ;# rail
set before [segset]
xschem unselect_all; xschem select instance 0
we_move_stretch 0 30
xschem undo
check "TC14 undo restores the exact wire set" [expr {[segset] eq $before}]
we_result
