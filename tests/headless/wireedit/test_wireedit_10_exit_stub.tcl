# TC10 (Issue E, RED today) — exit-stub preserved: after the corner-slide move, a
# one-grid stub should leave pin M along its exit direction before the first bend
# (the "dream", desired1). Same geometry as TC6, move (0,30).
source [file join [file dirname [info script]] fixtures.tcl]
we_reset 1 1
we_device 1360 -930          ;# pin M (1360,-900)
we_wire 1270 -900 1360 -900  ;# stub
we_wire 1270 -900 1270 -680  ;# riser
we_wire 1110 -680 1270 -680  ;# rail
xschem unselect_all; xschem select instance 0
we_move_stretch 0 30
# pin M now (1360,-870); a one-minor-grid (10) stub straight out along x
check "TC10 exit stub out of pin M (1360,-870)-(1350,-870)" \
  [expr {[has_seg 1360 -870 1350 -870] || [has_seg 1360 -870 1370 -870]}]
we_result
