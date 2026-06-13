# Characterization tests for the INSTANCE (component) lifecycle — Phase A of
# the stable-object-handles step-2 work. These lock the CURRENT behavior as
# observed through the Tcl surface, so the upcoming lifecycle funnel refactor
# (route every instances++/--/= through one family in store.c) is provably
# behavior-identical. They must be green at every commit from Phase A on.
#
# Sourced by inst_wrap.tcl, which provides `check`, `xcheck`, `::qo_dir`.
#
# Lifecycle sites exercised (census: code_analysis/instance_lifecycle_census.md):
#   BIRTH place_symbol  -> CHI1 (xschem instance ...)
#   BIRTH load_inst     -> every reload
#   BIRTH move-copy     -> CHI4 (copy_objects)        [move.c:972]
#   BIRTH merge_inst    -> CHI5 (copy + paste)        [paste.c:312]
#   DEATH delete_objects-> CHI2 / CHI3                [select.c:582]
#   BULK_RESET clear    -> CHI10                      [actions.c:1073]
#   undo restore (both backends) -> CHI3 / CHI6
#   REORDER-SWAP change_elem_order -> CHI9            [editprop.c:1100]
# NOT covered (honest gaps, per green-but-hollow rule 4):
#   REORDER-SHIFT place_symbol pos>=0 — the `xschem instance` command
#   hardcodes pos=-1, so the positional-insert shift is unreachable from Tcl.
#
# Conventions (same as the wire suite):
#   - All edits on /tmp/sh_inst_fixture.sch (a copy) — never the repo file.
#   - `xschem set modified 0` before every load (dodges the save-prompt modal).
#   - The instance snapshot is PLACEMENT-ONLY (symbol + x y rot flip) and
#     SORTED: the *set* of instances is the behavior we preserve; array order
#     is an implementation detail already unstable today (CHI7) and the funnel
#     must stay free to change it. Property drift is covered separately by the
#     byte-compare checks (CHI6).

### stub every modal dialog BEFORE any code path can reach one
rename tk_messageBox _real_tk_messageBox
proc tk_messageBox {args} {return ok}
rename tk_getOpenFile _real_tk_getOpenFile
proc tk_getOpenFile {args} {return {}}
catch {rename alert_ _real_alert_}
proc alert_ {args} {return 1}

### fixture: a /tmp copy of the 117-instance example
set REPO [file normalize $::qo_dir/../..]
set FIX /tmp/sh_inst_fixture.sch
file copy -force $REPO/xschem_library/examples/mos_power_ampli.sch $FIX

