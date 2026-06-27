# Issue 0042 — tabs path errors in multi-window: .x1.tabs missing, .tabs.x1 gone after detach

**Opened:** 2026-06-27
**Status:** FIXED (2026-06-27) — two winfo-exists guards in src/xschem.tcl
**Affects:** toolbar_show (~line 11655), set_tab_names (~line 11992) in src/xschem.tcl
**Severity:** medium — spurious Tcl errors on every multi-window op; causes MWs and GUI8 test failures
**Branch:** fluid-editing

**Root cause:**
1. toolbar_show: packs $topwin.toolbar before $topwin.tabs — .x1.tabs does not exist
   for secondary windows; only the main window has .tabs
2. set_tab_names: configures .tabs$tabname (e.g. .tabs.x1) but this tab button is
   removed when a window is detached to its own OS window

**Fix:** Two winfo exists guards. See commit message for exact diff.

**Acceptance criteria:**
- No .x1.tabs or .tabs.x1 errors in stderr when opening secondary windows
- test_multi_window.tcl MWs passes
- test_lib_manager_gui.tcl GUI8 passes (or fails only due to pending MW7/8 features)
