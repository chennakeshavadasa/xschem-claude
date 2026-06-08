# Action-registry FAQ

Running Q&A about the input action-registry / binding-table work (branch
`feature/action-registry`). Each entry records the **project state when it was
asked** (branch + HEAD commit + phase), because answers are tied to how much of the
refactor had landed at that moment — a later phase may make an old "no" a "yes."

Newest entries on top.

---

## Q1. Can a user remap the zoom-rectangle gesture from RMB-drag to **Ctrl+RMB-drag** with the current code?

- **Asked:** 2026-06-08
- **Project state:** branch `feature/action-registry` @ `898639af` (Phase 3a/3b done,
  Phase 3c c4/c5 first batch — key `f` — done). Mouse buttons: only the *bare*
  Button3 zoom-rect chord is data-driven (Phase 3b).

**Answer: No — not with the code at that commit, even though the binding can be created.**

`xschem bind button 3 ctrl canvas view.zoom_rect` parses and stores a valid row
(`parse_mods("ctrl") → ControlMask`, code 3). But the **press handler never reaches
the table dispatcher for a *modified* Button3 chord.**

`handle_button_press` (`callback.c`) is an `if / else-if` chain, and the data-driven
`dispatch_button_chord()` sits at the *end* of it (`callback.c:4560`). Earlier
`if`/`else if` branches hardcode the modified-Button3 chords and match first:

```c
if     (!excl && button==Button3 && state==ControlMask && semaphore<2) { … select_connected_nets(1); }  // 4522 ← Ctrl+RMB caught HERE
else if(!excl && button==Button3 && EQUAL_MODMASK && …)                { break_wires_at_point(…); }       // 4530/4536  (Alt+RMB)
else if(!excl && button==Button3 && state==ShiftMask && …)             { select_connected_nets(0); }      // 4542  (Shift+RMB)
…
else if(!excl && semaphore<2 && dispatch_button_chord(button, state, mx, my)) return;                      // 4560 ← table only reached here
```

`state` *is* correctly button-mask-stripped at `callback.c:4507`, so
`dispatch_button_chord` would see `mods==ControlMask` and *could* match the row — but
it is never called for Ctrl+Button3 because the hardcoded branch at 4522 wins and the
dispatch is in a later `else if`. Only **bare** Button3 falls through (the plain-RMB
context menu was moved to the release path, freeing the no-modifier slot).

**The completion side is already ready.** On Ctrl+RMB *release*, `state ==
Button3Mask|ControlMask`, so the exact-match context-menu branch
`if(state == Button3Mask)` (`callback.c:4779`) is skipped and the Phase 3b
fallthrough `else if((ui_state & STARTZOOM) && semaphore<2) end_place_move_copy_zoom()`
(`callback.c:4789`) completes the gesture. So only the **initiation** is blocked.

**What it would take** (a natural Phase 3 follow-on, same pattern as the key work):
1. Extract the hardcoded modified-Button3 branches into `act_*` fns
   (`select_connected_nets`, `break_wires_at_point`) + `{button 3 ctrl/shift/alt
   canvas}` rows; **or**
2. Move `dispatch_button_chord` earlier so a user-bound chord pre-empts the hardcoded
   default ("table-first, hardcoded-fallthrough" precedence, like the keys now have).

**UX consequence:** Ctrl+RMB is already a feature (select instance + connected nets,
stopping at junctions), so rebinding it to zoom means relocating that feature to
another chord.
