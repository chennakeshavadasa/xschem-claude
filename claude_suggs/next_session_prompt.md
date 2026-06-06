# Opening prompt for the next session (Phase 2 — data-driven shortcuts)

Phase 1 (action table + generated File menu + command palette) is committed on
branch `feature/action-registry`. Paste the block below as the first message of a
fresh Claude Code session, run from this repo directory so the referenced files
are on disk. It is objective-first and points at the already-committed artifacts
so the new session starts warm.

> Note: this is **Track A** from the end-of-Phase-1 discussion — the plan's named
> Phase 2 (make keyboard shortcuts data-driven). The lower-risk alternative
> (**Track B**: a `toggle` row type + generating the other menus) is sketched at
> the bottom; swap it in if you'd rather extend the menu pattern than touch the
> keyboard path.

---

```
Goal for this session: Phase 2 of the action-registry work — make keyboard
shortcuts DATA-DRIVEN. Generate the key bindings from the action table and pre-empt
the C keysym chain via Tk binding-specificity (the same trick the Ctrl+Shift+P
palette uses), so shortcuts become remappable and the keybindings cheat-sheet is
generated from the table and can't drift. UI-layer (Tcl) only; do NOT edit the C
engine (callback.c / handle_key_press stays untouched — we intercept ABOVE it).

Warm-start context — read these first instead of re-analyzing the codebase:
- CLAUDE.md  (architecture, build, the `xschem` Tcl dispatcher)
- claude_suggs/refactor_plan_action_registry.md  (THE plan; see Phase 2)
- claude_suggs/tutorial_action_registry.md  (what Phase 1 built + the
  binding-specificity trick in section 6 + the "add an action" quickstart)
- src/actions.csv  +  src/action_registry.tcl  (the table + generators to extend)
- src/callback.c, handle_key_press (~line 2519)  (READ-ONLY: the current
  key->command source of truth you must mirror; do not edit it)
- src/keys.help  (the prose cheat-sheet to retire)
- src/xschem.tcl, proc set_bindings (~line 9952)  (where the palette binding
  lives; where generated bindings get installed)
- tests/headless/run.sh  (engine harness — must stay 6/6 green)
- tests/headless/dump_file_menu.tcl, test_palette.tcl  (GUI-smoke patterns to copy)

Key gotchas already learned (in the project memory): the GUI runs here with
DISPLAY=:0; to capture a script's stdout you MUST pass `--pipe`
(`DISPLAY=:0 ./src/xschem --pipe --script FILE`); the canonical binding form is
`<Control-Shift-Key-P>` (the shorthand does not fire); a more-specific Tk binding
pre-empts the generic `<KeyPress>` on the same widget, so C never sees that key.

Definition of done for this session:
1. An accel->Tk-sequence translator: turn the table's `accel` display strings into
   real Tk event patterns ("Ctrl+S"->`<Control-Key-s>`, "Shift+Z"->`<Key-Z>`,
   "Alt-F"->`<Alt-Key-f>`, plain "F"->`<Key-f>`). Explicitly skip/flag the ones
   that aren't a single keyboard shortcut (e.g. "Ins, Shift-I", "Alt-Right Butt.",
   "Print Scrn", and symbol keys # & = * if they need special handling).
2. A generator `bind_accelerators_from_table` that installs those bindings on the
   drawing widget in set_bindings, each running the row's `command`, each
   pre-empting the generic `<KeyPress>` (so C is bypassed for migrated keys only).
3. Do it in SMALL BATCHES, behavior-preserving. Start with a handful of
   unambiguous global command keys that C currently runs via `tcleval("xschem ...")`
   with no modal state. For every migrated key, verify empirically that the
   generated binding runs the SAME action C did (press the key in the GUI and
   observe; compare against the C branch's command string). Do NOT trust the accel
   display string — verify the real keysym.
4. Generate the keybindings cheat-sheet (Show Keybindings / replace keys.help)
   FROM the table so it is always accurate.
5. Demonstrate remapping ONE key end-to-end (change its accel in the table -> the
   binding follows) to prove "data-driven" is real.
6. callback.c stays UNTOUCHED. Modal/stateful keys (live drag/move, constr_mv,
   graph measure, context_menu, anything that depends on in-progress editing
   state) STAY in C — do not migrate them.

Constraints / how I want you to work:
- Behavior-preserving: tests/headless/run.sh green after every batch; commit small,
  in logical steps. Confirm un-migrated keys still work after each batch.
- Continue on branch feature/action-registry (or a new branch off it). Don't push
  or do anything outward-facing without asking.
- Launch the GUI early (DISPLAY=:0) so I can watch shortcuts behave before/after.

Start by, BEFORE binding anything: (a) read handle_key_press and give me a list
that splits the key handlers into "clean command keys, safe to migrate" vs "modal/
stateful, leave in C"; (b) propose the accel->sequence translation rules and the
first migration batch; get my sign-off on both.
```

---

## Why it's shaped this way
- **Objective + "done" in the first lines**, engine explicitly off-limits — same
  habit that kept Phase 1 on the safe seam.
- **Warm-start pointers** to the committed Phase 1 artifacts (table, generators,
  tutorial) and the read-only C source of truth, so the session mirrors current
  behavior instead of re-deriving it.
- **Pre-flight analysis before any binding** (split migratable vs modal keys, agree
  the translation rules) — the riskiest part is deciding which keys are safe, so
  that decision is gated on your sign-off.
- **Small batches + empirical per-key verification** — accel strings lie about real
  keysyms and C handles some keys contextually, so each migrated key is checked
  against current behavior.

## Before starting that session
- Decide branch state: Phase 1 lives on `feature/action-registry` (not pushed).
  Either continue there or branch off it.
- Run the session from this repo directory so the referenced files exist on disk.

## Alternative — Track B (lower risk, menu completeness / Phase 3 prep)
If you'd rather extend the proven menu pattern than touch the keyboard path, swap
the goal to: add a `toggle` row type to the table + generator for the 46
checkbutton / 15 radiobutton options; extract the 22 inline-script menu commands
into named procs and add them as rows; then generate a second and third menu
(Edit — mostly clean commands; Options/View — toggle-heavy) from the table,
verifying each with a dump-menu diff like tests/headless/dump_file_menu.tcl. Same
constraints (engine untouched, harness green, small commits, no push).
