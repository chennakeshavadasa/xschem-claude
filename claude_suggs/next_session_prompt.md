# Opening prompt for the next session (Phase 3 COMPLETE — pick the next direction)

**The Phase-3 refactor plan is complete** (d5b `c36437c2` closed it; see
refactor_plan_action_registry_phase3.md). Keys/wheel/gesture dispatch is one
mechanism (the C input-binding table), remappable at runtime (`xschem bind`) and via
files (keybindings.csv/mousebindings.csv, drift-guarded); actions.csv labels every
bound id; the cheat-sheet renders the live table; the Phase-2 Tcl intercept is gone.

There is NO scoped next step. FIRST ACTION: present the user this decision menu and
wait — do not pick unilaterally:

  a) **Generate more menus from actions.csv.** Only File is generated
     (build_menu_from_table); Edit/View/etc. are hand-written in xschem.tcl
     build_widgets (~1000 lines incl. checkbuttons/radiobuttons, which the table
     schema does NOT yet model — needs new row types, e.g. checkbutton with a
     -variable column). Extends the single-source win; medium effort, mechanical
     once the schema question is settled.
  b) **`xschem action <id>` dispatcher** so the 15 label-only csv rows
     (view.scroll_*, view.pan_*, snap, toggles, zoom_rect) become runnable from the
     palette/menus/scripts. Small C addition (scheduler branch -> find_action_def ->
     run tcl or fn with a synthesized ActionEvent). Must refuse/skip graph.forward
     (needs a real XEvent). Unlocks removing the palette's empty-command skip.
  c) **Derive DISPLAYED accelerators from the live table** — the reverse of the d3
     cheat-sheet: menu -accelerator strings generated from `bindings dump` chords
     (keybinding_chord_label already renders them) instead of the hand-maintained
     accel column; kills the last accel-drift source. Touches menu generation (today
     only File) so it pairs naturally with (a).
  d) **Need-driven only:** stop here; revisit migrations when a concrete need
     appears (dialog keys, cadence_compat mode axis for plain s / Ctrl+r, pan-gesture
     migration which would also take the Button2 skips in waves_selected with it).

Whatever is chosen: behavior-preserving, tested, small commits (code vs docs), short
plan doc first (mirror plan_phase3d5b_dead_remnant_audit.md), update the doc chain +
project memory + THIS prompt after landing.

Standing facts (also project memory action-registry.md):
- GUI: DISPLAY=:0; `DISPLAY=:0 ./src/xschem --pipe -q --script F` captures stdout.
  Drive keys: `xschem callback .drw 2 <mx> <my> <keysym> 0 0 <state>` (KeyPress=2;
  Shift=1,Ctrl=4,Alt=8; letters strip Shift — physical Shift+Z = keysym 90 mods 0).
  `xschem callback` bypasses Tk bindings; `bind .drw <seq>` sees them; `event
  generate` works in the smokes (focus -force .drw first).
- Suite: tests/headless/run.sh (engine 6/6) + smokes: test_accelerators, test_remap,
  test_bindings_file, test_keybindings_help, test_key_graph_context,
  test_mouse_bindings, test_gesture_bindings, test_binding_precedence,
  test_graph_context, test_palette, dump_file_menu.
- keybindings.csv/mousebindings.csv are GENERATED (save_input_bindings_file); after
  ANY init_input_bindings change regenerate both or test_bindings_file fails (drift
  guard, by design).
- actions.csv schema: id,type,menu,label,accel,command,submenu,hook,help,idle —
  empty command = label-only binding-backed row (palette skips); idle=1 =
  action-level mirror of the binding idle_only flag (informational).
- Read lessons_learnt_action_registry.md FIRST for any new work in this area.

Warm-start reads: CLAUDE.md; refactor_plan_action_registry_phase3.md (complete);
lessons_learnt_action_registry.md; tutorial_action_registry_phase3d.md (d1..d5b);
src/action_registry.tcl; src/callback.c action_registry[]/init_input_bindings
(re-grep line numbers).
