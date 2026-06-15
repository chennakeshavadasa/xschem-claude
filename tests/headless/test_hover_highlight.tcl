# Hover ("awareness") highlight — issue feature/hover-highlight.
# When the tracking cursor is over an object the editor outlines it (mild dashed
# yellow, min weight, config-controlled). This proves the DETECTION + STATE that
# drives the outline, through the REAL motion callback (xschem callback .drw 6 …):
#   - a motion over an object makes `xschem hover` report it (per type)
#   - a motion over empty space clears it
#   - the master enable (hover_highlight) gates it
#   - an active gesture (ui_state != 0) suppresses it (it is an idle cue)
#   - the config vars exist with the ratified defaults (on; min width; yellow)
# Focus-independence + the actual pixels (dash/color/weight) are a MANUAL EYEBALL
# item (WSLg can't drive a real unfocused-window pointer). Decision doc:
# code_analysis/hover_highlight_decision.md.
#
# Run under X with --pipe:
#   DISPLAY=:0 ./src/xschem --pipe -q --script tests/headless/test_hover_highlight.tcl
update idletasks
focus -force .drw
update idletasks

set fail 0
proc check {name ok detail} {
  global fail
  if {$ok} { puts "ok:   $name $detail" } else { puts "FAIL: $name $detail"; incr fail }
}

set MOTION 6     ;# MotionNotify
set BP 4         ;# ButtonPress
set BR 5         ;# ButtonRelease
set B3 3         ;# Button3
set B3MASK 1024  ;# Button3Mask

# send a plain motion to the SCHEMATIC point (sx,sy): convert to screen coords via
# the live transform (X_TO_XSCHEM(mx)=mx*zoom-xorigin  =>  mx=(sx+xorigin)/zoom).
proc motion_to {sx sy} {
  global MOTION
  set xo [xschem get xorigin]; set yo [xschem get yorigin]; set z [xschem get zoom]
  set mx [expr {int(($sx + $xo) / $z)}]
  set my [expr {int(($sy + $yo) / $z)}]
  xschem callback .drw $MOTION $mx $my 0 0 0 0
  update idletasks
}
# the hovered object's type, or "" if none / command absent (RED phase)
proc hov_type {} {
  if {[catch {xschem hover} r]} { return "<no-cmd>" }
  if {$r eq ""} { return "" }
  return [dict get $r type]
}

# --- fixture: a wire with EXACT geometry + one instance ---------------------
xschem set modified 0
xschem clear force schematic
xschem instance res.sym 0 0 0 0 {name=R1 value=1k}
xschem wire 100 100 300 100
xschem zoom_full
update idletasks

# --- HV6 (defaults FIRST, before we touch the var) --------------------------
check "HV6a hover_highlight defaults ON" \
  [expr {[catch {xschem get hover_highlight} v]==0 && $v==1} ] \
  "(=> [catch {xschem get hover_highlight} v; set v])"
check "HV6b hover_highlight_width var exists (min default)" \
  [expr {[catch {set ::hover_highlight_width}]==0}] {}
check "HV6c hover_highlight_color var exists (yellow default)" \
  [expr {[catch {set ::hover_highlight_color}]==0}] {}

# enable explicitly for the behavior tests
catch {xschem set hover_highlight 1}

# --- HV1 — motion over the wire midpoint reports the wire -------------------
motion_to 200 100
check "HV1 hover over a wire reports it" [expr {[hov_type] eq "wire"}] "(=> [hov_type])"

# --- HV2 — motion over empty space clears the hover -------------------------
motion_to 5000 5000
check "HV2 hover over empty space is cleared" [expr {[hov_type] eq ""}] "(=> [hov_type])"

# --- HV5 — instances hover too (D3: all drawable types) ---------------------
xschem unselect_all
xschem select instance R1
set bb [xschem get bbox_selected]   ;# {x1 y1 x2 y2} schematic
xschem unselect_all
set cx [expr {([lindex $bb 0] + [lindex $bb 2]) / 2.0}]
set cy [expr {([lindex $bb 1] + [lindex $bb 3]) / 2.0}]
motion_to $cx $cy
check "HV5 hover over an instance reports it" [expr {[hov_type] eq "instance"}] "(=> [hov_type])"

# --- HV3 — master enable gates detection ------------------------------------
catch {xschem set hover_highlight 0}
motion_to 200 100
check "HV3 disabled (hover_highlight 0) reports nothing" [expr {[hov_type] eq ""}] "(=> [hov_type])"
catch {xschem set hover_highlight 1}

# --- HV4 — an active gesture suppresses the idle hover cue -------------------
# start a button3 zoom-rect gesture (sets ui_state), then move over the wire.
set xo [xschem get xorigin]; set yo [xschem get yorigin]; set z [xschem get zoom]
set px [expr {int((400 + $xo) / $z)}]; set py [expr {int((400 + $yo) / $z)}]
xschem callback .drw $BP $px $py 0 $B3 0 0; update idletasks
motion_to 200 100
check "HV4 active gesture suppresses hover" [expr {[hov_type] eq ""}] "(=> [hov_type], ui_state=[xschem get ui_state])"
# end the gesture
set qx [expr {int((420 + $xo) / $z)}]; set qy [expr {int((420 + $yo) / $z)}]
xschem callback .drw $BR $qx $qy 0 $B3 $B3MASK 0; update idletasks

if {$fail == 0} { puts "RESULT: ALL PASS" } else { puts "RESULT: $fail FAILED" }
flush stdout
exit [expr {$fail == 0 ? 0 : 1}]
