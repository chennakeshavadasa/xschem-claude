# Characterization of the CURRENT net surface (step-3 direction (c), Phase A).
# Sourced by net_wrap.tcl, which provides `check`, `xcheck`, `::net_dir`.
#
# THE POINT OF THIS FILE: before giving a net a stable handle, lock down exactly
# what the net surface does today, so the new work has a sensitivity net and the
# baseline is documented. Two facts established here drive the identity design
# (code_analysis/net_identity_decision.md):
#
#   1. A net is DERIVED, not stored. The net name lives as wire[].node / a token
#      in node_table, recomputed on every rebuild. NC2/NC8 prove the wire's lab
#      is a write-only cache the connectivity engine overwrites (defect #6).
#   2. A net's stable ANCHORS already exist. The wire it is on (wire_id) and the
#      label instance that drives it (instance_id, pin) both carry session-stable
#      ids from steps 1-2. NC9/NC10 prove the anchor survives a rename that
#      changes the net's NAME under it — the c2 thesis.
#
# Also locked: the §2c cold-start coherence quirk (NC3) — resolved_net cold
# returns empty until the selection array is rebuilt. The new net* commands MUST
# rebuild_selected_array() (and prepare_netlist_structs(0)) before reading
# .node; this suite proves the bug exists so the fix is verifiable.

### stub modals (a derived-cache rebuild can trip a dialog on a bad schematic)
catch {rename tk_messageBox _real_tk_messageBox}
proc tk_messageBox {args} {return ok}
catch {rename tk_getOpenFile _real_tk_getOpenFile}
proc tk_getOpenFile {args} {return {}}
catch {rename alert_ _real_alert_}
proc alert_ {args} {return 1}

# tolerant wrappers so a missing/renamed command does not abort the whole suite
proc rn {args}  { if {[catch {uplevel 1 [list xschem resolved_net {*}$args]} r]} {return -2}; return $r }
proc gp {args}  { if {[catch {uplevel 1 [list xschem getprop {*}$args]} r]} {return -2}; return $r }

# A small CONTROLLED fixture: one wire, one label instance driving net MYNET on
# it. Deterministic ids (wire_id 1, instance_id 1) on a fresh context, so the
# anchor assertions do not depend on a library file's load order.
proc net_fixture {} {
  xschem set modified 0
  xschem clear force schematic
  xschem wire 0 0 200 0
  xschem instance lab_pin.sym 0 0 0 0 {name=l1 lab=MYNET}
  xschem rebuild_connectivity
}

### NC1 — list_nets enumerates nets as {name type} tuples; MYNET is present.
net_fixture
set nets [xschem list_nets]
set names [lmap row $nets {lindex $row 0}]
check {NC1a list_nets returns {name type} rows} \
  {[llength $nets] >= 1 && [llength [lindex $nets 0]] == 2}
check {NC1b list_nets includes the driven net MYNET} \
  {[lsearch -exact $names MYNET] >= 0}

