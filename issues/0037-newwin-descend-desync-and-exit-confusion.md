# Issue 0037 — new-window descend desync (read-only never applied) and multi-window exit confusion

**Opened:** 2026-06-26
**Status:** PARTIALLY FIXED (2026-06-26).
**Affects:** `hi_descend_newwin` (`src/xschem.tcl`), `schematic_in_new_window`
(`src/actions.c`), the multi-window quit/teardown path, the `callback()` disk-mtime
`set_modify(1)` check (`src/callback.c`). Repro env: `src/xschem --script
src/cadence_style_rc` (sets `descend_readonly 1`), open via Library Manager
`xschem_libraries_oa/SANDBOX/test_hier_descend_etc/schematic/test_hier_descend_etc.sch`,
whose only instance `x1 = SANDBOX/solar_ctl`.
**Branch:** `fluid-editing`. See [[hi-descend]], issues 0035, 0036.

---

## 1. Symptoms reported

1. Select `x1`, open it in a new window → the new window **immediately shows the
   modified `*`** and the **title shows the PARENT cell** (`test_hier_descend_etc`)
   instead of `solar_ctl`.
2. (CTRL-X descend in the original window logs nothing in the CIW.)
3. On CTRL-Q: "Schematic test_hier_descend_etc.sch has unsaved changes. Save before
   quitting?" → No. Then BOTH windows pop "UNSAVED data: want to exit?" (the solar_ctl
   window's prompt names `test_hier_descend_etc.sch` — wrong cell). Clicking OK twice
   leaves the first window blank (title still `test_hier_descend_etc`), then it becomes
   the WSLg "empty shell immune to xkill" (issue 0002).

## 2. FIXED — the new-window desync (symptom 1's wrong title, and its `*`)

`hi_descend_newwin` called `schematic_in_new_window` with the target instance still
selected. That function's `lastsel==1` branch opens the **instance's** schematic
(`solar_ctl`) as a fresh top level, NOT the parent; `copy_hierarchy` then overwrites it
with the parent, and the following `select x1; descend` finds no `x1` in `solar_ctl`, so
the descend no-ops. The window is left desynced: `schname`=parent, `currsch`=0
(hierarchy lost), and — because the `if {$ok}` block is skipped — **read-only is never
applied** (`ro`=0). An editable window with a stale `time_last_modify` then trips the
`callback()` mtime check → spurious `*`.

Fix (commit `da142c75`): unselect before `schematic_in_new_window` (as
`open_sub_schematic` does), so it opens the parent and the descend is real. Verified on
the fixture: selected-`x1` new window → `sch=solar_ctl currsch=1 sch_path=.x1. ro=1`
(was `sch=parent currsch=0 ro=0`). Read-only now applied, so the mtime-check `set_modify`
is suppressed (issue 0035) and the `*` should be gone. Headless `SELNW` regression added.

## 3. NOT YET REPRODUCED — original-window `*` + exit confusion/crash

The CTRL-Q prompt names the **editable parent** (first window) as modified, which the
new-window fix does not touch. In a scripted repro of the full flow (source
`cadence_style_rc`, load the fixture, descend `x1`→`x3`, ascend) `modified` stays 0 at
every level — so the parent `*` is NOT from the descend path. The one path not
replicated headlessly is the **Library Manager open** (which has git integration,
`specs/library_git.md`). Hypothesis: the open (or git) leaves the parent file's on-disk
mtime != the loaded `time_last_modify`, so a later event's mtime check sets `modified`
on the editable parent — and the multi-window quit then walks windows with a confused
per-window `schname`, double-prompts, and tears down abnormally → WSLg ghost (0002).

To narrow it, need from the reporter:
- Does the spurious `*` on the original window happen when the file is opened via
  **File ▸ Open** instead of the Library Manager?
- Is `SANDBOX/...` under git / freshly written this session (so its mtime is "newer
  than load")?
- Which exact action opened the new window (hi_descend dialog → New window, vs
  Ctrl-Shift-N `cadence::open_inst_sch_readonly`)?

## 4. Candidate follow-up fixes (pending repro)

- The mtime check setting `modified` conflates "file changed on disk" with "you have
  unsaved edits"; the correct response to an external change is the RELOAD prompt
  (`scheduler.c:718`), not a save prompt. Consider not calling `set_modify(1)` from the
  mtime check at all (let reload handle it).
- Harden the multi-window quit to use each window's OWN `schname`/modified state and not
  double-prompt, so a confused/modified window cannot wedge teardown into the WSLg ghost.
