# Proves keyboard shortcuts are genuinely DATA-DRIVEN: change an action's accel
# in the table and the live binding follows it (old key released, new key runs
# the action). Run under X with --pipe:
#   DISPLAY=:0 ./src/xschem --pipe --script tests/headless/test_remap.tcl
update idletasks
focus -force .drw
update idletasks

set fail 0
proc check {name ok detail} {
  global fail
  if {$ok} { puts "ok:   $name $detail" } else { puts "FAIL: $name $detail"; incr fail }
}

# Default state: zoom-in is Shift+Z -> <Shift-Key-Z>; Ctrl+Shift+Z is unused.
check "default Shift+Z bound"    [expr {[bind .drw <Shift-Key-Z>] ne {}}] {}
check "Ctrl+Shift+Z free before" [expr {[bind .drw <Control-Shift-Key-Z>] eq {}}] {}

# Remap zoom-in to Ctrl+Shift+Z via the table, then re-install bindings.
set seq [remap_action_accel view.zoom_in {Ctrl+Shift+Z}]
check "remap returns new seq" [expr {$seq eq {<Control-Shift-Key-Z>}}] "(=> $seq)"

# The old key is released (reverts to C), the new key carries zoom_in.
check "old Shift+Z released"   [expr {[bind .drw <Shift-Key-Z>] eq {}}] {}
set nb [bind .drw <Control-Shift-Key-Z>]
check "new key bound to zoom_in" [expr {[string first {xschem zoom_in} $nb] >= 0}] "(=> $nb)"

# And pressing the new key actually zooms in (same view_zoom ratio as before).
set z0 [xschem get zoom]
event generate .drw <Control-Shift-Key-Z> ; update idletasks
set z1 [xschem get zoom]
check "new key zooms in" [expr {$z1 < $z0}] "(z0=$z0 z1=$z1)"

# Restore the default so later runs / windows are unaffected.
remap_action_accel view.zoom_in {Shift+Z}
check "restored Shift+Z" [expr {[bind .drw <Shift-Key-Z>] ne {} && [bind .drw <Control-Shift-Key-Z>] eq {}}] {}

if {$fail == 0} { puts "RESULT: ALL PASS" } else { puts "RESULT: $fail FAILED" }
flush stdout
exit [expr {$fail == 0 ? 0 : 1}]
