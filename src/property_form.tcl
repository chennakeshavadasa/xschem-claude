# property_form.tcl — the slick per-property "Edit Properties" form.
#
# v1 replaces the single raw-text-box property editor with a structured form: one
# entry per declared symbol attribute (Cadence-style), strict (no free-form add of
# undeclared tokens), single-line fields, Enter=OK / Escape=Cancel.
#
# This file is split in two:
#   * the CORE (namespace slickprop, below) — pure, widget-independent parse and
#     reassemble logic, unit-tested headless by tests/property_form/. It is the
#     correctness gate the form rests on.
#   * the FORM (the Tk dialog) — added on top of the core, see slickprop::edit_form.
#
# The reassembly is "subst-into-original": on OK, start from the object's ORIGINAL
# property string and substitute back ONLY the fields the user actually edited
# (tracked per field). Untouched tokens are preserved byte-for-byte — which is the
# cardinal invariant (open + OK with no edits leaves the string unchanged), proven
# necessary by probe: always-requoting turns `name=E1` into `name="E1"`, so only
# touched fields may be rewritten.
#
# Token primitives used (all pure string ops in the C core):
#   xschem list_tokens <s> 0      -> the token names in <s>
#   xschem get_tok <s> <tok> 2    -> <tok>'s value, CLEAN (quotes/escapes removed,
#                                     no tcl-hook substitution): the editable form
#   xschem subst_tok <s> <tok> <v>-> <s> with <tok>=<v> (v inserted AS-IS; an empty
#                                     v REMOVES the token). Caller must pre-quote.

namespace eval slickprop {}

