# Opening prompt for the next session (Phase 3d — sem-gated full-migration batch 2)

Committed on branch `feature/action-registry`: 3a (wheel), 3b (right-drag zoom
gesture), 3c (context-routed keys — complete), 3d.1 (Tcl-command-backed actions; `B`
out), 3d.2 batches 1-3 (`H`, Alt-h, `y`,`G`,`g`,`T`,`O`, `A`,`L`,`=`,`$`), **3d.1b
(semaphore `idle_only` flag)** (graph routing of `a`,`b`,`Ctrl+f`,`Ctrl+s`), and **3d.2
sem-gated batch 1** (`n` netlist+clear, `U` redo, `u` undo — first fully-migrated
sem-gated command keys via idle_only).

Keys/chords out of the switch so far: **B, H, Alt-h, y, G, g, T, O, A, L, =, $, n, U**
(whole or branch), **u** (branch); plus graph routing for `f`/arrows/Group-B/`t`/the 4
sem-first chords.

The pattern is now established (see `plan_phase3d2_semgated_batch1.md`): a sem-gated
chord migrates by adding an `idle_only` canvas row → its action and deleting the
case/branch; the dispatch skips it at `semaphore>=2` like the old `if(sem>=2)break;`.
**This session = the NEXT such batch.** Paste the block below into a fresh session.

---

