# Opening prompt for the next session (Phase 3d.2 — batch 3: more clean command keys)

Phases 3a (wheel), 3b (right-drag zoom gesture), 3c (context-routed keys, migration
complete), 3d.1 (Tcl-command-backed actions; `B` migrated out), 3d.2 dispatch
refinement + batch 1 (`H`, Alt-`h`) + batch 2 (`y`, `G`, `g`, `T`, `O`) are committed
on branch `feature/action-registry`.

> NOTE: the block below still describes BATCH 2 (now done). For batch 3, the task is
> the same SHAPE — re-run the classification scan in `handle_key_press` for branches
> with no `semaphore>=2` / `waves_selected` / mouse-coords / modal `ui_state`, scope a
> small set, write a short plan like `plan_phase3d2_batch2.md`, and migrate it the same
> way. Reuse every gotcha below. Keys already done: B, H, Alt-h, y, G, g, T, O. Likely
> next candidates to inspect: remaining single-fn/single-tcleval branches (e.g. `L`
> orthogonal toggle has a small modal flag — check it). Or pivot to **d3** (generate the
> cheat-sheet from `xschem bindings dump`) or **d1b** (semaphore `idle_only`).

Paste the block below as the first message of a **fresh** Claude Code session, run
from this repo directory. It's objective-first and points at the committed artifacts
so the new session starts warm — and tells it NOT to trust remembered line numbers
(`handle_key_press` is ~1600 lines and shifts every batch).

---

