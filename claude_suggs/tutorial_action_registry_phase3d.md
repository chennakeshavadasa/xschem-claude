# Phase 3d — bulk key migration: tutorial notes

Companion to `design_phase3d1_tcl_backed_actions.md` (the full design) and
`tutorial_action_registry_phase3c_key_routing.md` (the 3c key-routing machinery).
This file collects the *transferable lessons* per 3d step.

## d1 — Tcl-command-backed actions (commit `11744529`)

3c migrated keys whose behavior was C (each got an `act_*` function). But most of
the switch's command keys are a single `tcleval("…")` — wrapping each in a throwaway
C function would be ~60 lines of boilerplate. d1 lets an action id resolve to a Tcl
command instead.

### The model change is tiny; the gotcha was in the *validator*

The action gains a `tcl` field — "exactly one of `fn`/`tcl` is non-NULL" — and the
dispatch becomes three lines:

```c
if(d->fn)  return d->fn(e);
if(d->tcl) { tcleval(d->tcl); return 1; }
```

The non-obvious part: `xschem bind` validated an action id with
`if(!lookup_action_fn(id)) reject;`. That conflated **two different questions** —
"does this id exist?" and "does it have a C function?" — which were the same thing
until Tcl-backed ids appeared. A Tcl-backed id has *no* C function, so the old check
would have rejected a perfectly valid binding. Fix: introduce `find_action_def`
(returns the def, or NULL only when the id is truly unknown) and validate existence,
not fn-presence.

> **Lesson:** when you add a second backing kind, audit everywhere the *old* kind was
> used as a stand-in for a more general property. "Has a C fn" silently meant "is a
> real action"; splitting the model splits that meaning.

### `B` — the first case to vanish entirely

`B` was the ideal proof key because 3c had already moved its *routing* to the table,
leaving only `tcleval("update_schematic_header")` in the switch — a pure global
command, no semaphore guard, exact chord. Finishing it (register
`sch.edit_header → "update_schematic_header"`, add the canvas row) let the **entire
`case 'B'` be deleted**. That is the template d2 repeats: a key leaves the switch
once *every* chord it handled is a table row.

### Testing a Tcl-backed action without its dialog

`update_schematic_header` opens a dialog — useless in a headless test and a hang
risk. Stub it: `proc update_schematic_header {} { incr ::hdr_calls }`, then assert
the counter moves on a canvas `B` and *doesn't* on an over-graph `B` (forwarded).
Same trick will test most d2 command keys: replace the real proc with an observable
counter.

### What d1 deliberately did NOT solve (so d2 doesn't over-reach)

- **Context-dependent commands** — a Tcl action ignores the `ActionEvent`, so it
  can't pass mouse x/y. Place-at-cursor commands need a substitution mechanism or a
  C wrapper; defer.
- **Semaphore-gated commands** (`n`, `Ctrl+n`, and the 6 chords deferred from 3c) —
  need **d1b** (`idle_only`, checked before `current_input_ctx`) first.
- **`actions.csv` unification** — the default Tcl rows live in C for now; sourcing
  them from CSV is **d4**.

So d2's eligible-now set is exactly: **pure-global `tcleval` branches with no
semaphore guard.** Start there — but mind the canvas-only subtlety below.

## d2 — canvas-only command keys (commits `525bc94f` refinement, `dd0e5909` batch 1)

`B` was *graph-routed* (it had an `over_graph` row), so the dispatch's
`current_input_ctx()` call matched its original `waves_selected` guard. The next
clean keys (`H`, Alt-`h`) are **canvas-only** — they never forwarded to a graph — and
that exposes a gap.

### The canvas-only bug, and the one-line-idea fix

The DEV_KEY dispatch computed `ae.ctx = current_input_ctx(...)` for *every* bound
chord. `current_input_ctx` calls `waves_selected`, which (a) has side effects and (b)
returns `ACTX_OVER_GRAPH` when the pointer is over a graph. For a canvas-only key
whose case you just deleted, that means: pointer over a graph → ctx `OVER_GRAPH` → no
`over_graph` row → fall through → no case → **the key silently does nothing**.

Fix: consult the graph context **only when the chord actually has an `over_graph`
row**.

```c
ae.ctx = find_binding(DEV_KEY, (int)key, kmods, ACTX_OVER_GRAPH)
         ? current_input_ctx(event, key, state, button)   /* graph-routed, as before */
         : ACTX_CANVAS;                                    /* canvas-only: no waves_selected */
```

This is behavior-equivalent for every key that existed before it (they all had
`over_graph` rows), and it's the prerequisite that makes canvas-only migration both
correct and side-effect-free. **Lesson: a uniform "always compute context" is wrong
once some actions have no graph context — compute it only where it can matter.**

### Batch 1: one whole case + one branch, both backing kinds

