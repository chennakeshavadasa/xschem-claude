# Opening prompt for the next session (Phase 3d — d5b: dead-remnant audit; then choose a new direction)

Goal: d5b — a small, behavior-preserving audit/cleanup of remnants the migrations left
behind; then STOP and pick the next direction WITH the user. d5a is DONE (`07c1d4d9`):
the Phase-2 Tk intercept is retired, migrated_action_ids is empty, Z/Ctrl+z are table
rows, u/U un-shadowed (and the GUI idle-gate divergence fixed). One mechanism per key.

  d5b candidates (verify each is PROVABLY dead before deleting; inspect as-is first):
  - Button2 special-casing in the callback skip logic (noted at Phase 3b as a cleanup
    candidate; it blocked rebinding zoom-rect to button 2). Re-grep callback.c for
    Button2 near the top of callback(); understand WHY it skips (autorepeat? pan?)
    before touching — if it's load-bearing for middle-drag pan, leave it + document.
  - keys.help vs the generated cheat-sheet: two help texts can disagree (keys.help is
    hand-written; show_keybindings_help reads the live table). Options: point the old
    Help menu entry at show_keybindings_help, add a "see also" note, or leave + record.
    Don't delete keys.help (it documents many un-migrated keys the sheet doesn't show).
  - Stale comments referencing deleted cases / "fold in at d4" / "not yet in csv"
    (grep callback.c + action_registry.tcl + actions.csv header; most were updated at
    d4a/d5a but sweep once).
  - The Phase-2 machinery (accel_to_tk_sequence, bind_accelerators_from_table,
    remap_action_accel, accel_bound_seqs): now inert over the empty list. DECIDE with
    evidence: delete (smaller surface; test_remap no longer uses remap_action_accel)
    or keep (documented escape hatch). If deleting, also drop the accel column? NO —
    accel is still DISPLAYED in menus/palette; keep the column, delete only the procs
    nothing calls. grep first: build_menu_from_table uses accel for -accelerator;
    palette prints it.

  AFTER d5b, the refactor plan's checkboxes are complete. Present the user a short
  decision menu (do NOT pick unilaterally):
  a) generate more menus from actions.csv (only File is generated; Edit/View/... are
     hand-written in xschem.tcl build_widgets) — extends the single-source win.
  b) `xschem action <id>` C dispatcher so label-only rows (view.scroll_* etc.) become
     palette-runnable (needs a synthesized ActionEvent; refuse graph.forward).
  c) accel-column truth: derive the DISPLAYED accelerators from the live table (the
     reverse of the d3 cheat-sheet: menus show what keys actually do; kills the last
     hand-maintained accel drift).
  d) continue migrations only on concrete need (dialog keys, cadence_compat axis for
     plain s / Ctrl+r) — the clean well is dry; each needs new mechanism.

Behavior-preserving, tested, small commits (split code vs docs). Scope -> short plan
doc (mirror plan_phase3d5a_retire_tk_intercept.md) -> implement.

PRE-FLIGHT:
1. Re-grep callback.c line numbers (they shift every batch).
2. For each d5b candidate: read the code as it is NOW; classify keep/document/delete
   with the reason; propose the batch before editing.
3. grep for callers before deleting any proc (test_remap was rewritten at d5a and no
   longer calls remap_action_accel — verify nothing else does).

TEST:
- engine run.sh 6/6 + ALL smokes (test_accelerators, test_remap, test_bindings_file,
  test_keybindings_help, test_key_graph_context, test_mouse_bindings,
  test_gesture_bindings, test_binding_precedence, test_graph_context, test_palette,
  dump_file_menu). If a proc is deleted, the deletion IS the test change — make sure
  no smoke references it.
- The shipped keybindings.csv/mousebindings.csv are GENERATED: after ANY
  init_input_bindings change, regenerate via save_input_bindings_file ({key} and
  {wheel button}) or test_bindings_file fails — by design, not a flake.

Warm-start reads:
- CLAUDE.md; claude_suggs/refactor_plan_action_registry_phase3.md (d5a done, d5b last)
- claude_suggs/lessons_learnt_action_registry.md (READ FIRST; note the d5a lesson:
  two dispatch mechanisms for one chord WILL diverge — test at the layer where they
  meet; `xschem callback` bypasses Tk bindings, `bind .drw <seq>` sees them)
- claude_suggs/plan_phase3d5a_retire_tk_intercept.md (the retirement just landed)
- claude_suggs/tutorial_action_registry_phase3d.md (d1..d5a chronological)
- src/action_registry.tcl (Phase-2 remnants near the top; loader/saver; cheat-sheet)
- src/callback.c — action_registry[] + init_input_bindings (re-grep; ~2330-2620)

Gotchas (also project memory action-registry.md):
- GUI: DISPLAY=:0, capture with --pipe: `DISPLAY=:0 ./src/xschem --pipe -q --script F`.
  Drive events: `xschem callback .drw 2 <mx> <my> <keysym> 0 0 <state>` (KeyPress=2;
  Shift=1,Ctrl=4,Alt=8); kmods=(key<0xff00)?rstate:state, letters strip Shift.
  `event generate .drw <seq>` works in these smokes (focus -force .drw first).
- Whole-delete a case only when EVERY chord it handled is data-or-noop.
- Commit code and docs separately; don't push or do anything outward-facing without
  asking.

DoD:
1. d5b audited: each candidate keep/document/delete with evidence; small plan doc.
2. Anything deleted is provably dead (no callers, no test refs); suite green.
3. Docs chain updated (plan/tutorial/refactor-plan/memory) + refresh THIS prompt with
   the user's chosen next direction (a/b/c/d above).

Start with the pre-flight: inspect the four d5b candidates and propose the
keep/document/delete split.
