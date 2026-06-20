# TC17 (Issue 0014) — dragging a WIRE that meets a perpendicular wire at a junction
# must NOT drag the perpendicular wire (or its further-connected segments) along.
# The Phase-4 corner-slide only applies to stretches driven by a moving INSTANCE pin,
# not to wire-wire junctions, so a wire-drag leaves the junction anchored.
#
# Fixture = the user's "reverse-C": two left arms, a vertical spine V (autotrim
# splits it at the T-junction J into two halves, each ending at J), and a right prong
# H meeting V at its midpoint J=(0,0). Dragging H away from J must keep V and both
# arms fixed and only stretch H.
source [file join [file dirname [info script]] fixtures.tcl]
we_reset 1 1
uplevel #0 {set autotrim_wires 1}    ;# cadence_compat bundles this; it splits V at J
we_wire -40 40 0 40                  ;# top arm
we_wire 0 40 0 -40                   ;# spine V -> autotrim splits at J=(0,0)
we_wire -40 -40 0 -40                ;# bottom arm
we_wire 0 0 40 0                     ;# H, J=(0,0) is V's MIDPOINT
xschem trim_wires
# grab H (full selection) and stretch it AWAY from J (+40 in x)
set hidx -1
for {set i 0} {$i < [nwires]} {incr i} {
  if {[we_norm [xschem wire_coord $i]] eq [we_norm {0 0 40 0}]} { set hidx $i }
}
xschem unselect_all; xschem select wire $hidx
we_move_stretch 40 0
check "TC17 spine top half stays at (0,0)-(0,40)"    [has_seg 0 0 0 40]
check "TC17 spine bottom half stays at (0,-40)-(0,0)" [has_seg 0 -40 0 0]
check "TC17 top arm unchanged (-40,40)-(0,40)"       [has_seg -40 40 0 40]
check "TC17 bottom arm unchanged (-40,-40)-(0,-40)"  [has_seg -40 -40 0 -40]
check "TC17 J stays put (nothing dragged the junction off (0,0))" \
  [expr {[has_endpoint 0 0]}]
check "TC17 H stretched to (0,0)-(80,0), anchored at J" [has_seg 0 0 80 0]
we_result
