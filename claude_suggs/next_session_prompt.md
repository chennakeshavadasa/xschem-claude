# Opening prompt for the next session (Phase 3d — first sem-gated full-migration batch, now unblocked by d1b)

Committed on branch `feature/action-registry`: 3a (wheel), 3b (right-drag zoom
gesture), 3c (context-routed keys — complete), 3d.1 (Tcl-command-backed actions; `B`
out), 3d.2 batches 1-3 (`H`, Alt-h, `y`,`G`,`g`,`T`,`O`, `A`,`L`,`=`,`$`), and **3d.1b
(semaphore `idle_only` flag)** — which migrated the graph routing of the 4 sem-first
chords (`a`,`b`,`Ctrl+f`,`Ctrl+s`) and, crucially, **unblocked the sem-gated command
keys for full-data migration.**

Keys/chords out of the switch so far: **B, H, Alt-h, y, G, g, T, O, A, L, =, $** (whole
or branch); plus graph routing for `f`/arrows/Group-B/`t`/the 4 sem-first chords.

The d1b gate means a sem-gated chord can now be **fully** migrated: add an `idle_only`
canvas row (+ over_graph row if it routed to a graph) and **delete the whole case** —
the dispatch skips it at `semaphore>=2` exactly like the old `if(sem>=2)break;`. This is
the natural next batch. Paste the block below into a fresh Claude Code session.

---

```
Goal: scope and implement the FIRST batch of fully-migrated SEMAPHORE-GATED command
keys, now that Phase 3d.1b added the idle_only gate. Behavior-preserving, tested, the
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
3. SKIP already-migrated (B,H,Alt-h,y,G,g,T,O,A,L,=,$ and the routing-only a/b/Ctrl+f/
   Ctrl+s). DEFER anything cadence_compat-gated (plain s, Ctrl+r) or param-dependent
   (`\` fullscreen uses win_path) until a mechanism exists.

STRONG CANDIDATES (verify, don't trust) — clean sem-gated, mostly single-fn/tcleval:
  `?` (help: tcleval "textwindow ...help"), XK_slash `/` (tcleval "show_bindkeys"),
  `&` (trim_wires: push_undo+trim_wires+draw — C), `>`/`<` (draw_single_layer inc / =-1
  — C; note `>` has a quirk line `draw_single_layer = rectcolor` right after the ++,
  read carefully), `*` (postscript/xpm/svg print — 3 branches, each sem-gated; Tcl/C),
  `e`/`i`/`q`/`u`/`o`/`r`/`n`/`j`/`k` letters (many are sem-gated single ops, but several
  ALSO touch mouse/modal — filter with the scan). Prefer the symbol keys + pure
  single-fn letters for batch 1; they whole-delete cleanest.
  NOTE `:` (flat_netlist) and `%`/`_` are UNCONDITIONAL (no sem, no mod guard) — additive
  only (keep case), lower value; not this batch's focus.

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