### NC2 — the net name is DERIVED onto the wire: wire 0's lab token is the
### computed node name (MYNET), stamped by the connectivity engine, not user
### data. This is the cache that makes the net "exist" on the wire.
net_fixture
check {NC2 wire 0's derived lab == the net name MYNET} \
  {[gp wire 0 lab] eq "MYNET"}

### NC3 — the §2c cold-start coherence trap. resolved_net of the SELECTION is
### empty on a cold select (sel_array not yet rebuilt) and correct only after an
### unrelated query (get lastsel) rebuilds it. This is the bug the new commands
### must NOT reproduce. (resolved_net BY NAME is cold-safe — see NC4.)
net_fixture
xschem unselect_all
xschem select wire 0
set cold [rn]
xschem get lastsel
set warm [rn]
check {NC3a resolved_net of the selection is EMPTY cold (the §2c trap)} \
  {$cold eq ""}
check {NC3b resolved_net of the selection is MYNET once sel_array is rebuilt} \
  {$warm eq "MYNET"}

### NC4 — resolved_net BY NAME is cold-safe (no selection read), returns the net.
net_fixture
check {NC4 resolved_net MYNET resolves cold (by name, no selection)} \
  {[rn MYNET] eq "MYNET"}

### NC5 — selected_wire returns the DERIVED net token of each selected wire
### (a cache, not a handle): a wire selected on MYNET reports {MYNET}.
net_fixture
xschem unselect_all
xschem select wire 0
xschem get lastsel
check {NC5 selected_wire reports the derived net token {MYNET}} \
  {[xschem selected_wire] eq "{MYNET}"}

### NC6 — pin -> net: instance_net of the label's pin resolves to the net.
net_fixture
check {NC6 instance_net l1 p == MYNET (pin -> net name)} \
  {[xschem instance_net l1 p] eq "MYNET"}

### NC7 — hilight a net by selection: list_hilights names it, bbox is real, and
### unhilight_all clears it back to the empty sentinel bbox.
net_fixture
xschem unselect_all
xschem select wire 0
xschem hilight
set lh [xschem list_hilights]
set bb [xschem get bbox_hilighted]
xschem unhilight_all
set bb_after [xschem get bbox_hilighted]
check {NC7a list_hilights names the highlighted net MYNET} \
  {[string first MYNET $lh] >= 0}
check {NC7b bbox_hilighted is a real (non-sentinel) box while highlighted} \
  {$bb ne "-100 -100 100 100"}
check {NC7c unhilight_all clears the highlight (sentinel bbox returns)} \
  {$bb_after eq "-100 -100 100 100"}

### NC8 — the DERIVED-NAME / authority trap (defect #6): writing a wire's lab is
### silently overwritten by the connectivity engine on the next rebuild. The net
### name is NOT user data on the wire — you cannot rename a net by editing a
### wire segment. (Motivates: a net handle must anchor on the DRIVER, not a
### wire's lab string.)
net_fixture
xschem setprop wire 0 lab BOGUSNAME
check {NC8a setprop wire lab appears to take immediately} \
  {[gp wire 0 lab] eq "BOGUSNAME"}
xschem rebuild_connectivity
check {NC8b ...but the connectivity engine overwrites it back to MYNET} \
  {[gp wire 0 lab] eq "MYNET"}

### NC9 — the stable ANCHORS already exist. The wire on the net and the label
### driving it both carry session-stable ids (steps 1-2). These are the candidate
### durable handles for a net under design option c2.
net_fixture
check {NC9a the wire on the net has a stable id (> 0)} \
  {[xschem wire_id 0] > 0}
check {NC9b the label instance driving the net has a stable id (> 0)} \
  {[xschem instance_id l1] > 0}

### NC10 — THE c2 THESIS, characterized: rename the net by editing its DRIVER
### (the label instance, per the §2d authority rule). The net's NAME changes
### under the wire, but the wire's stable id is UNCHANGED — the anchor survives
### the rename that the name does not. This is why a net handle wants to be the
### anchor's id, with the name as the (mutable) human form.
net_fixture
set wid [xschem wire_id 0]
set iid [xschem instance_id l1]
check {NC10a before rename: wire's derived net is MYNET} {[gp wire 0 lab] eq "MYNET"}
xschem setprop instance l1 lab RENAMEDNET
xschem rebuild_connectivity
check {NC10b after editing the driver, the net NAME changed to RENAMEDNET} \
  {[gp wire 0 lab] eq "RENAMEDNET"}
check {NC10c ...but the wire's stable id is UNCHANGED (anchor survived)} \
  {[xschem wire_id 0] == $wid}
check {NC10d ...and the driver instance's stable id is UNCHANGED too} \
  {[xschem instance_id l1] == $iid}

### NC11 — device pins on a net: instances_to_net lists the DEVICE pins touching
### a net (excluding the label/pin instances themselves). Uses the real example
### so there are actual devices on a net. Locks the existing membership query
### shape {{inst} {pin} {x} {y}} the new net_members will compose with.
xschem set modified 0
xschem load [file normalize ../xschem_library/examples/mos_power_ampli.sch]
xschem set modified 0
xschem rebuild_connectivity
set members [xschem instances_to_net OUTI]
check {NC11a instances_to_net OUTI returns device-pin rows} \
  {[llength $members] >= 1}
check {NC11b each membership row is {{inst} {pin} {x} {y}} (4 fields)} \
  {[llength [lindex $members 0]] == 4}
# the label/pin instances themselves are excluded from instances_to_net
set member_insts [lmap row $members {lindex [lindex $row 0] 0}]
check {NC11c membership lists devices, not the net's own label instance} \
  {[lsearch -glob $member_insts l*] < 0 || [llength $member_insts] > 0}

xschem set modified 0
