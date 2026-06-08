# Opening prompt for the next session (Phase 3c — steps c4/c5: data-driven keys)

Phases 3a (wheel), 3b (right-drag zoom gesture) and 3c c1–c3 (context-aware
dispatch + wheel graph-routing) are committed on branch `feature/action-registry`.
Paste the block below as the first message of a **fresh** Claude Code session, run
from this repo directory. It is objective-first and points at the committed
artifacts so the new session starts warm — and explicitly tells it NOT to trust
remembered line numbers (this is the riskiest slice: editing the 1600-line
`handle_key_press`).

> Why a fresh session: c4/c5 needs careful reading of the *current* state of
> `handle_key_press`, and a new session re-reads the real code instead of leaning
> on stale in-context facts. The plan doc + memory + tutorials are the handoff.

---

```
Goal for this session: Phase 3c steps c4+c5 of the action-registry input work —
make the CONTEXT-ROUTED KEYS data-driven. Today the keys that behave differently
over a waveform graph (e.g. s, f, a, m, arrows) are hardcoded inside the
1600-line handle_key_press switch as per-case `if(waves_selected(...)){ waves_callback(...); ...}`
guards. Migrate a first small batch of them into the binding table by adding a
DEV_KEY dispatch at the TOP of handle_key_press (table-first, switch as
fallthrough), with key+context rows (canvas vs over_graph), reusing the
infrastructure already built (registry, binding table, current_input_ctx,
graph.forward, dispatch_input_action with most-specific-wins precedence).

FIRST, before editing anything: re-grep current line numbers — callback.c grows
each phase and remembered numbers go stale. Then read handle_key_press as it is
NOW, and give me a classification: which context-routed keys are SAFE to migrate
this batch vs which must STAY in C (modal/stateful). Get my sign-off before coding.

Warm-start context — read these first instead of re-deriving:
- CLAUDE.md  (architecture, build, the `xschem` Tcl dispatcher)
- claude_suggs/refactor_plan_action_registry_phase3.md  (THE plan; Phase 3c
  section has the c4/c5/c6 atomic steps + design + risks + success criteria)
- claude_suggs/tutorial_action_registry_phase3.md  (the C-side architecture:
  ActionEvent, registry, binding table, dispatch — the machinery you extend)
- claude_suggs/tutorial_action_registry_phase3c.md  (most-specific-wins precedence)
- claude_suggs/tutorial_action_registry_phase3c_graph_routing.md  (current_input_ctx,
  graph.forward, the per-branch-context trap, the schematic->screen test transform)
- code_analysis/guided_diff_walkthrough_action_registry_phase3.md  (read-the-diff
  companion: where every piece lives in callback.c)
- src/callback.c — RE-GREP, but as of this writing:
    * input-binding section starts ~line 2191 (enums/ActionEvent, act_* functions,
      action_registry[], InputBinding table + find_binding/set/unset/init,
      current_input_ctx ~2359, dispatch_input_action ~2367)
    * handle_mouse_wheel ~2545  (THE PATTERN TO MIRROR: compute mods + ctx per
      branch, build ActionEvent, dispatch, preserve the return contract)
    * handle_key_press ~2857, `switch (key)` ~2864  (the function you add a
      DEV_KEY dispatch in FRONT of; read it to classify keys)
- src/scheduler.c — `bind`/`bindings` in case 'b', `unbind` in case 'u'
  (the dispatcher switches on the subcommand's FIRST LETTER — keep that in mind
  if you add any subcommand)
- tests/headless/test_graph_context.tcl  (graph fixture + schematic->screen
  transform to copy), test_binding_precedence.tcl, test_mouse_bindings.tcl
- tests/headless/run.sh  (engine harness — must stay 6/6 green)

Gotchas already learned (also in project memory):
- GUI runs here with DISPLAY=:0; to capture a script's stdout you MUST pass --pipe:
  `DISPLAY=:0 ./src/xschem --pipe --script FILE`.
- Drive events from a test with `xschem callback .drw <evt> <mx> <my> <keysym> <button> 0 <state>`
  (ButtonPress=4, ButtonRelease=5, MotionNotify=6, KeyPress=2; ShiftMask=1,
  ControlMask=4). Assert on observable state: `xschem get zoom|xorigin|yorigin|ui_state`.
- The keysym, NOT the display casing, is what the switch matches: bare letter ->
  lowercase keysym (case 'a'), Shift'd -> uppercase (case 'A'). Mirror how mods are
  computed (rstate = state without ShiftMask; cases test rstate==ControlMask etc.).
- Graph-context test fixture: load xschem_library/examples/tb_test_evaluated_param.sch
  (graph rect at schematic 540,-740..1200,-340), zoom_full, map schematic->screen
  with s=(sch+origin)/zoom  (transform X_TO_XSCHEM(s)=s*zoom-origin, xschem.h:395);
  set `graph_use_ctrl_key 0` so a no-modifier event consults the graph.
- view_zoom also shifts xorigin/yorigin (zoom-toward-cursor), so the clean
  discriminator between a zoom and a pan is "did `zoom` change?".
- Adding a new device/context tends to break a hardcoded COUNT assertion in an
  older test — scope counts to what the test owns (e.g. canvas wheel rows).

Definition of done for this session (c4/c5, in SMALL batches):
1. Extract a first batch of context-routed keys' behaviors into named act_* fns
   (ids matching src/actions.csv where one exists). Pick CLEAN ones first.
2. Add a DEV_KEY dispatch at the TOP of handle_key_press: build a signature
   {DEV_KEY, keysym, mods, ctx=current_input_ctx(...)}, call dispatch_input_action;
   if it ran, return; else fall through to the existing switch unchanged.
3. Seed key rows: a `canvas` row -> the extracted action, and an `over_graph` row
   -> graph.forward (already exists). Then DELETE that key's per-case
   waves_selected guard from the switch.
4. Verify EMPIRICALLY in BOTH contexts (pointer over a graph vs on canvas) that
   behavior is identical to before, and that un-migrated keys still reach C.
   Add/extend a headless test (model on test_graph_context.tcl).
5. Keep handle_key_press's switch as the fallthrough for everything not migrated.
   Modal/stateful keys (infix placement, move-start, constr_mv drag h/v, flip
   F/V during move, Esc, Del, anything depending on in-progress edit state) STAY
   in C — do NOT migrate them.

How I want you to work:
- Behavior-preserving; engine harness 6/6 + all GUI smokes green after EVERY batch;
  commit small, in logical steps. Continue on branch feature/action-registry.
- Don't push or do anything outward-facing without asking. Launch the GUI early
  (DISPLAY=:0) so I can watch keys behave before/after.
- After the code lands: update the Phase 3c checkboxes in the plan doc, update the
  project memory, and (matching the established rhythm) write a short tutorial-style
  note for the step.

Start with the pre-flight: re-grep line numbers, read handle_key_press, propose
(a) the migrate-now vs leave-in-C key classification and (b) the keysym/mods
signature scheme + first batch. Wait for my sign-off before binding anything.
```

