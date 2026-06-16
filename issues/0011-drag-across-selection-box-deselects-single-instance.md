# Issue 0011 — dragging across the selection box deselects a *single* selected instance

**Opened:** 2026-06-15
**Status:** OPEN — reported, root cause not yet verified (leading hypothesis in §3).
**Affects:** interactive selection with the Cadence-style interaction settings
(`src/cadence_style_rc`: `intuitive_interface=1`, `cadence_compat=1`,
`enable_stretch=1`). Mouse/GUI only — not reproducible headlessly without an event
stream.
**Severity:** low–medium (workflow annoyance; the user loses a selection they
expected to keep — no data loss).
**Branch:** suggest a small dedicated branch when picked up; the selection-handling
code touched is shared (`callback.c`), independent of `library-manager`.
**Related:** the broader interaction-mode analysis in
`code_analysis/FAQ.md` Q14 and `code_analysis/wire_follow_stretch_move.md`
(same `intuitive_interface` / `cadence_compat` selection machinery).

---

## 1. Reproduction (reported)

1. Open `xschem_library/examples/mos_power_ampli.sch` (run with
   `--script src/cadence_style_rc`, as the reporter does).
2. Click a **single** instance to select it → its dashed selection rectangle
   (bounding box) is drawn.
3. Press Button1 and **drag the mouse pointer across that dashed rectangle**
   (the drag path crosses the box).
4. **Observed:** the instance becomes **deselected**.

**The tell-tale asymmetry:** the same gesture does **not** deselect when **more
than one** object is selected. So the bug is specific to the `lastsel == 1`
(single-selection) state.

---

## 2. Expected behaviour

Dragging the pointer across (or near) the selection box of an already-selected
object should not silently drop the selection. Either:
- it should begin a move/drag of the selected object (if the gesture starts on it),
  or
- it should begin a fresh rubber-band selection (if it starts on empty canvas),
  matching whatever rule applies when *several* objects are selected.

Whatever the rule is, it must be **independent of the selection count** — the
single-object case should behave like the multi-object case.

---

## 3. Candidate root cause (hypothesis — NOT yet verified)

The behaviour lives in the intuitive / cadence_compat selection logic in
`callback.c`. Several count- or selection-clearing branches are in play; the bug
is most likely one (or an interaction) of these:

1. **Press-time unselect in the intuitive interface** —
   `handle_button_press`, `callback.c:5198-5203`:
   ```c
   if(xctx->intuitive_interface && !already_selected && no_shift_no_ctrl)
     unselect_all(1);
   if(!already_selected) select_object(...);
   ```
   `already_selected` is computed from `find_closest_obj()` **at the press point**.
   If the drag starts just *off* the instance (on empty canvas), `already_selected`
   is 0 → `unselect_all(1)` fires immediately on press and the instance is dropped.
   This is the leading suspect for "crossing the box from outside."
   - *Why it might look count-dependent:* with several objects selected, the chosen
     drag-start point is more likely to land on one of them (`already_selected==1`),
     so the unselect is skipped. With a single small instance there is more empty
     space around it, so the press lands on emptiness and clears it. This would make
     the asymmetry **circumstantial rather than a hard rule** — needs confirming.

2. **cadence_compat release branch (explicitly count-gated)** —
   `handle_button_release`, `callback.c:5321-5343`:
   ```c
   else if(cadence_compat && xctx->lastsel != 1 && state == Button1Mask && !xctx->mouse_moved) {
     ... if(already_selected) { unselect_all(1); select_object(...); }
   }
   ```
   This is gated on `lastsel != 1`, i.e. it deliberately treats the single-selection
   case differently — exactly the axis of the reported asymmetry. It requires
   `!mouse_moved` (a click, not a drag), so it only applies if the "drag" is short
   enough not to set `mouse_moved`. Worth checking whether a small cross-the-box
   motion still counts as `!mouse_moved`.

3. **Rubber-band select END** — `callback.c:5387-5397`
   (`select_rect(enable_stretch, END, -1)`): if the press did start a `STARTSELECT`
   rubber band, the END reselects whatever the box covered, replacing the prior
   selection. Combined with (1)'s press-time clear, the net effect is "old selection
   gone, new (possibly empty) selection."

Note `prev_last_sel` (`callback.c:5146`, used at `:5256`) is only consulted for
highlight redraw, not selection — likely a red herring.

---

## 4. How to verify (interactive — WSLg caveat applies)

1. Build, run with `--script src/cadence_style_rc`, open the example.
2. Add `dbg(1, ...)` (or use existing dbg lines) around `callback.c:5200`,
   `:5323`, `:5340` and run with `-d 1` to see which `unselect_all` actually fires
   for the failing gesture.
3. Distinguish the two hypotheses:
   - If the deselect happens **on press** → it's branch (1) (empty-canvas press).
   - If it happens **on release** with no net movement → it's branch (2).
4. Repeat with 2+ objects selected and confirm which branch is skipped — that
   identifies the count-dependent path to fix.

Because this is pointer-driven, the WSLg flakiness noted elsewhere (issue 0001)
applies; drive it by hand or via `xschem callback`-level event injection rather
than relying on `event generate` smokes.

---

## 5. Acceptance criteria

- With a single instance selected in `mos_power_ampli.sch`, dragging the pointer
  across its selection box no longer silently deselects it.
- The single-selection and multi-selection cases behave identically for the same
  gesture.
- No regression to: click-empty-to-clear, click-object-to-select, rubber-band
  area select, and intuitive drag-to-move (all under `cadence_compat=1`).
