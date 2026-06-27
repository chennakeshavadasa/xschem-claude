# Issue 0044 — xinit.c: tk_messageBox hangs headless tests in batch mode (-q)

**Opened:** 2026-06-27
**Status:** OPEN — C fix needed; revert applied to our PR branch.
**Affects:** src/xinit.c — source_tcl_file() and Tcl_AppInit() error paths
**Severity:** medium — headless tests with -q can hang waiting for a GUI dialog
**Needs Ananth:** YES — C fix only

**Root cause:**
When Tcl_AppInit encounters a script error (missing xschem.tcl, bad --script path),
it calls tk_messageBox if has_x is true. In --pipe -q mode, has_x is true (Tk is
available) but there is no interactive user — the dialog hangs forever.

**Fix (3 lines in src/xinit.c):**
Add `&& !cli_opt_quit` to the three `if(has_x)` guards in source_tcl_file()
and Tcl_AppInit() that call tk_messageBox on error. When -q is passed,
skip the dialog and go straight to Tcl_Exit(EXIT_FAILURE).

Exact diff was in commit ea855d3 (now reverted from our branch).

**Acceptance criteria:**
Running with --pipe -q and a bad --script path exits immediately (no dialog).
