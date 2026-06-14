# Tests for the slick property-form CORE (slickprop::). Committed RED first:
# the PF* tests are xcheck (XFAIL) until src/property_form.tcl lands, then flip to
# check. Sourced by wrap.tcl, which provides check/xcheck/::pf_dir.
#
# THE CORE CONTRACT under test:
#   slickprop::to_fields <prop> <template>
#       -> ordered list of field dicts {name value declared default isset}, the
#          declared (template) tokens first (template order), then extra tokens.
#   slickprop::apply <orig> <changes>
#       -> <orig> with ONLY the {tok val ...} pairs in <changes> substituted back
#          (subst-into-original); empty val removes the token; untouched tokens of
#          <orig> are preserved byte-for-byte.
#   slickprop::requote <v>  -> escape "/\ and wrap in quotes (for subst_tok).
#
# A field needs a live xctx for the token primitives, so build a fixture first.

### stub modals
catch {rename tk_messageBox _real_tk_messageBox}
proc tk_messageBox {args} {return ok}

xschem set modified 0
xschem clear force schematic

# tolerant wrappers so missing procs (RED phase) don't abort the suite
proc f_fields {p t} { if {[catch {slickprop::to_fields $p $t} r]} {return -2}; return $r }
proc f_apply  {o c} { if {[catch {slickprop::apply $o $c} r]} {return -2}; return $r }
proc f_dg {d k {dflt {}}} { if {$d eq "-2"} {return $dflt}; if {[catch {dict get $d $k} v]} {return $dflt}; return $v }
# find the field dict for token <tok> in a to_fields result
proc f_row {fields tok} {
  if {$fields eq "-2"} {return {}}
  foreach row $fields { if {[f_dg $row name] eq $tok} {return $row} }
  return {}
}

### PF1 — to_fields builds one row per declared token, in template order, with the
### instance value where set.
set prop {name=E1 TABLE="1.4 0.0 1.6 4.0"}
set tmpl {name=x1 TABLE="0 0 0 0"}
set F [f_fields $prop $tmpl]
check {PF1a to_fields returns 2 rows for a 2-token template} {[llength $F] == 2}
check {PF1b row order follows the template (name then TABLE)} \
  {[f_dg [lindex $F 0] name] eq "name" && [f_dg [lindex $F 1] name] eq "TABLE"}
check {PF1c the instance value is extracted clean (no surrounding quotes)} \
  {[f_dg [f_row $F TABLE] value] eq "1.4 0.0 1.6 4.0"}
check {PF1d declared tokens are marked declared=1} \
  {[f_dg [f_row $F name] declared] == 1}

### PF2 — a declared-but-unset attr: isset=0, value empty, template default carried.
set prop {name=E1}
set tmpl {name=x1 lab=DEFLAB}
set F [f_fields $prop $tmpl]
check {PF2a unset declared token lab has isset=0} \
  {[f_row $F lab] ne "" && [f_dg [f_row $F lab] isset] == 0}
check {PF2b unset declared token lab has empty value (not written unless edited)} \
  {[f_row $F lab] ne "" && [f_dg [f_row $F lab] value] eq ""}
check {PF2c unset declared token carries the template default as a hint} \
  {[f_dg [f_row $F lab] default] eq "DEFLAB"}

### PF3 — an extra (undeclared) instance token appears AFTER declared ones,
### declared=0 (the strict-mode "Extra" section).
set prop {name=E1 foobar=123}
set tmpl {name=x1}
set F [f_fields $prop $tmpl]
check {PF3a extra token foobar is present} {[f_row $F foobar] ne ""}
check {PF3b extra token is declared=0} {[f_dg [f_row $F foobar] declared] == 0}
check {PF3c declared tokens come before extras} \
  {[f_dg [lindex $F 0] name] eq "name" && [f_dg [lindex $F end] name] eq "foobar"}

### PF4 — THE CARDINAL INVARIANT: apply with NO changes is byte-identical, for a
### battery of hostile strings (quoted, multi-line, escaped, extra tokens).
foreach {tag p} {
  simple   {name=E1}
  spaces   {name=E1 TABLE="1.4 0.0 1.6 4.0"}
  extra    {name=E1 lab=PLUS foobar=123}
  multilin "format=\"\n@value\n\""
  escaped  {name=x1 descr="say \"hi\" there"}
} {
  check "PF4-$tag apply(prop,{}) is byte-identical (no-edit no-op)" \
    {[f_apply $p {}] eq $p}
}

