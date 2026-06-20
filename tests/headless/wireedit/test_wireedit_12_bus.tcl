# TC12 (R19) — bus rubber-band: a bus wire stretches like a plain wire (TC2) and its
# persistent properties + net label survive the move.
#
# DESIGN NOTE (Phase 6 follow-up): the Phase-1 TC12 asserted that a wire's `lab=A[3:0]`
# token survives the move. That premise was WRONG — a bare wire's `lab` token is a
# WRITE-ONLY derived-net cache that `prepare_netlist_structs()` overwrites with the
# auto net name (`#net1`) on the first netlist prep, MOVE OR NOT (verified headlessly:
# `lab=A[3:0]` -> `lab=#net1` after `xschem resolved_net` with no move at all). So a
# wire's `lab` is not a thing that "survives" anything. The REAL bug Phase-1 stumbled
# on: a colinear stretch (V-H/H-V manhattan branch in place_moved_wire) degenerates the
# original wire to zero length and stores the surviving segment via storeobject(... NULL),
# wiping the wire's ENTIRE prop_ptr -> any persistent attribute (`bus=`, etc.) was lost.
# Fix: the jog/continuation segment inherits wire[n].prop_ptr (it is the same net). This
# test asserts that persistent property survival + a real net-label instance surviving.
source [file join [file dirname [info script]] fixtures.tcl]

# --- part 1: geometry follows + persistent `bus=` attribute survives --------------------
we_reset 1 1
we_device 0 0                       ;# pin M (0,30)
we_wire 0 30 0 130 {bus=4}          ;# a bus wire on pin M (bus=4 is a persistent attr)
check "TC12 bus=4 present before move" [expr {[xschem getprop wire 0 bus] eq {4}}]
xschem unselect_all; xschem select instance 0
we_move_stretch 0 40
check "TC12 bus wire stretched to (0,70)-(0,130)" [has_seg 0 70 0 130]
check "TC12 bus=4 attribute preserved across the move" \
  [expr {[xschem getprop wire 0 bus] eq {4}}]

# --- part 2: a real net-label instance survives the move (R19 "labels survive") ---------
we_reset 1 1
we_device 0 0
we_wire 0 30 0 130                  ;# wire on pin M, far end at (0,130)
we_label 0 130 NETBUS               ;# lab_pin.sym net label on the far end
check "TC12 wire is on net NETBUS before move" [expr {[we_net 0] eq {NETBUS}}]
xschem unselect_all; xschem select instance 0
we_move_stretch 0 40                ;# pin M -> (0,70); wire stretches, label stays put
check "TC12 wire stretched, label still names the net after move" \
  [expr {[has_seg 0 70 0 130] && [we_net 0] eq {NETBUS}}]

we_result
