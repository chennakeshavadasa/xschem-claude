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
