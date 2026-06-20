#!/bin/sh
# Aggregate every test_wireedit_*.tcl in this dir: print each RESULT line and exit
# nonzero if any test FAILS or produces no RESULT. Spec: Phase 0.2.
#
# These tests drive the scripted edit path (move_objects etc.), which is byte-identical
# to the interactive drag's release -- so they run TRUE HEADLESS via --nogui (no X server,
# no window; options.c sets has_x=0). DISPLAY is deliberately unset so a stray server can't
# turn this into a windowed run. This avoids the WSLg flakiness (empty stdout / exit 127)
# that windowed runs hit. (The GESTURE tests -- test_cadence_drag.tcl -- DO need a real
# window and are not part of this aggregate.) Run from anywhere; it locates the repo root.
root=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$root" || exit 2
fail=0
ran=0
for t in tests/headless/wireedit/test_wireedit_*.tcl; do
  [ -e "$t" ] || continue
  ran=$((ran + 1))
  out=$(env -u DISPLAY timeout 60 ./src/xschem --nogui --pipe -q --nolog --script "$t" 2>&1)
  line=$(printf '%s\n' "$out" | grep -E '^RESULT:' | tail -1)
  echo "$(basename "$t"): ${line:-NO RESULT}"
  case "$line" in
    "RESULT: ALL PASS") ;;
    *) fail=1 ;;
  esac
done
if [ "$ran" -eq 0 ]; then echo "WIREEDIT: no tests found"; exit 2; fi
if [ "$fail" -eq 0 ]; then echo "WIREEDIT: ALL PASS"; else echo "WIREEDIT: FAILURES"; fi
exit $fail
