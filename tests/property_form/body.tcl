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
xcheck {PF1a to_fields returns 2 rows for a 2-token template} {[llength $F] == 2}
xcheck {PF1b row order follows the template (name then TABLE)} \
  {[f_dg [lindex $F 0] name] eq "name" && [f_dg [lindex $F 1] name] eq "TABLE"}
xcheck {PF1c the instance value is extracted clean (no surrounding quotes)} \
  {[f_dg [f_row $F TABLE] value] eq "1.4 0.0 1.6 4.0"}
xcheck {PF1d declared tokens are marked declared=1} \
  {[f_dg [f_row $F name] declared] == 1}

### PF2 — a declared-but-unset attr: isset=0, value empty, template default carried.
set prop {name=E1}
set tmpl {name=x1 lab=DEFLAB}
set F [f_fields $prop $tmpl]
xcheck {PF2a unset declared token lab has isset=0} \
  {[f_row $F lab] ne "" && [f_dg [f_row $F lab] isset] == 0}
xcheck {PF2b unset declared token lab has empty value (not written unless edited)} \
  {[f_row $F lab] ne "" && [f_dg [f_row $F lab] value] eq ""}
xcheck {PF2c unset declared token carries the template default as a hint} \
  {[f_dg [f_row $F lab] default] eq "DEFLAB"}

### PF3 — an extra (undeclared) instance token appears AFTER declared ones,
### declared=0 (the strict-mode "Extra" section).
set prop {name=E1 foobar=123}
set tmpl {name=x1}
set F [f_fields $prop $tmpl]
xcheck {PF3a extra token foobar is present} {[f_row $F foobar] ne ""}
xcheck {PF3b extra token is declared=0} {[f_dg [f_row $F foobar] declared] == 0}
xcheck {PF3c declared tokens come before extras} \
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
  xcheck "PF4-$tag apply(prop,{}) is byte-identical (no-edit no-op)" \
    {[f_apply $p {}] eq $p}
}

### PF5 — apply ONE change touches only that token; the rest is byte-identical.
set p {name=E1 TABLE="1.4 0.0 1.6 4.0"}
set out [f_apply $p [list TABLE "9.9 8.8"]]
xcheck {PF5a editing TABLE changes only TABLE's value} \
  {$out eq {name=E1 TABLE="9.9 8.8"}}
xcheck {PF5b name token is untouched (still bare, not requoted)} \
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
  xcheck "PF6-$tag re-inserting a value preserves its meaning" \
    {[xschem get_tok $out $tok 2] eq $v}
}

### PF7 — clearing a field (empty new value) removes the token.
set p {name=E1 lab=PLUS}
set out [f_apply $p [list lab {}]]
xcheck {PF7 clearing lab removes the token but keeps the rest} \
  {[string match {*name=E1*} $out] && ![string match {*lab=*} $out]}

### PF8 — requote escapes "/\ and wraps in quotes.
xcheck {PF8a requote wraps a plain value in quotes} \
  {[catch {slickprop::requote abc} r] == 0 && $r eq {"abc"}}
xcheck {PF8b requote escapes embedded double quotes} \
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
xcheck {PF9b no-op apply is byte-identical across all real instances} {$noop_ok == 1}
xcheck {PF9c every declared token survives re-insert with meaning intact} {$fidel_ok == 1}

### PF10 — the multi-line `code` symbol: a fresh instance round-trips its big
### `value`/`format` attributes byte-for-byte under a no-op apply.
xschem set modified 0
xschem clear force schematic
xschem instance code.sym 0 0 0 0 {name=s1}
set prop [xschem getprop instance 0]
xcheck {PF10 a code.sym instance's multi-line props survive a no-op apply} \
  {[f_apply $prop {}] eq $prop}

xschem set modified 0