### PF5 — apply ONE change touches only that token; the rest is byte-identical.
set p {name=E1 TABLE="1.4 0.0 1.6 4.0"}
set out [f_apply $p [list TABLE "9.9 8.8"]]
check {PF5a editing TABLE changes only TABLE's value} \
  {$out eq {name=E1 TABLE="9.9 8.8"}}
check {PF5b name token is untouched (still bare, not requoted)} \
  {[xschem get_tok $out name 2] eq "E1" && [string match {name=E1 *} $out]}

### PF6 — EDIT FIDELITY: re-inserting a value preserves its MEANING (get_tok before
### == after) even for spaces / multi-line / escaped quotes. (Not byte-identical —
### requoting may add quotes — but semantically lossless.)
foreach {tag p tok} {
  spaces   {name=E1 TABLE="1.4 0.0 1.6 4.0"}        TABLE
  multilin "v=\"\n@value\n\""                         v
  escaped  {d="say \"hi\" there"}                     d
} {
  set v [xschem get_tok $p $tok 2]
  set out [f_apply $p [list $tok $v]]
  check "PF6-$tag re-inserting a value preserves its meaning" \
    {[xschem get_tok $out $tok 2] eq $v}
}

### PF7 — clearing a field (empty new value) removes the token.
set p {name=E1 lab=PLUS}
set out [f_apply $p [list lab {}]]
check {PF7 clearing lab removes the token but keeps the rest} \
  {[string match {*name=E1*} $out] && ![string match {*lab=*} $out]}

### PF8 — requote escapes "/\ and wraps in quotes.
check {PF8a requote wraps a plain value in quotes} \
  {[catch {slickprop::requote abc} r] == 0 && $r eq {"abc"}}
check {PF8b requote escapes embedded double quotes} \
  {[catch {slickprop::requote {a"b}} r] == 0 && $r eq {"a\"b"}}

### PF9 — THE RELEASE GATE: across every instance of a real schematic, apply with
### no edits is byte-identical AND every declared token survives a re-insert with
### its meaning intact. This is run on real device prop strings at scale.
xschem set modified 0
xschem load [file normalize ../xschem_library/examples/mos_power_ampli.sch]
xschem set modified 0
set ninst [xschem get instances]
set noop_ok 1; set fidel_ok 1; set tested 0
for {set i 0} {$i < $ninst} {incr i} {
  set prop [xschem getprop instance $i]
  if {$prop eq ""} continue
  incr tested
  # no-op invariant
  if {[f_apply $prop {}] ne $prop} { set noop_ok 0 }
  # edit fidelity per declared token
  set tmpl [xschem getprop instance $i cell::template]
  foreach tok [xschem list_tokens $tmpl 0] {
    set v [xschem get_tok $prop $tok 2]
    set out [f_apply $prop [list $tok $v]]
    if {[xschem get_tok $out $tok 2] ne $v} { set fidel_ok 0 }
  }
}
# corpus-size precondition (not a module test) — a plain check
check {PF9a tested a meaningful number of real instances (> 50)} {$tested > 50}
check {PF9b no-op apply is byte-identical across all real instances} {$noop_ok == 1}
check {PF9c every declared token survives re-insert with meaning intact} {$fidel_ok == 1}

### PF10 — the multi-line `code` symbol: a fresh instance round-trips its big
### `value`/`format` attributes byte-for-byte under a no-op apply.
xschem set modified 0
xschem clear force schematic
xschem instance code.sym 0 0 0 0 {name=s1}
set prop [xschem getprop instance 0]
check {PF10 a code.sym instance's multi-line props survive a no-op apply} \
  {[f_apply $prop {}] eq $prop}

# ===========================================================================
# PF11-PF15 — the FORM layer (build_fields/placeholder/collect_changes/result),
# exercised through real Tk widgets (a display is available headless). These
# prove the widget-level dirty-tracking and placeholder logic feed the proven
# core correctly. Built in a withdrawn toplevel so nothing pops up.
# ===========================================================================
proc gui_ok {} { return [expr {[catch {toplevel .pf; wm withdraw .pf; frame .pf.f; pack .pf.f} ] == 0}] }
proc gui_done {} { catch {destroy .pf} }

### PF11 — build the form, make NO edits, result() == orig (cardinal invariant
### carried through the widget layer).
if {[gui_ok]} {
  set prop {name=E1 TABLE="1.4 0.0 1.6 4.0"}
  set tmpl {name=x1 TABLE="0 0 0 0" lab=DEF}
  slickprop::build_fields .pf.f $prop $tmpl
  check {PF11a build_fields placed an entry for each declared token} \
    {[winfo exists $slickprop::cur(entry,name)] && [winfo exists $slickprop::cur(entry,TABLE)]}
  check {PF11b no edits -> result() is byte-identical to the original} \
    {[slickprop::result] eq $prop}
  gui_done
} else { check {PF11 (skipped: no display)} {1} }

### PF12 — edit ONE entry; result() reflects only that change.
if {[gui_ok]} {
  set prop {name=E1 TABLE="1.4 0.0 1.6 4.0"}
  slickprop::build_fields .pf.f $prop {name=x1 TABLE="0 0 0 0"}
  $slickprop::cur(entry,TABLE) delete 0 end
  $slickprop::cur(entry,TABLE) insert 0 {9.9 8.8}
  check {PF12 editing the TABLE entry updates only TABLE in result()} \
    {[slickprop::result] eq {name=E1 TABLE="9.9 8.8"}}
  gui_done
} else { check {PF12 (skipped)} {1} }

### PF13 — a declared-but-unset attr shows its default as a placeholder; its
### effective value is empty and, if untouched, it is NOT written.
if {[gui_ok]} {
  set prop {name=E1}
  slickprop::build_fields .pf.f $prop {name=x1 lab=DEFLAB}
  check {PF13a unset attr lab shows the placeholder (default text, flagged)} \
    {$slickprop::cur(placeholder,lab) == 1 && [$slickprop::cur(entry,lab) get] eq "DEFLAB"}
  check {PF13b lab's effective value is empty (placeholder != content)} \
    {[slickprop::field_value lab] eq ""}
  check {PF13c untouched placeholder -> lab not written, result()==orig} \
    {[slickprop::result] eq $prop}
  gui_done
} else { check {PF13 (skipped)} {1} }

### PF14 — typing into a placeholder field adds the token.
if {[gui_ok]} {
  slickprop::build_fields .pf.f {name=E1} {name=x1 lab=DEFLAB}
  slickprop::placeholder_in lab   ;# simulate focus-in clearing the placeholder
  $slickprop::cur(entry,lab) insert 0 MYNET
  check {PF14 typing a value into an unset attr adds it} \
    {[xschem get_tok [slickprop::result] lab 2] eq "MYNET"}
  gui_done
} else { check {PF14 (skipped)} {1} }

### PF15 — clearing a set field removes its token.
if {[gui_ok]} {
  slickprop::build_fields .pf.f {name=E1 lab=PLUS} {name=x1 lab=DEF}
  $slickprop::cur(entry,lab) delete 0 end
  check {PF15 clearing a set field removes the token from result()} \
    {![string match {*lab=*} [slickprop::result]] && [string match {*name=E1*} [slickprop::result]]}
  gui_done
} else { check {PF15 (skipped)} {1} }

### PF16 — the FULL modal edit_form: build the real dialog, edit a field via a
### scheduled callback, click OK, and assert the C contract (rcode + tctx::retval).
### A safety timer cancels the modal if the field isn't found, so the suite can
### never hang. Guarded so an environment without a usable main window just skips.
proc gui2_ok {} { return [expr {[catch {winfo exists .drw} x]==0 && $x}] }
if {[gui2_ok]} {
  xschem set modified 0
  xschem clear force schematic
  xschem instance res.sym 0 0 0 0 {name=RTEST}
  set ::symbol res.sym
  set ::tctx::retval {name=RTEST value=1k}
  set ::no_change_attrs 0; set ::preserve_unchanged_attrs 0; set ::copy_cell 0
  set ::pf16_built 0
  after 500 {
    if {[info exists slickprop::cur(entry,value)]} {
      set ::pf16_built 1
      slickprop::placeholder_in value
      $slickprop::cur(entry,value) delete 0 end
      $slickprop::cur(entry,value) insert 0 2k
      slickprop::ok
    }
  }
  after 4000 {catch {slickprop::cancel}}  ;# safety: never hang the suite
  set pf16_rc [catch {slickprop::edit_form {Input property:}} pf16_ret]
  check {PF16a edit_form built per-field entries from the live template} {$::pf16_built == 1}
  check {PF16b edit_form returned rcode ok after OK} {$pf16_ret eq "ok"}
  check {PF16c OK wrote the edited value into tctx::retval (subst-into-original)} \
    {[xschem get_tok $::tctx::retval value 2] eq "2k" && [string match {name=RTEST*} $::tctx::retval]}
} else {
  check {PF16a (skipped: no main window)} {1}
  check {PF16b (skipped)} {1}
  check {PF16c (skipped)} {1}
}

### PF17 — user-tunable font size (the Cadence-style preference variable). Setting
### ::slickprop_fontsize drives the rendered named fonts on the next init.
set ::slickprop_fontsize 16
slickprop::init_fonts
check {PF17a slickprop_fontsize drives the value font size} \
  {[font configure slickPropValue -size] == 16}
check {PF17b the value font is the monospace TkFixedFont family} \
  {[font configure slickPropValue -family] eq [font actual TkFixedFont -family]}
check {PF17c the label font tracks the same size} \
  {[font configure slickPropLabel -size] == 16}
unset ::slickprop_fontsize  ;# back to auto-default for any later use

xschem set modified 0