```
Goal for this session: Phase 3d.2 batch 2 of the action-registry input work —
migrate the next cluster of CLEAN canvas-only command keys out of the giant
handle_key_press switch into the data-driven binding table. The exact batch is
already scoped in claude_suggs/plan_phase3d2_batch2.md: keys y (toggle stretch),
G/g (snap double/half), T (toggle_ignore), O (toggle colorscheme). Implement that
plan in small, tested, behavior-preserving steps and get the switch to shrink
(case 'y' and case 'G' should disappear entirely).

FIRST, before editing anything: re-grep current line numbers — callback.c grows
each batch and remembered numbers are stale. Read the plan doc, then read each
target case AS IT IS NOW and confirm it still matches the plan (no semaphore guard,
no waves_selected, no mouse coords, no modal ui_state) before migrating it. If a
case no longer matches, flag it and adjust rather than forcing it.

Warm-start context — read these first instead of re-deriving:
- CLAUDE.md  (architecture, build, the `xschem` Tcl dispatcher)
- claude_suggs/plan_phase3d2_batch2.md  (THE batch plan: the 5 keys, exact act_
  bodies, the two wrinkles already resolved, ids, which cases delete whole vs
  branch-only, the test approach, risks, definition of done)
- claude_suggs/design_phase3d1_tcl_backed_actions.md  (how Tcl-backed actions work:
  the `tcl` field on ActionDef, find_action_def, the dispatch, the bind-validator)
- claude_suggs/tutorial_action_registry_phase3d.md  (d1 + d2 lessons: the validator
  gotcha, the canvas-only dispatch refinement and WHY it's needed, EQUAL_MODMASK ->
  two rows, how to test a migrated key)
- claude_suggs/refactor_plan_action_registry_phase3.md  (the overall Phase 3 plan;
  d2 section has batch-1 status; d1b is the deferred semaphore work)
- src/callback.c — RE-GREP, but the machinery lives around:
    * ActionDef struct + action_registry[] + find_action_def (~2270-2310)
    * act_* behavior fns (~2229-2270) — add the new ones here
    * init_input_bindings (seed DEV_KEY canvas rows here; ~2360-2420)
    * the DEV_KEY dispatch at the TOP of handle_key_press (~2960) — note it now
      sets ae.ctx via `find_binding(...,ACTX_OVER_GRAPH) ? current_input_ctx(...)
      : ACTX_CANVAS` (the 3d.2 refinement; canvas-only keys take the CANVAS branch)
    * switch(key) — the cases to migrate: 'y','G','g','T','O'
- tests/headless/test_key_graph_context.tcl  (the growing key test — extend it;
  it has helpers: check, screen (live coords), keyat, keyats x y keysym state)
- tests/headless/run.sh  (engine harness — must stay 6/6 green)

Gotchas already learned (also in project memory action-registry.md):
- GUI runs here with DISPLAY=:0; to capture a script's stdout you MUST pass --pipe:
  `DISPLAY=:0 ./src/xschem --pipe --script FILE`. Drive events with
  `xschem callback .drw <evt> <mx> <my> <keysym> <button> 0 <state>` (KeyPress=2;
  ShiftMask=1, ControlMask=4, Mod1Mask/Alt=8). The keysym, NOT the display casing,
  is what the switch matches (bare letter -> lowercase keysym; Shift'd -> uppercase).
- mods are normalized per key class in the dispatch: letters strip ShiftMask
  (kmods=rstate); named keys (arrows/Tab) use raw state. For these batch-2 letter
  keys the chord is rstate==0, so seed rows at mods 0.
- CANVAS-ONLY keys (these 5) have NO over_graph row. The 3d.2 refinement makes the
  dispatch use ACTX_CANVAS directly for them (no waves_selected) — which is what
  lets you delete their case and still have them work when the pointer is over a
  graph. Do NOT add over_graph rows for these (they never forwarded).
- Two param wrinkles, already solved in the plan: G/g read the snap via
  tclgetdoublevar("cadsnap") (that's how the c_snap param is derived,
  callback.c:5207); y must flip the enable_stretch tcl var
  (tclsetboolvar("enable_stretch", !tclgetboolvar(...))) because the local param
  toggle is dead code after the function returns.
- Only migrate the PLAIN (rstate==0) branch of g/T/O — their Ctrl/Alt branches do
  semaphore manipulation or open dialogs and STAY in C. case 'y' and case 'G' are
  single-branch and delete whole.
- Test via observable Tcl vars: y -> enable_stretch flips, O -> dark_colorscheme
  flips, G -> cadsnap doubles, g -> cadsnap halves. T (toggle_ignore) has no clean
  observable -> assert the row is present + it doesn't error. For a Tcl-backed
  action you can stub the proc as a counter; these are C-backed so use the vars.
- Adding rows tends to break an older test's broad count/scope assertion — narrow it
  to what the test owns (this bit us when Ctrl+arrow rows broke a "no modified-arrow
  rows" check). Re-run test_accelerators (it checks f/s/w have no Tcl bind).

Definition of done for this session:
1. The 5 keys migrated per the plan; case 'y' and case 'G' deleted; the plain
   branch removed from g/T/O (Ctrl/Alt branches untouched).
2. New act_* fns are C-backed (call the exact C the switch did / flip the exact tcl
   var); registry rows added (reuse the 2 csv ids, register the 3 new ones in C).
3. Verified EMPIRICALLY: each migrated key produces the identical observable effect
   on canvas; canvas-only keys still work with the pointer over a graph. Extend
   tests/headless/test_key_graph_context.tcl.
4. Engine harness 6/6 + all GUI smokes green after the batch.
5. Behavior-preserving throughout; commit code and docs separately, small steps,
   continue on branch feature/action-registry. Don't push or do anything
   outward-facing without asking.
6. After it lands: tick the d2 batch-2 status in the plan doc, add a short tutorial
   note (tutorial_action_registry_phase3d.md), update project memory, and refresh
   THIS next_session_prompt.md for the following batch.

How I want you to work:
- Re-grep before editing; read the real current code; behavior-preserving; small
  commits in logical steps. Launch the GUI early (DISPLAY=:0) so I can watch keys
  behave before/after if I want.
- If you hit a key that's less clean than the plan assumed (a hidden sem guard, a
  mouse-coord dependency), STOP and flag it — defer it rather than force it.

Start with the pre-flight: re-grep line numbers, read the plan doc and the 5 target
cases as they are NOW, confirm they still match, then implement in 1-2 small commits.
```

---

## After batch 2

Remaining d2: more clean command keys (re-run the classification scan in callback.c
for branches with no `semaphore>=2` / `waves_selected` / mouse-coords / modal
`ui_state`). Then **d1b** (semaphore `idle_only` flag — unlocks the 6 deferred
sem-first chords + sem-gated command keys), **d3** (generate the cheat-sheet from
`xschem bindings dump`), **d4** (load `keybindings.csv`/`mousebindings.csv` at
startup; unify the new ids into `actions.csv`), **d5** (delete the dead ladders).

The running Q&A for the user lives in `code_analysis/action_registry_faq.md`
(stamped with phase + HEAD); add to it when the user asks a keep-worthy question.
