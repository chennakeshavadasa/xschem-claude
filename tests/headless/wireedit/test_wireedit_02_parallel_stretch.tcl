# TC2 (control, must already pass) — parallel stretch along the wire.
source [file join [file dirname [info script]] fixtures.tcl]
we_reset 1 1                 ;# enable_stretch + orthogonal_wiring ON
we_device 0 0                ;# pin M (0,30)
we_wire 0 30 0 130           ;# vertical, on pin M
xschem unselect_all; xschem select instance 0
we_move_stretch 0 40         ;# move along the wire
check "TC2 wire stretched to (0,70)-(0,130)" [has_seg 0 70 0 130]
check "TC2 one wire (no new segment)" [expr {[nwires] == 1}]
we_result
