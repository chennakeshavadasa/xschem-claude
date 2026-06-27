# Issue 0040 — cadence::open_inst_sch_readonly (Ctrl-Shift-N) opens blank window on WSLg

**Opened:** 2026-06-27
**Status:** FIXED (2026-06-27)
**Affects:** utils/cadence_nav.tcl — cadence::open_inst_sch_readonly (Ctrl-Shift-N)
**Severity:** medium — blank canvas until manual F; no error message
**Branch:** fluid-editing

**Repro:**
  1. Launch: DISPLAY=:0 ./src/xschem --script src/cadence_style_rc
  2. Open a schematic with sub-cell instances.
  3. Select an instance.
  4. Press Ctrl-Shift-N.
  5. New window opens with correct title but blank canvas. Pressing F shows the schematic.

## Root cause
cadence::open_inst_sch_readonly calls schematic_in_new_window but does not call
newwin_defer_fullzoom. open_sub_schematic and hi_descend_newwin received this fix
in issue 0037 §5; cadence_nav.tcl was overlooked because it is a separate file.

## Fix
After schematic_in_new_window returns 1, call newwin_defer_fullzoom on
last_created_window (wrapped in catch for headless/no-X safety).

## Acceptance criteria
- Ctrl-Shift-N on a selected instance → new window shows schematic immediately (no blank)
- Headless pipe tests all green