- `case 'H'` → deleted whole. Two **C-backed** acts (`attach_labels_to_inst(1)`,
  `make_schematic_symbol_from_sel()`) — call the exact C functions the switch did, not
  the Tcl menu equivalents, so behavior is identical.
- Alt-`h` (`schpins_to_sympins`) → **Tcl-backed**; the branch is deleted but `case 'h'`
  stays (it still owns the modal constrained-drag and Ctrl-h launcher). `EQUAL_MODMASK`
  is `Alt|Super`, so it becomes **two** rows (`Mod1Mask`, `Mod4Mask`) — the family
  lesson from §9 again: one source condition can map to several exact rows.

### Testing canvas-only keys

You can't stub a C action, but you can stub the Tcl one: `proc schpins_to_sympins {}
{ incr ::n }`. The decisive check is pressing Alt-`h` **over a graph** and asserting it
*still runs* — that's the bug the refinement prevents, and a plain canvas press
wouldn't catch it.

### Batch 2 — five C-backed command keys (commit `9a8e517a`)

`y` (toggle stretch), `G`/`g` (snap double/half), `T` (`toggle_ignore`), `O` (toggle
colorscheme). Two reusable lessons:

- **A migrated action must not depend on `handle_key_press` parameters.** `G`/`g`
  used the `c_snap` param and `y` toggled the `enable_stretch` param. An `act_*` fn
  doesn't receive those. The fix is to read the *source of truth* the parameters were
  derived from: `c_snap = tclgetdoublevar("cadsnap")` and `enable_stretch =
  tclgetboolvar("enable_stretch")` (both set at the top of `callback()`). Bonus
  catch: `y`'s local `enable_stretch = !enable_stretch` was **dead code** — the
  function returns right after, so only the `tclsetboolvar` mattered. Always check
  whether a local mutation actually escapes before faithfully "preserving" it.
- **Test C-backed actions through the state they change.** No stub needed: `y`→
  `enable_stretch` flips, `O`→`dark_colorscheme` flips, `G`×2 then `g`÷2 round-trips
  `cadsnap`. Only `toggle_ignore` (operates on selection) lacks a clean observable —
  assert the row exists and that it dispatches without error.

Cases `y` and `G` deleted whole; `g`/`T`/`O` kept their `case` (the Ctrl/Alt branches
do semaphore-manipulating loads or dialogs — deferred to d1b/later).

### Batch 3 — four command keys, the first id-reuse, and a graph-routed whole-delete (commit `9687d033`)

`A` (toggle show-netlist), `L` (toggle orthogonal wiring), `=` (Tcl console), `$`
(toggle pixmap drawing). Three new lessons:

- **A graph-routed key can still be whole-deleted.** Earlier whole-deletes (`B`, `H`,
  `y`, `G`) were canvas-only or already-data. `A` was **Group-B graph-routed** — it
  kept an `over_graph -> graph.forward` row while its canvas behavior stayed in the C
  switch. Adding the *canvas* row (`view.toggle_show_netlist`) makes the key fully
  data, so `case 'A'` deletes — **but the over_graph row stays**, so the dispatch keeps
  computing `current_input_ctx()` for `A` (over a graph it still forwards). The only
  reason the case could vanish cleanly: its `rstate==ControlMask` branch was already a
  **canvas no-op** (comment-only; the Ctrl graph cursor is the over_graph row's job).
  Lesson: "whole-delete" needs *every* chord the case handled to be data **or** a
  no-op — graph-routing doesn't block it, a live second canvas branch does.
- **First reuse of an existing `actions.csv` id.** `=` maps to the csv's
  `tools.execute_tcl_command` (tcl `tclcmd`). Batches 1–2 coined new C-only ids; here
  the id already existed in the csv, so the registry row just references it Tcl-backed.
  The d1 validator fix (existence, not fn-presence) is what lets a csv/Tcl id bind.
- **Don't reuse an id whose semantics differ — even if the name fits.** `Z` (Shift+Z
  zoom-in) was the obvious 5th key, but the csv maps `view.zoom_in` → Shift+Z →
  `view_zoom(0.0)` while the C registry **already** binds `view.zoom_in` =
  `view_zoom(CADZOOMSTEP)` to the mouse **wheel**. Same id, two behaviors. That's a d4
  csv/C *reconciliation*, not a migration — picking it would force a colliding or
  duplicate id. Deferred. (Also deferred: `%`/`_`, which are *unconditional* — no mod
  guard — so a whole-case-delete would silently drop their modified-press behavior.)

Test note: `A`/`L` round-trip their tcl vars (`netlist_show`, `orthogonal_wiring`);
`=` stubs `proc tclcmd` as a counter; `$` toggles a C-only flag (`draw_pixmap`, no tcl
var) so it only asserts dispatch-without-error (the `toggle_ignore` pattern). The
existing Group-B `A` checks had to be **narrowed**: the old "Group B has no canvas
rows" assertion explicitly excluded `key 65` once `A` gained its canvas row.
