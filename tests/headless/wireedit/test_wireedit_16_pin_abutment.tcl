# TC16 (Issue H, RED on the drag path) — pin-to-pin abutment generates a wire.
# Two device pins are placed DIRECTLY coincident (abutted, no wire between them):
# moving one instance must GENERATE a wire so the pins stay connected.
#
# The mechanism (connect_by_kissing) exists and is proven below via the `kissing`
# move; the plain/stretch drag path (and the cadence_compat plain-drag) do NOT call
# it yet -> RED. Phase 3 routes the drag through connect_by_kissing.
source [file join [file dirname [info script]] fixtures.tcl]
we_reset 1 1
we_device 0 0                ;# dev0: pin M (0,30)
we_device 0 60               ;# dev1: pin P (0,30)  -> abutted to dev0.M, NO wire
check "TC16 starts with no wire (pure pin abutment)" [expr {[nwires] == 0}]

# DESIRED: a plain stretch move (the intuitive / cadence plain-drag path) keeps the
# connection by generating a wire from the fixed pin (0,30) to the moved pin (40,30).
xschem unselect_all; xschem select instance 0
we_move_stretch 40 0
check "TC16 abutment preserved by a generated wire (0,30)-(40,30)" [has_seg 0 30 40 30]
check "TC16 exactly one connecting wire" [expr {[nwires] == 1}]
we_result
