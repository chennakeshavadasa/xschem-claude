# TC11 (R16, guard) — two nets, no over-grab: moving net A must not grab the
# distinct net B that sits 20 units away. Guards Phase 2's tolerance against
# over-grabbing.
source [file join [file dirname [info script]] fixtures.tcl]
we_reset 1 1
we_device 0 0                ;# pin M (0,30) -> net A
we_wire 0 30 0 130           ;# net A on pin M
we_wire 20 30 20 130         ;# net B, 20 units away, distinct
xschem unselect_all; xschem select instance 0
we_move_stretch 20 0         ;# pin lands at (20,30)
check "TC11 net B wire NOT grabbed (still (20,30)-(20,130))" [has_seg 20 30 20 130]
we_result
