# Characterization tests (Phase A of plan_stable_handles_step1.md).
# These lock the CURRENT wire lifecycle behavior as observed through the Tcl
# surface, so the Phase C funnel refactor is provably behavior-identical.
# They must be green at every commit from Phase A on.
#
# Sourced by wrap.tcl, which provides `check`, `xcheck` and `::qo_dir`.
#
# Conventions:
# - All edits happen on /tmp/sh_fixture.sch (a copy) — never the repo file.
# - `xschem set modified 0` before every load (avoids the save-prompt modal).
# - Wire snapshots are COORDINATE-ONLY and SORTED: the set of wires is the
#   behavior we preserve; array order is an implementation detail that is
#   already unstable today (see tcl_introspection_wire.md §2e) and that the
#   funnel must remain free to change. Attribute drift is covered separately
#   by the byte-compare checks (CH5), because wire lab= attrs are stamped by
#   the connectivity engine and would produce false snapshot diffs.

### stub every modal dialog BEFORE any code path can reach one
rename tk_messageBox _real_tk_messageBox
proc tk_messageBox {args} {return ok}
rename tk_getOpenFile _real_tk_getOpenFile
proc tk_getOpenFile {args} {return {}}
catch {rename alert_ _real_alert_}
proc alert_ {args} {return 1}

### fixture: a /tmp copy of the 91-wire example
set REPO [file normalize $::qo_dir/../..]
set FIX /tmp/sh_fixture.sch
file copy -force $REPO/xschem_library/examples/mos_power_ampli.sch $FIX

proc reload {} {
  global FIX
  xschem set modified 0
  xschem load $FIX
}
proc nwires {} {return [xschem get wires]}

