# Test harness for the slick property-form CORE (the pure parse/assemble logic
# behind the new per-field "Edit Properties" dialog — branch slick-property-forms).
#
# This suite tests the WIDGET-INDEPENDENT core: turning a property string + symbol
# template into an ordered field model (slickprop::to_fields) and reassembling it
# by substituting ONLY the fields the user edited back into the original string
# (slickprop::apply, "subst-into-original"). It is the correctness gate the whole
# form rests on — the cardinal invariant being "open + OK with no edits leaves the
# property string byte-identical" (PF4), proven across real symbols (PF9).
#
# Run from the source tree (headless, needs the xschem token primitives):
#   cd src && timeout -s KILL 120 ./xschem -q --script ../tests/property_form/wrap.tcl
# Results in /tmp/sh_pf_test.log. PASS/FAIL per check, final line DONE.

set ::pf_dir [file normalize [file dirname [info script]]]
set ::logfd [open /tmp/sh_pf_test.log w]

proc check {what cond} {
  if { [catch {uplevel 1 [list expr $cond]} res] } {
    puts $::logfd "FAIL: $what (eval error: $res)"
  } elseif { $res } {
    puts $::logfd "PASS: $what"
  } else {
    puts $::logfd "FAIL: $what"
  }
  flush $::logfd
}
# expected-failure variant for the RED phase (the slickprop:: core not yet written)
proc xcheck {what cond} {
  if { [catch {uplevel 1 [list expr $cond]} res] } {
    puts $::logfd "XFAIL: $what (eval error: $res)"
  } elseif { $res } {
    puts $::logfd "PASS (was XFAIL — flip to check): $what"
  } else {
    puts $::logfd "XFAIL: $what"
  }
  flush $::logfd
}

# Source the core module if it exists yet (RED phase: it does not -> procs absent).
catch {source [file normalize $::pf_dir/../../src/property_form.tcl]}

if { [catch {source $::pf_dir/body.tcl} err] } {
  puts $::logfd "ERROR: $err"
  puts $::logfd $::errorInfo
}

puts $::logfd "DONE"
flush $::logfd
close $::logfd
exit
