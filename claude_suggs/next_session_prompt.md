# Opening prompt for the next session (Phase 3d.2 — batch 3: scope + migrate more keys)

Committed on branch `feature/action-registry`: 3a (wheel), 3b (right-drag zoom
gesture), 3c (context-routed keys — migration complete), 3d.1 (Tcl-command-backed
actions; `B` out), 3d.2 dispatch refinement + batch 1 (`H`, Alt-`h`) + batch 2 (`y`,
`G`, `g`, `T`, `O`). Keys already migrated out of the switch: **B, H, Alt-h, y, G, g,
T, O**.

Paste the block below as the first message of a **fresh** Claude Code session, run
from this repo directory. Unlike batch 2 (which had a ready plan), batch 3 is
**scope-then-implement**: you pick the next clean cluster, write a short plan, get
sign-off, then migrate it the same way.

---

```
Goal for this session: Phase 3d.2 batch 3 of the action-registry input work — scope
and migrate the NEXT small cluster of clean command keys out of the ~1600-line
handle_key_press switch into the data-driven binding table, behavior-preserving and
fully tested, the same way batches 1-2 were done.

This batch has no pre-written plan: you scope it. Do the pre-flight, propose a small
batch (3-5 chords) with my sign-off, write a short plan doc like
claude_suggs/plan_phase3d2_batch2.md, then implement.

PRE-FLIGHT (do this first, before proposing anything):
1. Re-grep line numbers — callback.c shifts every batch; remembered numbers are stale.
2. Re-run the cleanliness classification scan over handle_key_press to find candidate
   branches with NO `semaphore >= 2`, NO `waves_selected`, NO mouse-coords
   (mousex_snap/mx_double/infix_interface), NO modal ui_state (move_objects/new_*/
   place_/start_line/ui_state). Example scan (adjust the NR range to the current
   handle_key_press bounds):
     awk 'NR>=A && NR<=B { ... per-case sem/waves/mouse/modal counts ... }' src/callback.c
   (See the batch-2 scan I ran earlier in the project history for the exact form, or
   just inspect each candidate case directly.)
3. Read each candidate case AS IT IS NOW and confirm it's clean before proposing it.
   Already-migrated keys to SKIP: B, H, h(Alt), y, G, g, T, O.

CANDIDATES worth inspecting (verify, don't trust): `Z` (zoom — view_zoom(0.0); watch
that you don't conflate it with the existing view.zoom_in/CADZOOMSTEP — replicate the
exact call), `L` (toggle orthogonal_wiring — it also sets xctx->manhattan_lines, a
small C state flag, so a C-backed act is fine but read the branch carefully), and any
other single-fn/single-tcleval branch the scan surfaces. STILL DEFERRED (do NOT pick):
anything semaphore-gated (-> d1b: plain a/b, s, Ctrl+s/f/r, n, q, ...) or mouse-coord/
placement/embedded-logic dialogs (insert-symbol file_chooser/load_file_dialog).

Warm-start context — read these first instead of re-deriving:
- CLAUDE.md  (architecture, build, the `xschem` Tcl dispatcher)
- claude_suggs/plan_phase3d2_batch2.md  (the batch-2 plan — copy its SHAPE for your
  batch-3 plan: keys table, act_ bodies, wrinkles, ids, case-deletes-whole-vs-branch,
  test approach, risks, DoD)
- claude_suggs/design_phase3d1_tcl_backed_actions.md  (how Tcl-backed actions work:
  the `tcl` field on ActionDef, find_action_def, dispatch, the bind validator)
- claude_suggs/tutorial_action_registry_phase3d.md  (d1+d2 lessons: the validator
  gotcha; the canvas-only dispatch refinement and WHY; EQUAL_MODMASK -> two rows; a
  migrated act must NOT use handle_key_press params — read the source tcl var; test via
  the state the act changes / stub a Tcl proc)
- claude_suggs/refactor_plan_action_registry_phase3.md  (overall plan; d2 status; d1b)
- src/callback.c — RE-GREP, but the machinery is around: ActionDef + action_registry[]
  + find_action_def (~2280-2330); act_* fns just above the registry (add yours there);
  init_input_bindings (seed DEV_KEY canvas rows; ~2360-2440); the DEV_KEY dispatch atop
  handle_key_press (~3000), which sets ae.ctx = find_binding(...,ACTX_OVER_GRAPH) ?
  current_input_ctx(...) : ACTX_CANVAS (the 3d.2 refinement — canvas-only keys take the
  CANVAS branch, so do NOT add over_graph rows for canvas-only keys).
- tests/headless/test_key_graph_context.tcl  (the growing key test — extend it; helpers
  check / screen (live coords) / keyat / keyats x y keysym state)
- tests/headless/run.sh  (engine harness — stay 6/6 green)

Gotchas already learned (also in project memory action-registry.md):
- GUI runs with DISPLAY=:0; capture stdout with --pipe:
  `DISPLAY=:0 ./src/xschem --pipe --script FILE`. Drive events with
  `xschem callback .drw <evt> <mx> <my> <keysym> <button> 0 <state>` (KeyPress=2;
  ShiftMask=1, ControlMask=4, Mod1Mask/Alt=8). The keysym, NOT display casing, is what
  the switch matches (bare letter -> lowercase keysym; Shift'd -> uppercase).
- mods normalized per key class: letters strip ShiftMask (kmods=rstate); named keys use
  raw state. Most letter command keys migrate at the rstate==0 (mods 0) chord.
- A migrated act() takes (const ActionEvent *e) and ignores mouse context; it must NOT
  read handle_key_press parameters (c_snap, enable_stretch, infix_interface, ...). Read
  the source instead (tclgetdoublevar("cadsnap"), tclgetboolvar("enable_stretch"), ...).
  Check whether any local mutation in the old branch is actually dead before preserving it.
- Migrate only the CLEAN chord(s); leave a case's other branches (Ctrl/Alt loads,
  dialogs, modal) in C. A single-branch clean case deletes WHOLE; otherwise delete just
  the branch and keep the case + its `break;`.
- Backing: call the exact C fn the switch did (C-backed act) OR `tcl` a global command
  string (Tcl-backed). Don't swap a C fn for its Tcl `xschem ...` equivalent unless you
  verify they're identical.
- Test C-backed acts via the state they change (a tcl var that flips/scales); for a
  Tcl-backed act stub the proc as a counter. Assert rows present + canvas-only (no graph
  rows). Re-run test_accelerators (checks f/s/w have no Tcl bind). Narrow any older
  broad count/scope assertion that a new row trips.

Definition of done:
1. A small clean batch scoped + signed off + a short plan doc written.
2. Keys migrated; whole cases deleted where single-branch-clean; act_* C- or Tcl-backed
   matching the original exactly; registry + canvas binding rows added.
3. Verified EMPIRICALLY (observable tcl var / stubbed proc); engine 6/6 + all GUI smokes
   green. Extend tests/headless/test_key_graph_context.tcl.
4. Behavior-preserving; commit code and docs separately, small steps. Don't push or do
   anything outward-facing without asking.
5. After it lands: update the plan doc d2 status, add a tutorial note, update project
   memory, and refresh THIS next_session_prompt.md for the following batch.

If the clean-key well is running dry, consider pivoting instead to **d3** (generate the
keyboard cheat-sheet from `xschem bindings dump` — self-contained, Tcl-side, no switch
edits) or **d1b** (semaphore `idle_only` flag — unlocks the deferred sem-gated chords).
Propose the pivot with reasoning if so.

Start with the pre-flight: re-grep, run the scan, inspect candidates, propose the batch.
```

---

## Roadmap after batch 3

More d2 clean keys until the well runs dry, then **d1b** (semaphore `idle_only` —
unlocks the 6 deferred sem-first chords + sem-gated command keys), **d3** (cheat-sheet
from `xschem bindings dump`), **d4** (load `keybindings.csv`/`mousebindings.csv` at
startup; fold the new `edit.toggle_stretch`/`view.snap_*` ids into `actions.csv`),
**d5** (delete the dead ladders).

The running user-facing Q&A lives in `code_analysis/action_registry_faq.md` (stamped
with phase + HEAD); add to it when the user asks a keep-worthy question.
