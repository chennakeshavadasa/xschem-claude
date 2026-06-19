# TC3 (Issue D, desired) — perpendicular lone wire: move perpendicular to the wire;
# far end stays fixed, an L-jog appears (2 Manhattan segments).
source [file join [file dirname [info script]] fixtures.tcl]
we_reset 1 1
we_device 0 0                ;# pin M (0,30)
we_wire 0 30 0 130           ;# vertical; far end (0,130) free
xschem unselect_all; xschem select instance 0
we_move_stretch 40 0         ;# move perpendicular to the wire
check "TC3 two Manhattan segments (L-jog)" [expr {[nwires] == 2 && [all_manhattan]}]
check "TC3 a segment reaches the moved pin (40,30)" [has_endpoint 40 30]
check "TC3 far end (0,130) stays fixed" [has_endpoint 0 130]
we_result
