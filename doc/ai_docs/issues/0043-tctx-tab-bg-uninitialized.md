# Issue 0043 — tctx::tab_bg uninitialized when real windows opened before tabs

**Opened:** 2026-06-27
**Status:** FIXED (2026-06-27)
**Affects:** set_tab_names for-loop in src/xschem.tcl (~line 12004)
**Severity:** medium — "can't read tctx::tab_bg" error on every multi-window operation
**Branch:** fluid-editing

tctx::tab_bg is declared in the tctx namespace but never given a default value.
C sets it only when the first tab button (.tabs.xN) is created via new_schematic create.
When real windows (.x1 etc.) are opened before any tab button exists, tctx::tab_bg
is unset and the for-loop throws. Exposed by the issue 0042 fix which let the for-loop
run in cases where it previously was aborting early.

Fix: add [info exists tctx::tab_bg] as first condition in the for-loop guard.