# Escape any embedded " and \ in <v> and wrap the whole thing in double quotes,
# producing a value safe to hand to `subst_tok` (which inserts it verbatim). This
# is the same recipe the legacy "Edit Attr" combobox used.
proc slickprop::requote {v} {
  regsub -all {(["\\])} $v {\\\1} v
  return "\"$v\""
}

# Build the ordered field model for the form from an object's property string
# <prop> and its symbol template <template>. Returns a list of field dicts; each:
#   name      the token name (the fixed field label)
#   value     the current editable value (clean; empty for a declared-but-unset
#             attr, so it is not written unless the user types something)
#   declared  1 if the token is declared in the template, else 0 (an "Extra" token)
#   default   the template default (declared tokens only; {} for extras) — shown as
#             a greyed placeholder when the field is unset
#   isset     1 if the token is actually present in <prop>, else 0
# Declared tokens come first, in template order; then any extra (undeclared)
# instance tokens, in their order of appearance.
proc slickprop::to_fields {prop template} {
  set decl [xschem list_tokens $template 0]
  set inst [xschem list_tokens $prop 0]
  set fields {}
  foreach tok $decl {
    set isset [expr {[lsearch -exact $inst $tok] >= 0}]
    lappend fields [dict create \
      name     $tok \
      value    [expr {$isset ? [xschem get_tok $prop $tok 2] : {}}] \
      declared 1 \
      default  [xschem get_tok $template $tok 2] \
      isset    $isset]
  }
  foreach tok $inst {
    if {[lsearch -exact $decl $tok] >= 0} continue
    lappend fields [dict create \
      name     $tok \
      value    [xschem get_tok $prop $tok 2] \
      declared 0 \
      default  {} \
      isset    1]
  }
  return $fields
}

# Apply edits to <orig>, subst-into-original. <changes> is a flat list
# {tok val tok val ...} of ONLY the fields the user actually edited. For each:
#   * an empty <val> REMOVES the token (the clear / delete path);
#   * otherwise <val> is requoted and substituted in.
# Tokens of <orig> not named in <changes> are preserved byte-for-byte. With an
# empty <changes> the result is identical to <orig> (the cardinal invariant).
proc slickprop::apply {orig changes} {
  set out $orig
  foreach {tok val} $changes {
    if {$val eq {}} {
      set out [xschem subst_tok $out $tok <NULL>]
    } else {
      set out [xschem subst_tok $out $tok [slickprop::requote $val]]
    }
  }
  return $out
}

# ===========================================================================
# THE FORM (Tk). Built on the core above. State for the single open dialog
# lives in slickprop::cur(...) (only one Edit Properties dialog exists at a
# time). Field-building and change-collection are factored out of the modal
# wrapper so they can be driven headlessly by tests.
# ===========================================================================

# Get the symbol's template (declared attributes), or "" if unavailable.
proc slickprop::template_of {symbol} {
  if {[catch {xschem getprop symbol $symbol template} t]} { return "" }
  return $t
}

# Build the per-field rows for <prop>+<template> into the frame <parent>,
# recording state in slickprop::cur. Each field is a label + a single-line entry.
# A declared-but-unset attr shows its template default as a greyed placeholder
# (not part of the value). Returns the list of token names placed.
proc slickprop::build_fields {parent prop template} {
  variable cur
  array unset cur
  set cur(orig) $prop
  set cur(tokens) {}
  set fields [slickprop::to_fields $prop $template]
  set r 0
  set extras_started 0
  foreach f $fields {
    set tok      [dict get $f name]
    set val      [dict get $f value]
    set declared [dict get $f declared]
    set default  [dict get $f default]
    # a visual divider before the first undeclared "Extra" token
    if {!$declared && !$extras_started} {
      set extras_started 1
      label $parent.x$r -text "Extra (undeclared)" -fg gray40 -anchor w
      grid $parent.x$r -row $r -column 0 -columnspan 2 -sticky w -pady {6 1}
      incr r
    }
    label $parent.l$r -text $tok -anchor w
    entry $parent.e$r -width 48
    grid $parent.l$r -row $r -column 0 -sticky w  -padx {2 6}
    grid $parent.e$r -row $r -column 1 -sticky we -padx {0 2}
    set cur(entry,$tok)       $parent.e$r
    set cur(loaded,$tok)      $val
    set cur(placeholder,$tok) 0
    lappend cur(tokens) $tok
    if {$val ne {}} {
      $parent.e$r insert 0 $val
    } elseif {$default ne {}} {
      slickprop::set_placeholder $tok $default
    }
    incr r
  }
  grid columnconfigure $parent 1 -weight 1
  return $cur(tokens)
}

# Show <default> as a greyed placeholder in <tok>'s entry; clears on focus-in,
# restores on focus-out if left empty. While showing, the field value is empty.
proc slickprop::set_placeholder {tok default} {
  variable cur
  set e $cur(entry,$tok)
  $e delete 0 end
  $e insert 0 $default
  $e configure -fg gray60
  set cur(placeholder,$tok) 1
  bind $e <FocusIn>  [list slickprop::placeholder_in $tok]
  bind $e <FocusOut> [list slickprop::placeholder_out $tok $default]
}
proc slickprop::placeholder_in {tok} {
  variable cur
  if {$cur(placeholder,$tok)} {
    set e $cur(entry,$tok)
    $e delete 0 end
    $e configure -fg black
    set cur(placeholder,$tok) 0
  }
}
proc slickprop::placeholder_out {tok default} {
  variable cur
  set e $cur(entry,$tok)
  if {[$e get] eq {}} { slickprop::set_placeholder $tok $default }
}

# The effective current value of a field's entry (a showing placeholder is empty).
proc slickprop::field_value {tok} {
  variable cur
  if {$cur(placeholder,$tok)} { return {} }
  return [$cur(entry,$tok) get]
}

# Collect the {tok val ...} list of ONLY the fields whose value changed from what
# they loaded with — the input to slickprop::apply (subst-into-original).
proc slickprop::collect_changes {} {
  variable cur
  set changes {}
  foreach tok $cur(tokens) {
    set v [slickprop::field_value $tok]
    if {$v ne $cur(loaded,$tok)} { lappend changes $tok $v }
  }
  return $changes
}

# The new property string implied by the current field edits (for OK / tests).
proc slickprop::result {} {
  variable cur
  return [slickprop::apply $cur(orig) [slickprop::collect_changes]]
}

# The OK action: compute the new property string from the field edits into
# tctx::retval, replicate edit_prop's symbol-change / copy-cell handling, set
# rcode, and tear the dialog down. (Mirrors the legacy edit_prop OK handler so
# the C side update_symbol() sees the same contract.)
proc slickprop::ok {} {
  global symbol prev_symbol copy_cell user_wants_copy_cell
  set ::tctx::retval [slickprop::result]
  set symbol [.dialog.f1.e2 get]
  set abssymbol [abs_sym_path $symbol]
  set ::tctx::rcode {ok}
  set user_wants_copy_cell $copy_cell
  set prev_symbol [abs_sym_path $prev_symbol]
  if { ($abssymbol ne $prev_symbol) && $copy_cell } {
    if { ![regexp {^/} $symbol] && ![regexp {^[a-zA-Z]:} $symbol] } {
      set symlist [file split $symbol]
      set symlen [llength $symlist]
      set abssymbol "[path_head $prev_symbol $symlen]/$symbol"
    }
    if { [file exists "[file rootname $prev_symbol].sch"] } {
      if { ! [file exists "[file rootname ${abssymbol}].sch"] } {
        file copy "[file rootname $prev_symbol].sch" "[file rootname $abssymbol].sch"
      }
    }
    if { [file exists "$prev_symbol"] } {
      if { ! [file exists "$abssymbol"] } { file copy "$prev_symbol" "$abssymbol" }
    }
  }
  set copy_cell 0
  destroy .dialog
}

proc slickprop::cancel {} {
  global edit_symbol_prop_new_sel
  set ::tctx::rcode {}
  set edit_symbol_prop_new_sel {}
  destroy .dialog
}

# The slick replacement for the legacy edit_prop dialog: one single-line entry
# per declared symbol attribute (Cadence-style, strict), Enter=OK / Escape=Cancel.
# Same C contract as the old edit_prop: reads tctx::retval (current property
# string) and the `symbol` global on entry; sets tctx::retval (new string) +
# tctx::rcode ({ok}|{}) and returns rcode. Modal.
proc slickprop::edit_form {txtlabel} {
  global symbol prev_symbol no_change_attrs preserve_unchanged_attrs copy_cell
  global user_wants_copy_cell edit_prop_size edit_prop_pos edit_symbol_prop_new_sel
  set user_wants_copy_cell 0
  set ::tctx::rcode {}
  set ::tctx::retval_orig $::tctx::retval
  if { [winfo exists .dialog] } return
  xschem set semaphore [expr {[xschem get semaphore] + 1}]
  toplevel .dialog -class Dialog
  wm title .dialog {Edit Properties}
  wm transient .dialog [xschem get topwindow]
  set X [expr {[winfo pointerx .dialog] - 60}]
  set Y [expr {[winfo pointery .dialog] - 35}]
  wm geometry .dialog "+$X+$Y"

  set prev_symbol $symbol

  # --- top: symbol entry + Browse -----------------------------------------
  frame .dialog.f1
  label .dialog.f1.l2 -text "Symbol"
  entry .dialog.f1.e2 -width 30
  .dialog.f1.e2 insert 0 $symbol
  button .dialog.f1.b5 -text "Browse" -command {
    set r [tk_getOpenFile -parent .dialog -initialdir $INITIALINSTDIR]
    if {$r ne {}} { .dialog.f1.e2 delete 0 end; .dialog.f1.e2 insert 0 $r }
    raise .dialog .drw
  }
  pack .dialog.f1.l2 -side left
  pack .dialog.f1.e2 -side left -fill x -expand yes
  pack .dialog.f1.b5 -side left

  # --- options row (the legacy checkbuttons; their globals are read by C) ---
  frame .dialog.f2
  checkbutton .dialog.f2.r1 -text "No change properties" -variable no_change_attrs
  checkbutton .dialog.f2.r2 -text "Preserve unchanged props" -variable preserve_unchanged_attrs
  checkbutton .dialog.f2.r3 -text "Copy cell" -variable copy_cell
  pack .dialog.f2.r1 .dialog.f2.r2 .dialog.f2.r3 -side left

  # --- scrollable per-field area ------------------------------------------
  frame .dialog.fa
  canvas .dialog.fa.c -yscrollcommand ".dialog.fa.sb set" -highlightthickness 0
  scrollbar .dialog.fa.sb -command ".dialog.fa.c yview" -orient vertical
  frame .dialog.fa.c.inner
  .dialog.fa.c create window 0 0 -anchor nw -window .dialog.fa.c.inner -tags inner
  bind .dialog.fa.c.inner <Configure> {
    .dialog.fa.c configure -scrollregion [.dialog.fa.c bbox all]
    .dialog.fa.c itemconfigure inner -width [winfo width .dialog.fa.c]
  }
  pack .dialog.fa.sb -side right -fill y
  pack .dialog.fa.c -side left -fill both -expand yes

  # --- bottom: OK / Cancel -------------------------------------------------
  frame .dialog.fb
  button .dialog.fb.ok     -text "OK"     -command slickprop::ok -width 8
  button .dialog.fb.cancel -text "Cancel" -command slickprop::cancel -width 8
  pack .dialog.fb.ok .dialog.fb.cancel -side left -padx 4 -pady 2

  pack .dialog.f1 -side top -fill x
  pack .dialog.f2 -side top -fill x
  pack .dialog.fb -side bottom -fill x
  pack .dialog.fa -side top -fill both -expand yes

  # populate the fields from the property string + symbol template
  slickprop::build_fields .dialog.fa.c.inner $::tctx::retval [slickprop::template_of $symbol]

  # --- keyboard contract: Enter = OK, Escape = Cancel ----------------------
  bind .dialog <Return>     {slickprop::ok}
  bind .dialog <KP_Enter>   {slickprop::ok}
  bind .dialog <Escape>     {slickprop::cancel}
  wm protocol .dialog WM_DELETE_WINDOW {slickprop::cancel}

  # focus + select the most-likely-to-edit field (the symbol's `select` attr,
  # else value/lab/name), mirroring the legacy dialog's cursor placement.
  set sel_attr [xschem get_tok $::tctx::retval select]
  if {$sel_attr eq {}} { catch {set sel_attr [xschem getprop symbol $symbol select]} }
  set focused 0
  foreach a [list $sel_attr value lab name] {
    if {$a ne {} && [info exists slickprop::cur(entry,$a)]} {
      set e $slickprop::cur(entry,$a)
      focus $e; $e selection range 0 end; $e icursor end
      set focused 1; break
    }
  }
  if {!$focused && [llength $slickprop::cur(tokens)]} {
    focus $slickprop::cur(entry,[lindex $slickprop::cur(tokens) 0])
  }

  tkwait window .dialog
  xschem set semaphore [expr {[xschem get semaphore] - 1}]
  return $::tctx::rcode
}
