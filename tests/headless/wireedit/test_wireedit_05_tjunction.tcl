# TC5 (Issue C, RED today) — T-junction / mid-span connection follows: a wire runs
# THROUGH the pin mid-span; a stretch move should preserve the connection. Minimal
# acceptable: a vertical stub joining the old tap point to the new pin (Phase 3).
source [file join [file dirname [info script]] fixtures.tcl]
we_reset 1 1
we_device 0 0                ;# pin M (0,30)
we_wire -60 30 60 30         ;# horizontal, through pin M (0,30) mid-span
xschem unselect_all; xschem select instance 0
we_move_stretch 0 40
check "TC5 connection preserved to the new pin (0,70)" [has_endpoint 0 70]
check "TC5 a vertical stub joins tap (0,30) to pin (0,70)" [has_seg 0 30 0 70]
we_result
