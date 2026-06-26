# Issue 0035 — a freshly descended NEW window is spuriously flagged "modified" (asterisk + save prompt)

**Opened:** 2026-06-25
**Status:** OPEN (pre-existing multi-window infra; surfaced via `hi_descend ... target=new_window`)
**Affects:** the disk-mtime modified check in `callback()`
(`src/callback.c` ~5962), `set_modify()`/title rendering (`src/actions.c` ~218),
new-context init (`create_new_window`/`create_new_tab`, `src/xinit.c` ~1699/1847),
`schematic_in_new_window` / `new_schematic switch`. Reachable from both
`open_sub_schematic` (Alt+E) and `hi_descend` new-window/tab paths.
**Severity:** medium — no data is actually at risk, but the bogus asterisk + "save
changes?" prompt on close is confusing and trains users to ignore save prompts.
**Branch:** `fluid-editing`. See [[hi-descend]], [[multi-window-detach]].

---

## 1. Symptom

Descend into a sub-schematic in a **new window/tab** (`hi_descend target=new_window`,
or Alt+E `open_sub_schematic`). Move the mouse into the new window: the title bar
gains the `*` "modified" marker although nothing was edited. Closing the window then
prompts "save changes?".

## 2. Suspected root cause

`callback()` runs, on (almost) every event including the first Motion/Enter in the new
window:

```c
/* src/callback.c ~5962 — "file modified on disk since loaded" detection */
if(!xctx->modified && !stat( xctx->sch[xctx->currsch], &buf) && xctx->time_last_modify &&
   xctx->time_last_modify != buf.st_mtime) {
   set_modify(1);
}
```

The marker is the `*` added by `set_modify()`'s title path (`actions.c` ~218, only when
`modified==1`). The check is meant to catch a file edited by an external program, by
comparing the loaded-time mtime (`xctx->time_last_modify`) against the current disk
mtime. The hypothesis is that for a freshly created window context the
`time_last_modify` recorded for the descended child does not match the file's disk
mtime (a stale/0 value carried in the new `Xschem_ctx`, or the descend-into-new-window
sequence — `schematic_in_new_window` loads the parent, then `descend` loads the child —
sets `time_last_modify` from a different file/àt a different moment than the stat seen
on the first event), so the comparison fires `set_modify(1)`.

Not yet reproduced head­lessly (a synthetic `xschem callback <win> 6 …`/`7 …` does NOT
trip it on the test fixture — `modified` stays 0), so it is timing/data/-WM-dependent
and needs an interactive repro to confirm which of `time_last_modify` vs `st_mtime` is
wrong for the new context.

## 3. Fix direction (to verify interactively)

- After a descend into a new window/tab, ensure `xctx->time_last_modify` for the
  loaded child equals its on-disk mtime (re-`stat` and set it), so the
  `time_last_modify != st_mtime` guard cannot fire spuriously. Equivalently, make
  `create_new_window`/`create_new_tab` initialize `time_last_modify` to 0 AND have
  `load_schematic` always set it from the actual file just loaded.
- The mtime check should also be a no-op for a **read-only** context (a browse window
  cannot have been edited), and the close path should not prompt to save a read-only,
  never-edited window.

## 4. Mitigation already in place

`hi_descend` now opens the descended view **read-only by default** (Mode = Read only;
`specs/hi_descend.md`). A read-only browse window should never prompt to save — so once
the close path honors read-only (or the mtime check is fixed), the user-visible
annoyance for the hi_descend browse workflow disappears. This issue still tracks the
underlying spurious `set_modify(1)`.

## 5. Tests

- Interactive: descend into a new window, move mouse in, confirm no `*` and no
  save prompt on close (for both edit and read-only modes).
- Headless probe (once reproduced): after the new-window descend, assert
  `xschem get modified == 0` and that a simulated motion/enter callback keeps it 0
  (extend `tests/headless/test_hi_descend.tcl`). Sabotage-verify by forcing a
  `time_last_modify` mismatch.
