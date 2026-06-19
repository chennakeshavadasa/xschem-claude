# TC13 (R5, guard) — multi-component rigid move: select both devices + the wire
# joining them, move; the wire translates rigidly (both ends move, 1 segment).
source [file join [file dirname [info script]] fixtures.tcl]
we_reset 1 1
we_device 0 0                ;# inst0, pin M (0,30)
we_device 0 200              ;# inst1, pin P (0,170)
we_wire 0 30 0 170           ;# joins the two pins
xschem unselect_all
xschem select instance 0
xschem select instance 1
xschem select wire 0
we_move 40 0                 ;# rigid move of the whole selection
check "TC13 wire translated rigidly to (40,30)-(40,170)" [has_seg 40 30 40 170]
check "TC13 one wire (no jog)" [expr {[nwires] == 1}]
we_result