```
Goal: scope and implement the NEXT batch of fully-migrated SEMAPHORE-GATED command
keys (sem-gated batch 2), continuing the idle_only pattern from batch 1
(plan_phase3d2_semgated_batch1.md). Behavior-preserving, tested, the
same rhythm as the d2 batches. No pre-written plan — you scope it, propose 3-5 chords
with my sign-off, write a short plan doc (mirror claude_suggs/plan_phase3d2_batch3.md),
then implement.

WHAT d1b GIVES YOU (read claude_suggs/plan_phase3d1b_idle_only.md +
tutorial_action_registry_phase3d.md §d1b first):
- A binding can be idle_only: the DEV_KEY dispatch skips it when xctx->semaphore>=2,
  BEFORE current_input_ctx (so no waves_selected side effect while busy) — reproducing
  `if(sem>=2)break;`. Seed with set_input_binding_idle(...); or `xschem bind ... idle`.
- `bindings dump` appends " idle" to idle_only rows; the gate is testable via
  `xschem set semaphore <n>` + an observable action.
- So a sem-gated key whose branch is `if(sem>=2)break; <behavior>` migrates by: add an
  idle_only canvas row → <behavior's action> (C- or Tcl-backed), delete the whole case
  (or just the branch if other chords stay). If the key ALSO had a waves guard, add an
  idle_only over_graph→graph.forward row too (that's what the 4 sem-first chords did).

PRE-FLIGHT:
1. Re-grep callback.c line numbers (they shift every batch).
2. Re-run the cleanliness scan, but this time you WANT sem-gated branches. Find ones
   that are sem-gated and OTHERWISE clean (no mouse-coords mousex_snap|mx_double|
   infix_interface, no modal move_objects|new_*|place_|start_line|ui_state, no
   cadence_compat / other untable-able mode condition). Inspect each candidate as-is.
3. SKIP already-migrated (B,H,Alt-h,y,G,g,T,O,A,L,=,$,n,U,u and the routing-only
   a/b/Ctrl+f/Ctrl+s). DEFER anything cadence_compat-gated (plain s, Ctrl+r),
   param-dependent (`\` fullscreen uses win_path), or that manipulates the semaphore
   directly (q quit, o load, the e/I edit-in-new-window branches) until a mechanism
   exists.

STRONG CANDIDATES for batch 2 (verify against scheduler.c, don't trust) — sem-gated,
EXPLICIT mod guard (so whole/branch delete is exact), single-fn:
  `j` (print_hilight_net 1/0/4 across plain/Ctrl/Alt — all sem-gated explicit; but the
  4th SET_MODMASK&&Ctrl branch has no sem guard + murky reachability, read carefully),
  `k` (hilight_net — but check if it depends on mouse position; Ctrl=unhilight_net),
  `K` (delete hilighted nets — read it), `Q` (plain edit_property(1) sem-gated; Ctrl
  edit_property(2) NOT sem-gated — both dialogs, test via gate not by opening them),
  `J` (print_hilight_net 2). Prefer C-backed acts calling the exact fn; verify any csv
  Tcl reuse equals the C call (the `e` trap: xschem descend ≠ the key's descend params).
  AVOID for now: `?`,`/`,`&`,`>`,`<`,`*`,`:` (UNCONDITIONAL — no mod guard — so
  whole-delete changes modified-press behavior; additive-only, lower value);
  `%`/`_` (also unconditional).

BACKINGS: call the exact C fn the switch did (C-backed act) OR a global tcl command
string (Tcl-backed). For a tcleval branch, prefer Tcl-backed reusing an actions.csv id
if one exists (grep src/actions.csv); else coin a C id (fold into csv at d4). Don't swap
a C fn for its `xschem ...` Tcl equivalent unless verified identical.

TEST (extend tests/headless/test_key_graph_context.tcl):
- rows present (+ " idle" marker on the new idle_only rows; canvas-only keys have no
  graph row).
- the action fires when idle: observe its effect (tcl var flip, or stub a Tcl proc as a
  counter). For destructive canvas ops (dialogs), prove via the idle GATE on a probe
  like d1b did, or assert dispatch-without-error + rows.
- the idle GATE: `xschem set semaphore 2` → the migrated key does NOT fire; reset to 0 →
  it does. (Reset semaphore to 0 afterwards — leaving it high wedges later checks.)
- Re-run the full suite: engine run.sh 6/6, all GUI smokes green. Watch for older
  count/glob assertions tripped by new rows (narrow them, as every batch has).

Warm-start reads:
- CLAUDE.md; claude_suggs/refactor_plan_action_registry_phase3.md (d1b DONE, d2/d3/d4/d5)
- claude_suggs/plan_phase3d1b_idle_only.md (the gate; the cadence_compat deferral)
- claude_suggs/tutorial_action_registry_phase3d.md (all d1/d2/d1b lessons)
- src/callback.c — RE-GREP: action_registry[] + find_action_def (~2325-2400); act_* fns
  above it; set_input_binding_idle + key_chord_is_idle_only (~2415-2455);
  init_input_bindings (~2435-2545); the DEV_KEY dispatch gate (~3095) — idle term is
  already folded into the `if(...)` condition there.
- tests/headless/run.sh (engine 6/6)

Gotchas (also project memory action-registry.md):
- GUI: DISPLAY=:0, capture with --pipe: `DISPLAY=:0 ./src/xschem --pipe -q --script FILE`.
  Drive events: `xschem callback .drw 2 <mx> <my> <keysym> 0 0 <state>` (KeyPress=2;
  Shift=1,Ctrl=4,Alt=8). kmods=(key<0xff00)?rstate:state; letters strip Shift.
- A migrated act() takes (const ActionEvent*e), ignores mouse ctx, must NOT read
  handle_key_press params — read the source (tcl var / xctx field).
- Whole-delete a case only when EVERY chord it handled is data-or-noop; else delete the
  branch and keep the case + break. For a sem-gated chord, the idle_only row replaces
  the `if(sem>=2)break;` — confirm the branch had NOTHING else before the break.
- Commit code and docs separately; don't push or do anything outward-facing without asking.

DoD:
1. Small sem-gated batch scoped + signed off + short plan doc.
2. idle_only rows added (canvas, + over_graph if it routed); cases whole-deleted where
   single-branch; acts match the originals exactly.
3. Verified empirically (effect or gate-via-semaphore probe); engine 6/6 + smokes green;
   test extended.
4. After it lands: update plan/tutorial/refactor-plan/memory and refresh THIS prompt.

Start with the pre-flight: re-grep, scan for clean sem-gated branches, propose the batch.
```

---

## Roadmap after this batch

- More sem-gated full-migration batches (the bulk of the remaining switch) until that
  well thins.
- **d3** cheat-sheet from `xschem bindings dump` (can now show `idle`).
- **d4** load `keybindings.csv`/`mousebindings.csv` at startup (incl. an `idle` column);
  **fold the C-only ids into `actions.csv`** (`edit.toggle_stretch`, `view.snap_half`,
  `view.snap_double`, `view.toggle_show_netlist`, `edit.toggle_orthogonal_wiring`,
  `view.toggle_draw_pixmap`); **reconcile `Z`/`view.zoom_in`** (wheel CADZOOMSTEP vs
  Shift+Z `view_zoom(0.0)` — distinct ids). Consider a `cadence_compat` axis so plain
  `s`/`Ctrl+r` can migrate.
- **d5** delete the dead switch ladders.

The running user-facing Q&A lives in `code_analysis/action_registry_faq.md` (stamped
with phase + HEAD); add to it when the user asks a keep-worthy question.
