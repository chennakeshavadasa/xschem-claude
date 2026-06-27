#!/bin/bash
# Full headless audit — runs every .tcl test in tests/headless/
# Usage: bash full_audit.sh 2>&1 | tee audit_full_log.txt

XSCHEM="/home/nithin/AI_Projects/Open_EDA_Tools/xschem-fluid/src/xschem"
TESTDIR="tests/headless"
TIMEOUT=90
PASS=0; FAIL=0; CRASH=0
declare -A RESULTS
declare -A OUTPUTS

# Tests that require --logdir (open the action log or CIW)
logdir_tests=(
  test_ciw
  test_ciw_autocomplete
  test_ciw_puts_capture
  test_hi_descend
  test_action_log_dispatch
  test_action_log_libmgr
  test_context_menu_log
  test_gesture_end_log
  test_phase3_mints
  test_lib_roundtrip
)

# test_nolog explicitly tests --nolog mode, so it uses --nolog
nolog_tests=(test_nolog)

needs_logdir() {
  local t="$1"
  for x in "${logdir_tests[@]}"; do
    [[ "$t" == "$x" ]] && return 0
  done
  return 1
}

needs_nolog() {
  local t="$1"
  for x in "${nolog_tests[@]}"; do
    [[ "$t" == "$x" ]] && return 0
  done
  return 1
}

is_pass() {
  local name="$1" output="$2" ec="$3"
  case "$name" in
    test_palette)
      [[ $ec -eq 0 && "$output" == *"EVENT opens palette: yes"* ]] && return 0 ;;
    test_ciw_autocomplete)
      [[ "$output" == *"PASS: ciw autocomplete (0 failure(s))"* ]] && return 0 ;;
    test_ciw_puts_capture)
      [[ "$output" == *"PASS: ciw puts-capture (0 failure(s))"* ]] && return 0 ;;
    test_lib_new_discovered_defs)
      # This test prints "RESULT: all passed" (lowercase) instead of "RESULT: ALL PASS"
      [[ "$output" == *"RESULT: all passed"* ]] && return 0 ;;
    *)
      [[ "$output" == *"RESULT: ALL PASS"* ]] && return 0 ;;
  esac
  return 1
}

export DISPLAY=:0

for testfile in "$TESTDIR"/test_*.tcl; do
  name=$(basename "$testfile" .tcl)

  if needs_logdir "$name"; then
    TMPD=$(mktemp -d)
    if [[ "$name" == "test_action_log_libmgr" ]]; then
      CMD=(timeout $TIMEOUT env XSCHEM_AL_LOGDIR="$TMPD" "$XSCHEM" --pipe -q --logdir "$TMPD" --script "$testfile")
    else
      CMD=(timeout $TIMEOUT "$XSCHEM" --pipe -q --logdir "$TMPD" --script "$testfile")
    fi
  elif needs_nolog "$name"; then
    CMD=(timeout $TIMEOUT "$XSCHEM" --pipe -q --nolog --script "$testfile")
  else
    CMD=(timeout $TIMEOUT "$XSCHEM" --pipe -q --nolog --script "$testfile")
  fi

  output=$("${CMD[@]}" 2>&1)
  ec=$?

  if [[ $ec -eq 124 ]]; then
    RESULTS[$name]="TIMEOUT"
    OUTPUTS[$name]="$output"
    ((CRASH++))
  elif [[ "$output" == *"FATAL: signal"* ]] || [[ "$output" == *"Tcl_AppInit() error"* && "$output" != *"RESULT: ALL PASS"* ]]; then
    RESULTS[$name]="CRASH"
    OUTPUTS[$name]="$output"
    ((CRASH++))
  elif is_pass "$name" "$output" "$ec"; then
    RESULTS[$name]="PASS"
    ((PASS++))
  else
    RESULTS[$name]="FAIL"
    OUTPUTS[$name]="$output"
    ((FAIL++))
  fi
  echo "${RESULTS[$name]} | $name"
done

echo ""
echo "========================================"
echo "SUMMARY: $PASS PASS  $FAIL FAIL  $CRASH CRASH"
echo "Total: $((PASS + FAIL + CRASH))"
echo "========================================"
echo ""
echo "=== FAIL/CRASH/TIMEOUT FULL OUTPUTS ==="
for name in $(echo "${!OUTPUTS[@]}" | tr ' ' '\n' | sort); do
  echo ""
  echo "############## ${RESULTS[$name]}: $name ##############"
  echo "${OUTPUTS[$name]}"
done