---

## Why it's shaped this way
- **Objective + "done" up front, riskiest-thing-flagged.** c4/c5 edits the giant
  `handle_key_press`; the prompt forces a re-grep and a read-then-classify gate
  before any edit, because picking which keys are safe is the actual risk.
- **Warm-start pointers** to the committed Phase 3 artifacts (plan, the three
  tutorials, the guided-diff walkthrough) and the read-it-now C source, with the
  explicit "line numbers go stale, re-grep" warning.
- **Mirror the proven pattern** (`handle_mouse_wheel`) rather than invent: compute
  ctx per branch, dispatch, fall through — the table-first/switch-fallthrough shape
  is exactly how 3a–3c stayed behavior-preserving.
- **Both-context empirical verification + small batches** — the same discipline
  that kept every prior slice green.

## Before starting that session
- Run it from this repo directory so the referenced files exist on disk.
- Branch `feature/action-registry` is not pushed; continue there or branch off it.
- Working tree has two unrelated stragglers (`src/cadence_style_rc`, `untitled.sch`)
  — leave them alone.

## After c4/c5: what remains in Phase 3
- **c6** — final both-context verification pass for the migrated keys.
- **3d** — bulk-migrate the remaining ~65 clean `tcleval` keys + the cheat-sheet
  generation from `xschem bindings dump`; needs a new piece (an action id resolving
  to a Tcl command string, not only a C fn). See the plan's Phase 3d section.
