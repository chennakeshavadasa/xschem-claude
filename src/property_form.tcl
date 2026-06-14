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
