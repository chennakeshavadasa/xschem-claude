# Opening prompt for the next session (Phase 3d — pivot decision: d1b vs d3 vs thin d2 tail)

Committed on branch `feature/action-registry`: 3a (wheel), 3b (right-drag zoom
gesture), 3c (context-routed keys — migration complete), 3d.1 (Tcl-command-backed
actions; `B` out), 3d.2 dispatch refinement + batch 1 (`H`, Alt-`h`) + batch 2 (`y`,
`G`, `g`, `T`, `O`) + batch 3 (`A`, `L`, `=`, `$`). Keys already migrated out of the
switch: **B, H, Alt-h, y, G, g, T, O, A, L, =, $**.

**The clean canvas-only command-key well is nearly dry.** After batch 3, what remains
in `handle_key_press` is mostly: semaphore-gated chords (need d1b), mouse-coord/modal
placement (stays in C by design), `Z` (blocked on a d4 csv/C id reconciliation —
`view.zoom_in` means CADZOOMSTEP on the wheel but `view_zoom(0.0)` for Shift+Z), and a
couple of *unconditional* symbol toggles (`%` draw-grid, `_` change-line-width) that
can only migrate **additively** (keep the case, add a mods-0 row, let the gate shadow
it — the arrow-key pattern; low value since the switch doesn't shrink).

So the next session is a **pivot decision**, not another clean-key batch. Paste the
block below into a fresh Claude Code session from this repo dir.

---

```
Goal: pick the highest-leverage next step in the action-registry input work and do it.
The clean canvas-only command-key migration (Phase 3d.2 batches 1-3) has nearly
exhausted its candidates. Before writing any code, do the pre-flight, then PROPOSE ONE
of the three directions below with reasoning and get my sign-off.

PRE-FLIGHT (confirm the well is actually dry before pivoting):
1. Re-grep callback.c line numbers (they shift every batch).
2. Re-run the cleanliness scan over handle_key_press (per-case counts of
   `semaphore>=2` / `waves_selected` / mouse-coords mousex_snap|mx_double|infix_interface
   / modal move_objects|new_*|place_|start_line|ui_state). Already migrated (SKIP):
   B, H, Alt-h, y, G, g, T, O, A, L, =, $.
3. Confirm what's left really is sem-gated / modal / additive-only. If you find a
   genuinely clean, switch-shrinking key I missed, that's a valid small batch-4 instead.

THE THREE DIRECTIONS (recommend one):

(A) d1b — semaphore `idle_only` flag. HIGHEST LEVERAGE. Unlocks the 6 deferred
    sem-first chords (plain a/b, s, Ctrl+s/f/r) AND the many sem-gated command keys
    (n, q, e, i, j/J, k/K, u, ...). Mechanism: add an `idle_only` bit to ActionDef (or
    the binding), checked at the TOP of the DEV_KEY dispatch BEFORE current_input_ctx/
    waves_selected (which are side-effectful) — so a busy editor (semaphore>=2) bails
    exactly like the old `if(sem>=2)break;` did, before any graph side effect fires.
    Then a sem-gated key migrates cleanly: add its row(s), delete the guard, the
    idle_only check stands in for the deleted `if(sem>=2)break`. See the 2026-06-08
    DECISION in project memory action-registry.md and refactor_plan d1b. This is the
    architecturally meaningful unblock; everything sem-gated is parked behind it.

(B) d3 — keyboard cheat-sheet generated from `xschem bindings dump`. SELF-CONTAINED,
    Tcl-side, NO switch edits (low risk, good demo value). Replace/extend the existing
    `generate_keybindings_text`/`show_keybindings_help` (Help menu) to read the live
    binding table (`xschem bindings dump`) instead of (or merged with) the accel
    display strings, flagging migrated chords. Cross-check against actions.csv for the
    human-readable command names. Test with tests/headless/test_keybindings_help.tcl.

(C) Thin d2 tail (additive). `%` (draw_grid) and `_` (change_lw) are unconditional
    (no mod guard) → migrate the arrow-key way: KEEP the case, add a `mods-0 canvas`
    row, let the gate shadow the mods-0 chord while the case still handles other mods.
    C-backed acts (both set xctx flags: change_lw / draw_pixmap-style). LOW VALUE (the
    switch doesn't shrink) — only worth it as a warm-up. NOTE the behavior-preservation
    subtlety: deleting these cases whole is WRONG (drops modified-press behavior); the
    additive approach is the only correct one. Also d4-blocked `Z` lives here.

MY RECOMMENDATION going in: (A) d1b — it's the gate that unblocks the largest set and
the last structurally-new piece before d4/d5 are mostly mechanical. But run the
pre-flight and make your own call; (B) is the safe pick if you want a low-risk session.

Warm-start context — read these first:
- CLAUDE.md (architecture, build, the `xschem` Tcl dispatcher)
- claude_suggs/refactor_plan_action_registry_phase3.md (overall plan; d1b/d3/d4/d5)
- claude_suggs/tutorial_action_registry_phase3d.md (d1+d2+d3-of-this-doc lessons:
  validator gotcha; canvas-only dispatch refinement; graph-routed-but-whole-deletable;
  id-reuse; don't-reuse-an-id-whose-semantics-differ)
- claude_suggs/design_phase3d1_tcl_backed_actions.md (Tcl-backed action machinery)
- claude_suggs/plan_phase3d2_batch3.md (batch-3 shape, if you do option C)
- src/callback.c — RE-GREP: ActionDef + action_registry[] + find_action_def (~2300-2380);
  act_* fns above the registry; init_input_bindings (~2400-2510); the DEV_KEY dispatch
  atop handle_key_press (~3030) — `ae.ctx = find_binding(...,ACTX_OVER_GRAPH) ?
  current_input_ctx(...) : ACTX_CANVAS`. For d1b the idle_only check goes ABOVE that
  ae.ctx line (before current_input_ctx is ever called).
- tests/headless/test_key_graph_context.tcl (the growing key test — extend it; helpers
  check / screen / keyat / keyats x y keysym state)
- tests/headless/run.sh (engine harness — stay 6/6)

Gotchas (also in project memory action-registry.md):
- GUI runs with DISPLAY=:0; capture stdout with --pipe:
  `DISPLAY=:0 ./src/xschem --pipe -q --script FILE`. Drive events with
  `xschem callback .drw <evt> <mx> <my> <keysym> <button> 0 <state>` (KeyPress=2;
  ShiftMask=1, ControlMask=4, Mod1Mask/Alt=8). Keysym (not display casing) matches.
- For d1b: semaphore is `xctx->semaphore`; readable via `xschem get`? check — if not,
  test idle_only by other means (e.g. assert a sem-gated act does NOT fire while a
  modal op holds the semaphore, vs fires when idle). The 6 sem-first chords' canvas
  behavior stays in C; d1b only adds the over_graph routing + the idle gate.
- A migrated act() takes (const ActionEvent *e), ignores mouse context, and must NOT
  read handle_key_press params — read the source (tcl var / xctx field) instead.
- Commit code and docs separately, small steps. Don't push or do anything
  outward-facing without asking.

Definition of done:
1. One direction proposed + signed off (+ a short plan doc if it's a code change).
2. Implemented behavior-preserving; engine 6/6 + all GUI smokes green; extend the
   relevant headless test.
3. After it lands: update the plan/tutorial/memory and refresh THIS prompt.

Start with the pre-flight, then propose A / B / C with reasoning.
```

---

## Roadmap after this pivot

- **d1b** semaphore `idle_only` — unlocks the 6 sem-first chords + sem-gated command keys.
- **d3** cheat-sheet from `xschem bindings dump` (Tcl-side, no switch edits).
- **d4** load `keybindings.csv`/`mousebindings.csv` at startup; **fold the C-only ids into
  `actions.csv`**: `edit.toggle_stretch`, `view.snap_half`, `view.snap_double`,
  `view.toggle_show_netlist`, `edit.toggle_orthogonal_wiring`, `view.toggle_draw_pixmap`;
  and **reconcile the `Z` / `view.zoom_in` collision** (wheel CADZOOMSTEP vs Shift+Z
  view_zoom(0.0) — they need distinct ids).
- **d5** delete the dead switch ladders.

The running user-facing Q&A lives in `code_analysis/action_registry_faq.md` (stamped
with phase + HEAD); add to it when the user asks a keep-worthy question.