proc reload {} {
  global FIX
  xschem set modified 0
  xschem load $FIX
}
proc ninst {} {return [xschem get instances]}
# 1 if instance <name> resolves, 0 if not (select returns "1"/"0", no error)
proc resolves {name} {
  xschem unselect_all
  set r [xschem select instance $name]
  xschem unselect_all
  return $r
}
# current array index of instance <name>, or -1 (via the selection enumerator)
proc idx_of {name} {
  xschem unselect_all
  if {[xschem select instance $name] == 0} { xschem unselect_all; return -1 }
  set row [lindex [xschem selection] 0]
  xschem unselect_all
  return [lindex $row 1]
}
# sorted, placement-only instance list (symbol + x y rot flip) from the saved
# .sch C-records. The C-record's first line is `C {sym} x y rot flip {prop...`;
# multi-line props continue on lines that do NOT start with "C ", so the
# regex over first-lines captures every instance's placement exactly once.
proc inst_snapshot {tag} {
  set f /tmp/sh_inst_snap_$tag.sch
  file delete -force $f
  xschem saveas $f schematic
  set fd [open $f r]; set data [read $fd]; close $fd
  set out {}
  foreach line [split $data \n] {
    if {[regexp {^C \{([^\}]*)\} (\S+) (\S+) (\S+) (\S+)} $line -> sym x y rot flip]} {
      lappend out "C {$sym} $x $y $rot $flip"
    }
  }
  return [lsort $out]
}
proc read_file {f} {
  set fd [open $f r]; set d [read $fd]; close $fd
  return $d
}
# content from the first "G {" record onward — skips the v{...} header, which
# memory undo is known not to round-trip (same quirk the wire suite locks)
proc body_after_header {f} {
  set lines [split [read_file $f] \n]
  set i [lsearch -glob $lines {G \{*}]
  return [join [lrange $lines $i end] \n]
}

### CHI1 — create an instance (BIRTH: place_symbol)
reload
set ::base_n [ninst]
set ::base_snap [inst_snapshot base]
check {CHI1pre fixture has 117 instances} \
  {$::base_n == 117 && [llength $::base_snap] == 117}
xschem unselect_all
xschem instance res.sym 3000 3000 0 0 {name=AAA}
check {CHI1a create: instance count +1} {[ninst] == $::base_n + 1}
set s1 [inst_snapshot chi1]
set diff {}
foreach l $s1 {if {[lsearch -exact $::base_snap $l] < 0} {lappend diff $l}}
check {CHI1b create: snapshot gains exactly the new instance placement} \
  {$diff eq {{C {res.sym} 3000 3000 0 0}} && [llength $s1] == $::base_n + 1}
check {CHI1c created instance resolves by name} {[resolves AAA] == 1}

### CHI2 — delete it (DEATH: delete_objects)
xschem unselect_all
xschem select instance AAA
xschem delete
check {CHI2a delete: count back to baseline} {[ninst] == $::base_n}
check {CHI2b delete: instance no longer resolves by name} {[resolves AAA] == 0}
check {CHI2c delete: snapshot equals baseline set} {[inst_snapshot chi2] eq $::base_snap}

### CHI3 — undo/redo round-trip, BOTH undo backends
foreach utype {disk memory} {
  reload
  xschem undo_type $utype
  xschem unselect_all
  xschem instance res.sym 3000 3000 0 0 {name=AAA}
  xschem unselect_all
  xschem select instance AAA
  xschem delete
  check "CHI3a ($utype) create+delete: baseline count" {[ninst] == $::base_n}
  xschem undo
  check "CHI3b ($utype) undo restores the deleted instance" \
    {[ninst] == $::base_n + 1 && [resolves AAA] == 1}
  xschem redo
  check "CHI3c ($utype) redo re-deletes" {[ninst] == $::base_n && [resolves AAA] == 0}
  xschem undo
  xschem undo
  check "CHI3d ($utype) full unwind: snapshot equals baseline" \
    {[ninst] == $::base_n && [inst_snapshot chi3_$utype] eq $::base_snap}
}

### CHI4 — copy as BIRTH (move_objects copy path): a duplicate is a new
### instance with a FRESH unique name; the original is untouched
reload
xschem unselect_all
xschem instance res.sym 3000 3000 0 0 {name=AAA}
xschem unselect_all
xschem select instance AAA
set before [ninst]
xschem copy_objects 500 0
check {CHI4a copy_objects: count +1} {[ninst] == $before + 1}
set newidx [expr {[ninst] - 1}]
set newrow [xschem instance_coord $newidx]
check {CHI4b the copy carries a FRESH name (not AAA) at the offset coords} \
  {[lindex $newrow 0] ne {AAA} && [lindex $newrow 0] ne {} && \
   [lindex $newrow 2] == 3500 && [lindex $newrow 3] == 3000}
check {CHI4c original AAA is unchanged and still resolves} \
  {[resolves AAA] == 1 && [string trim [xschem instance_coord AAA]] eq {{AAA} {res.sym} 3000 3000 0 0}}

### CHI5 — paste as BIRTH (merge_inst path): copy to clipboard + paste adds one
reload
xschem unselect_all
xschem instance res.sym 3000 3000 0 0 {name=AAA}
xschem unselect_all
xschem select instance AAA
set before [ninst]
xschem copy
xschem paste 600 0
check {CHI5 copy+paste (merge_inst): count +1} {[ninst] == $before + 1}

### CHI6 — whole-pipeline drift detector (byte-level)
reload
xschem saveas /tmp/sh_inst_save_clean1.sch schematic
reload
xschem saveas /tmp/sh_inst_save_clean2.sch schematic
check {CHI6a save is deterministic (two clean saves byte-identical)} \
  {[read_file /tmp/sh_inst_save_clean1.sch] eq [read_file /tmp/sh_inst_save_clean2.sch]}

reload
xschem undo_type disk
xschem unselect_all
xschem instance res.sym 3000 3000 0 0 {name=AAA}
xschem unselect_all
xschem select instance AAA
xschem delete
xschem undo
xschem undo
xschem saveas /tmp/sh_inst_save_disk.sch schematic
check {CHI6b disk-undo edit cycle: save byte-identical to clean save} \
  {[read_file /tmp/sh_inst_save_disk.sch] eq [read_file /tmp/sh_inst_save_clean1.sch]}

reload
xschem undo_type memory
xschem unselect_all
xschem instance res.sym 3000 3000 0 0 {name=AAA}
xschem unselect_all
xschem select instance AAA
xschem delete
xschem undo
xschem undo
xschem saveas /tmp/sh_inst_save_mem.sch schematic
check {CHI6c memory-undo edit cycle: save body identical from G record onward} \
  {[body_after_header /tmp/sh_inst_save_mem.sch] eq [body_after_header /tmp/sh_inst_save_clean1.sch]}

### CHI7 — THE identity characterization (the §2e analog for instances).
### Locks today's behavior: an instance's array INDEX is unstable across a
### delete of an earlier instance (compaction shifts it down), but the NAME is
### a stable handle that still resolves. This is the crucial difference from
### wires (which had NO stable handle) and the fact that shapes Phase D: do
### instances need a numeric id, or does the name suffice?
reload
xschem unselect_all
xschem instance res.sym 3000 3000 0 0 {name=AAA}
set idx_before [idx_of AAA]
check {CHI7a created instance has a valid index} {$idx_before >= 0}
# delete a LOW-index instance (index 0) so every later index shifts down by 1
xschem unselect_all
xschem select instance 0
xschem delete
set idx_after [idx_of AAA]
check {CHI7b INDEX is unstable: AAA's index shifted down by the compaction} \
  {$idx_after == $idx_before - 1}
check {CHI7c NAME is stable: AAA still resolves and keeps its coords} \
  {[resolves AAA] == 1 && [string trim [xschem instance_coord AAA]] eq {{AAA} {res.sym} 3000 3000 0 0}}

### CHI8 — selection side effects (instances flow through `selection` and
### `selected_set`; today an instance carries id -1 — no stable id yet)
reload
xschem unselect_all
xschem instance res.sym 3000 3000 0 0 {name=AAA}
xschem unselect_all
xschem select instance AAA
check {CHI8a lastsel 1 after selecting one instance} {[xschem get lastsel] == 1}
check {CHI8b first_sel reports type ELEMENT(8)} {[lindex [xschem get first_sel] 0] == 8}
set row [lindex [xschem selection] 0]
check {CHI8c selection row is {instance <idx> 1 -1} (col WIRELAYER, id -1 today)} \
  {[lindex $row 0] eq {instance} && [lindex $row 2] == 1 && [lindex $row 3] == -1}
check {CHI8d selected_set lists the instance by name} \
  {[lsearch -exact [xschem selected_set] {AAA}] >= 0}

### CHI9 — reorder-swap (change_elem_order) executes and preserves the SET
reload
set snap0 [inst_snapshot chi9pre]
xschem unselect_all
xschem instance res.sym 3000 3000 0 0 {name=AAA}
set name0_before [lindex [xschem instance_coord 0] 0]
set snap_with_aaa [inst_snapshot chi9with]
xschem unselect_all
xschem select instance AAA
xschem change_elem_order 0
check {CHI9a swap executed: AAA now sits at array index 0} \
  {[lindex [xschem instance_coord 0] 0] eq {AAA} && $name0_before ne {AAA}}
check {CHI9b swap preserves the instance SET (placement snapshot unchanged)} \
  {[inst_snapshot chi9post] eq $snap_with_aaa}
check {CHI9c both swapped instances still resolve by name} \
  {[resolves AAA] == 1 && [resolves $name0_before] == 1}

### CHI10 — bulk reset (clear_schematic sets instances = 0)
reload
xschem set modified 0
xschem clear force schematic
check {CHI10 clear force schematic: zero instances} {[ninst] == 0}

xschem set modified 0
