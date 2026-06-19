# TC12 (R19) — bus rubber-band: a labeled bus wire stretches like TC2 with its
# lab= preserved.
source [file join [file dirname [info script]] fixtures.tcl]
we_reset 1 1
we_device 0 0                ;# pin M (0,30)
we_wire 0 30 0 130 {lab=A[3:0]}
xschem unselect_all; xschem select instance 0
we_move_stretch 0 40
check "TC12 bus wire stretched to (0,70)-(0,130)" [has_seg 0 70 0 130]
check "TC12 lab=A\[3:0\] preserved on the wire" \
  [expr {[xschem getprop wire 0 lab] eq {A[3:0]}}]
we_result