# sorted, coordinate-only wire list via xschem's own serializer (saveas):
# the only complete enumeration that includes wire 0 (wire_coord 0 is
# unreachable today — scheduler.c:7032)
proc wire_snapshot {tag} {
  set f /tmp/sh_snap_$tag.sch
  file delete -force $f
  xschem saveas $f schematic
  set fd [open $f r]; set data [read $fd]; close $fd
  set w {}
  foreach line [split $data \n] {
    if {[string match {N *} $line]} {
      regsub { \{.*\}$} $line {} line
      lappend w $line
    }
  }
  return [lsort $w]
}
proc read_file {f} {
  set fd [open $f r]; set d [read $fd]; close $fd
  return $d
}
# file content from the first "G {" line onward — skips the v{...} header,
# which memory undo is already known not to round-trip (see CH5c)
proc body_after_header {f} {
  set lines [split [read_file $f] \n]
  set i [lsearch -glob $lines {G \{*}]
  return [join [lrange $lines $i end] \n]
}

### CH1 — create a wire
reload
set ::base_n [nwires]
set ::base_snap [wire_snapshot base]
check {CH1pre fixture has 91 wires} {$::base_n == 91 && [llength $::base_snap] == 91}
xschem unselect_all
xschem wire 6000 -6000 6100 -6000 -1 {} 1
check {CH1a create: wire count +1} {[nwires] == $::base_n + 1}
set s1 [wire_snapshot ch1]
set diff {}
foreach l $s1 {if {[lsearch -exact $::base_snap $l] < 0} {lappend diff $l}}
check {CH1b create: snapshot gains exactly the new wire} \
  {$diff eq {{N 6000 -6000 6100 -6000}} && [llength $s1] == $::base_n + 1}
check {CH1c create with sel=1: selected} {[xschem get lastsel] == 1}

### CH2 — delete it
xschem delete
check {CH2a delete: wire count back to baseline} {[nwires] == $::base_n}
check {CH2b delete: snapshot equals baseline set} \
  {[wire_snapshot ch2] eq $::base_snap}

### CH3 — undo/redo round-trip, BOTH undo backends
foreach utype {disk memory} {
  reload
  xschem undo_type $utype
  xschem unselect_all
  xschem wire 6000 -6000 6100 -6000 -1 {} 1
  xschem delete
  check "CH3a ($utype) create+delete: baseline count" {[nwires] == $::base_n}
  xschem undo
  check "CH3b ($utype) undo restores the deleted wire" {[nwires] == $::base_n + 1}
  xschem redo
  check "CH3c ($utype) redo re-deletes" {[nwires] == $::base_n}
  xschem undo
  xschem undo
  check "CH3d ($utype) full unwind: snapshot equals baseline" \
    {[nwires] == $::base_n && [wire_snapshot ch3_$utype] eq $::base_snap}
}

### CH4 — connectivity-engine operations (these run the check.c sites that
### Phase C will funnel: the densest coverage goes here)
reload
xschem trim_wires
check {CH4a trim_wires on fixture: count unchanged (91)} {[nwires] == 91}
reload
xschem break_wires
check {CH4b break_wires on fixture: count unchanged (91)} {[nwires] == 91}
reload
xschem rebuild_connectivity
check {CH4c rebuild_connectivity on fixture: count unchanged (91)} {[nwires] == 91}

# synthetic merge: two collinear touching wires must merge into one
xschem set modified 0
xschem clear force schematic
xschem wire 0 0 100 0
xschem wire 100 0 200 0
check {CH4d synthetic: two collinear wires placed} {[nwires] == 2}
xschem trim_wires
check {CH4e trim_wires merges collinear pair into one} {[nwires] == 1}
xschem undo
check {CH4f undo of trim restores the pair} {[nwires] == 2}

# synthetic T-junction: a wire ending mid-span of another must SPLIT it.
# These three cases execute the wire-split birth sites (census B3, B4, B6)
# that the fixture runs above do not reach (the fixture is well-formed).
proc tj_setup {} {
  xschem set modified 0
  xschem clear force schematic
  xschem wire 0 0 200 0
  xschem wire 100 0 100 100
  xschem unselect_all
}
tj_setup
xschem trim_wires
check {CH4g trim_wires splits at T-junction (B3): 3 wires} {[nwires] == 3}
check {CH4h split produces the exact segment set} \
  {[wire_snapshot ch4h] eq [lsort {{N 0 0 100 0} {N 100 0 200 0} {N 100 0 100 100}}]}
# B4 (break_wires_at_point) depends on a populated wire spatial hash —
# a freshly scripted schematic has a stale one, so rehash first; the cut
# point may be off-wire within cadsnap and is projected onto the wire
xschem set modified 0
xschem clear force schematic
xschem wire 0 0 200 0
xschem unselect_all
xschem rebuild_connectivity
xschem wire_cut 100 3 noalign
check {CH4i wire_cut splits at projected point (B4): 2 wires} {[nwires] == 2}
check {CH4i2 wire_cut split produces the exact segment set} \
  {[wire_snapshot ch4i] eq [lsort {{N 0 0 100 0} {N 100 0 200 0}}]}
tj_setup
xschem select wire 1
xschem break_wires
check {CH4j break_wires at selected wire's endpoint (B6): 3 wires} {[nwires] == 3}
check {CH4k B6 split: new segment joins the selection} {[xschem get lastsel] >= 2}

### CH5 — whole-pipeline drift detector (byte-level)
reload
xschem saveas /tmp/sh_save_clean1.sch schematic
reload
xschem saveas /tmp/sh_save_clean2.sch schematic
check {CH5a save is deterministic (two clean saves byte-identical)} \
  {[read_file /tmp/sh_save_clean1.sch] eq [read_file /tmp/sh_save_clean2.sch]}

reload
xschem undo_type disk
xschem unselect_all
xschem wire 6000 -6000 6100 -6000 -1 {} 1
xschem delete
xschem undo
xschem undo
xschem saveas /tmp/sh_save_disk.sch schematic
check {CH5b disk-undo edit cycle: save byte-identical to clean save} \
  {[read_file /tmp/sh_save_disk.sch] eq [read_file /tmp/sh_save_clean1.sch]}

reload
xschem undo_type memory
xschem unselect_all
xschem wire 6000 -6000 6100 -6000 -1 {} 1
xschem delete
xschem undo
xschem undo
xschem saveas /tmp/sh_save_mem.sch schematic
# characterized pre-existing quirk: memory undo does not round-trip the
# multi-line v{...} file header (collapses to one line); everything from the
# first G{} record onward is identical. We lock the body invariant.
check {CH5c memory-undo edit cycle: save body identical from G record onward} \
  {[body_after_header /tmp/sh_save_mem.sch] eq [body_after_header /tmp/sh_save_clean1.sch]}

### CH6 — selection side-effect chain (the funnel must not change these)
reload
xschem unselect_all
xschem select wire 5
check {CH6a select wire 5: lastsel 1} {[xschem get lastsel] == 1}
check {CH6b first_sel reports type=WIRE(1) n=5 col=0} \
  {[xschem get first_sel] eq {1 5 0}}
xschem unselect_all
check {CH6c unselect_all: lastsel 0} {[xschem get lastsel] == 0}

### H1–H7 — session-stable wire ids (Phase D of the plan). Committed RED
### first (all xcheck, logging XFAIL — see commit dd0a56d6) per the TDD
### discipline; H1–H6 flipped to plain check by the D2 implementation
### commit, H7 resolved by the D3 decision (disk undo invalidates handles —
### option (b), see the H7 block below).
###
### Surface under test (additive, two scheduler subcommands):
###   xschem wire_id <index>   → session-stable id of wire[index] (or -1)
###   xschem wire_index <id>   → current array index of that wire (or -1)
###
### Conventions for these scenarios:
### - wrappers h_wid/h_widx catch the "invalid command" error so the RED
###   suite runs to completion; they return -2 (never a legal result) while
###   the commands do not exist, and are transparent once they do.
### - every scenario keeps a throwaway "pad" wire at index 0: wire_coord 0
###   is unreachable today (scheduler.c `n > 0` — known pothole, out of
###   step-1 scope), so any wire whose coords we dereference must sit at
###   index >= 1.

proc h_wid {n} {
  if {[catch {xschem wire_id $n} r]} {return -2}
  return $r
}
proc h_widx {id} {
  if {[catch {xschem wire_index $id} r]} {return -2}
  return $r
}
proc h_setup {} {
  xschem set modified 0
  xschem clear force schematic
  xschem wire 5000 5000 5100 5000
  xschem unselect_all
}

### H1 — ids of created wires are positive and pairwise distinct
h_setup
xschem wire 0 0 100 0
xschem wire 0 100 100 100
xschem wire 0 200 100 200
set ida [h_wid 1]
set idb [h_wid 2]
set idc [h_wid 3]
check {H1 created wires have positive pairwise-distinct ids} \
  {$ida > 0 && $idb > 0 && $idc > 0 && $ida != $idb && $ida != $idc && $idb != $idc}

### H2 — the §2e dangling-index scenario, solved by handle: hold wire C's id,
### delete neighbor B; C's array index changes (order-preserving compaction
### shift) but the id still dereferences to C's coordinates. This is the
### original tcl_introspection_wire.md defect this whole feature exists for.
xschem select wire 2
xschem delete
set idx_c [h_widx $idc]
check {H2a id survives a neighbor delete and still resolves} {$idx_c >= 1}
set wc {}
if {$idx_c >= 1} {catch {xschem wire_coord $idx_c} wc}
check {H2b resolved index dereferences to the held wire's coords} \
  {$wc eq {0 200 100 200}}

### H3 — delete the held wire itself: handle dangles LOUDLY (-1), it does not
### silently name a stranger like a raw index does
h_setup
xschem wire 0 0 100 0
set id3 [h_wid 1]
xschem select wire 1
xschem delete
check {H3 deref after own deletion returns -1} {[h_widx $id3] == -1}

### H4 — no id reuse within a session: create→delete→create at the same
### coords mints a fresh id
h_setup
xschem wire 0 0 100 0
set id4a [h_wid 1]
xschem select wire 1
xschem delete
xschem wire 0 0 100 0
set id4b [h_wid 1]
check {H4 recreated wire at same coords gets a fresh id} \
  {$id4b > 0 && $id4a > 0 && $id4b != $id4a}

### H5 — memory-undo round-trip: undo makes the handle dangle, redo brings
### back the SAME id resolving to the same coords (mem undo copies whole
### structs both ways — census "facts banked for Phase D")
h_setup
xschem undo_type memory
xschem wire 0 0 100 0
set id5 [h_wid 1]
xschem undo
set h5_gone [h_widx $id5]
xschem redo
set h5_back [h_widx $id5]
check {H5a memory undo: handle of the undone wire dangles} {$h5_gone == -1}
set wc5 {}
if {$h5_back >= 1} {catch {xschem wire_coord $h5_back} wc5}
check {H5b memory redo: same id resolves again to the same coords} \
  {$h5_back >= 1 && $wc5 eq {0 0 100 0}}

### H6 — split/merge id semantics. These tests RECORD the design decision:
### the struct that survives the operation keeps its id; newly born segments
### get fresh ids (wire_store_split is a birth door).
# split: T-junction trim splits wire W at (100,0) into two halves
h_setup
xschem wire 0 0 200 0
xschem wire 100 0 100 100
set idw [h_wid 1]
set idt [h_wid 2]
xschem trim_wires
set i_w [h_widx $idw]
set i_t [h_widx $idt]
set cw {}
if {$i_w >= 1} {catch {xschem wire_coord $i_w} cw}
check {H6a split: original id survives on one collinear half} \
  {$i_w >= 1 && ($cw eq {0 0 100 0} || $cw eq {100 0 200 0})}
# the other collinear half is a new segment and must carry a fresh id
set i_other {}
for {set i 1} {$i < [nwires]} {incr i} {
  set c {}
  catch {xschem wire_coord $i} c
  if {($c eq {0 0 100 0} || $c eq {100 0 200 0}) && $i != $i_w} {set i_other $i}
}
set ido [expr {$i_other ne {} ? [h_wid $i_other] : -2}]
check {H6b split: the new segment carries a fresh id} \
  {$ido > 0 && $ido != $idw && $ido != $idt}
set ct {}
if {$i_t >= 1} {catch {xschem wire_coord $i_t} ct}
check {H6c split: untouched stem keeps its id} \
  {$i_t >= 1 && $ct eq {100 0 100 100}}
# merge: two collinear touching wires trim into one — exactly one id survives
h_setup
xschem wire 0 0 100 0
xschem wire 100 0 200 0
set idm1 [h_wid 1]
set idm2 [h_wid 2]
xschem trim_wires
set im1 [h_widx $idm1]
set im2 [h_widx $idm2]
check {H6d merge: exactly one of the two ids survives, the other dangles} \
  {[nwires] == 2 && (($im1 >= 1 && $im2 == -1) || ($im1 == -1 && $im2 >= 1))}

### H7 — disk undo INVALIDATES handles (D3 decision: option (b),
### invalidate-on-restore, chosen by the user 2026-06-12). Disk undo restores
### by re-reading .sch-format temp files (clear_drawing + load_wire), so
### restored wires are new births carrying fresh ids and every handle held
### across a disk-undo restore dangles LOUDLY: the wire_id_counter is
### monotonic per context and survives the restore, so freshly minted ids are
### strictly greater than any id a script can already hold — an old handle
### can never alias a restored wire. Memory undo (H5) is the backend that
### round-trips identity. (Was an xcheck round-trip expectation through D2 —
### see commits dd0a56d6 / 6e0c6eaf.)
h_setup
xschem undo_type disk
xschem wire 0 0 100 0
set id7 [h_wid 1]
xschem undo
xschem redo
check {H7a disk undo+redo restores the wire itself} \
  {[nwires] == 2 && [xschem wire_coord 1] eq {0 0 100 0}}
check {H7b held handle is loudly invalidated (-1, not a stranger)} \
  {[h_widx $id7] == -1}
set id7r [h_wid 1]
check {H7c restored wire carries a fresh, valid, resolvable id} \
  {$id7r > 0 && $id7r != $id7 && [h_widx $id7r] == 1}
xschem undo_type memory

xschem set modified 0
