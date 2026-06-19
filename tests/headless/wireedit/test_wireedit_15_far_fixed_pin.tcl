# TC15 (R18, guard) — far end on a FIXED pin must stay connected: move only the
# near device; a jog should appear so the far end stays on the fixed pin.
source [file join [file dirname [info script]] fixtures.tcl]
we_reset 1 1
we_device 0 0                ;# inst0 MOVING, pin M (0,30)
we_device 0 160              ;# inst1 FIXED, pin P (0,130)
we_wire 0 30 0 130           ;# between the two pins (perpendicular to an x-move)
xschem unselect_all; xschem select instance 0   ;# move ONLY inst0
we_move_stretch 40 0
check "TC15 moved end reaches new pin (40,30)" [has_endpoint 40 30]
check "TC15 far end stays on the fixed pin (0,130)" [has_endpoint 0 130]
we_result
