# B9: Cadence-style hierarchy walk-up on close/quit. Spec: descend_hierarchy_in_memory.md
#
# Run TRUE HEADLESS from the repo root:
#   src/xschem --nogui --pipe -q --nolog --script tests/headless/test_hier_walkup.tcl
#
# hierarchy_close walks UP the descend stack, prompting per dirty level (go_back's
# own Save/No/Cancel), then handles the top level, and returns 1 (proceed) / 0
# (cancel). This pins that logic with a stubbed ask_save (the real dialog is GUI).
# Scenario per the bug report: edit T, descend+edit M, descend into B (B clean).

set work /tmp/b9_walkup_work
file delete -force $work; file mkdir $work

set ::fails 0
proc check {name ok} { puts "[expr {$ok ? {ok:  } : {FAIL:}}] $name"; flush stdout; if {!$ok} {incr ::fails} }
proc result {} { puts [expr {$::fails==0 ? {RESULT: ALL PASS} : "RESULT: $::fails FAILED"}]; flush stdout; exit [expr {$::fails!=0}] }

# Build a 3-level hierarchy: top -> x1(mid) -> x1(bot)
proc subsym {path} {
  set fp [open $path w]
  puts $fp "v {xschem version=3.4.4 file_version=1.2}"
  puts $fp "G {type=subcircuit\ntemplate=\"name=x1\"}"
  puts $fp "V {}"; puts $fp "S {}"; puts $fp "E {}"
  puts $fp "B 5 -2.5 -2.5 2.5 2.5 {name=A dir=inout}"
  puts $fp "T {@symname} -20 -34 0 0 0.2 0.2 {}"
  close $fp
}
proc sch_with_inst {path sym} {
  set fp [open $path w]
  puts $fp "v {xschem version=3.4.4 file_version=1.2}"
  puts $fp "G {}"; puts $fp "V {}"; puts $fp "S {}"; puts $fp "E {}"
  if {$sym ne {}} { puts $fp "C {$sym} 0 0 0 0 {name=x1}" }
  close $fp
}
subsym $work/mid.sym
subsym $work/bot.sym
sch_with_inst $work/top.sch mid.sym
sch_with_inst $work/mid.sch bot.sym
sch_with_inst $work/bot.sch {}
set XSCHEM_LIBRARY_PATH "$work"

# Configurable ask_save stub: return whatever ::answer is set to (yes|no|{}).
set ::answer yes
set ::asks 0
proc ask_save {{msg {}} {cancel 1}} { incr ::asks; return $::answer }

# Drive: edit T, descend+edit M, descend into B (clean).
proc setup_TMB {} {
  global work
  foreach c {top mid bot} { file delete -force $work/$c~.sch }
  xschem load $work/top.sch
  xschem wire 200 300 300 300                 ;# edit T -> top~.sch
  xschem unselect_all; xschem select instance 0; xschem descend   ;# into M
  xschem wire 200 300 300 300                 ;# edit M -> mid~.sch
  xschem unselect_all; xschem select instance 0; xschem descend   ;# into B (no edit)
}

# ---- case 1: SAVE everything ----
setup_TMB
check "setup: at B, currsch=2, B clean" [expr {[xschem get currsch]==2 && [xschem get modified]==0}]
check "setup: T and M backups exist" [expr {[file exists $work/top~.sch] && [file exists $work/mid~.sch]}]
set ::answer yes; set ::asks 0
set r [hierarchy_close quit]
check "save-all: returned proceed=1" [expr {$r==1}]
check "save-all: walked up to top (currsch=0)" [expr {[xschem get currsch]==0}]
check "save-all: M backup removed (saved)" [expr {![file exists $work/mid~.sch]}]
check "save-all: T backup removed (saved)" [expr {![file exists $work/top~.sch]}]
check "save-all: top clean after save" [expr {[xschem get modified]==0}]

# ---- case 2: DISCARD everything ----
setup_TMB
set ::answer no; set ::asks 0
set r [hierarchy_close quit]
check "discard-all: returned proceed=1" [expr {$r==1}]
check "discard-all: at top (currsch=0)" [expr {[xschem get currsch]==0}]
check "discard-all: M backup removed (discarded, no lingering ~)" [expr {![file exists $work/mid~.sch]}]
check "discard-all: T backup removed (discarded, no lingering ~)" [expr {![file exists $work/top~.sch]}]

# ---- case 3: CANCEL aborts ----
setup_TMB
set ::answer {}; set ::asks 0
set r [hierarchy_close quit]
check "cancel: returned proceed=0 (abort)" [expr {$r==0}]
check "cancel: prompt was shown (M is lowest dirty level)" [expr {$::asks >= 1}]
check "cancel: did NOT walk all the way up (still descended)" [expr {[xschem get currsch] > 0}]

result
