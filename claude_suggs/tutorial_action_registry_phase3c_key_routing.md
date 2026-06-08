# Phase 3c c4/c5 — the DEV_KEY dispatch: context-routed *keys* become data

This is the key-side counterpart of the graph-routing tutorial. Where c3 moved the
wheel's graph-vs-canvas routing into the binding table, c4/c5 add a **`DEV_KEY`
dispatch at the top of `handle_key_press`** and migrate the first key — plain `f`
(full-zoom). The machinery is what matters; `f` is just the first thing fed to it.

## 1. What was there before

Inside the ~1600-line `switch (key)` in `handle_key_press`, every key that behaves
differently over a waveform graph carried the *same* 4-line guard at the top of its
branch:

```c
case 'f':
  if(rstate == 0) { /* full zoom */
    int flags = 1;
    if(waves_selected(event, key, state, button)) {   /* <-- the graph guard */
      waves_callback(event, mx, my, key, button, aux, state);
      break;
    }
    if(tclgetboolvar("zoom_full_center")) flags |= 2;
    zoom_full(1, 0, flags, 0.97);
  }
  else if(rstate == ControlMask) { /* search */ ... }
  else if(EQUAL_MODMASK)         { /* flip   */ ... }
  break;
```

That guard is *identical* across ~22 (key, mods) branches (`a`, `A`, `b`, `B`, `f`,
`m`, `s`, `t`, arrows, …). It is exactly the "route to the graph when the pointer is
over one" rule — already captured as the `graph.forward` action and an `over_graph`
binding row in c3. So the migration is mechanical: add table rows, delete the guard.

## 2. The new shape

```c
static void handle_key_press(...)
{
  char str[PATH_MAX + 100];
  int dr_gr;

  /* table-first; switch is the fallthrough */
  {
    int kmods = (key < 0xff00) ? rstate : state;
    if(key_chord_has_binding((int)key, kmods)) {
      ActionEvent ae;
      ae.device = DEV_KEY; ae.code = (int)key; ae.mods = kmods;
      ae.ctx = current_input_ctx(event, key, state, button);
      /* ... mx/my/state/xevent/key/button/aux ... */
      if(dispatch_input_action(&ae)) return;   /* handled: done */
    }
  }

  switch (key) { ... }   /* unchanged for everything not migrated */
}
```

Plus two default rows and a new action:

```c
set_input_binding(DEV_KEY, 'f', 0, ACTX_CANVAS,     "view.zoom_full");
set_input_binding(DEV_KEY, 'f', 0, ACTX_OVER_GRAPH, "graph.forward");
```

`act_zoom_full` holds the canvas behavior (the old `rstate==0` body, verbatim); the
`rstate==0` arm of `case 'f'` is deleted. `Ctrl-f` (search) and `Alt-f` (flip) keep
their arms in the switch — they were not migrated, so their `{f, Ctrl/Alt, *}`
chords have no rows and fall straight through.

## 3. The one trap that shaped the whole design: side effects

`current_input_ctx` calls `waves_selected`, and **`waves_selected` is not a pure
predicate** — when the pointer is over (or leaves) a graph it mutates
`xctx->graph_master`, clears `GRAPHPAN`, reconfigures the `.drw` cursor, and can
call `graph_show_measure stop` (`callback.c:83-107`).

If the dispatch computed `ctx` for *every* keypress, then pressing an un-migrated
key like `g` or `k` while hovering a graph would now fire those side effects, where
before it fired none. That is a behavior change, however subtle.

**The gate fixes this.** `key_chord_has_binding(code, mods)` is a cheap table scan
that runs *before* `current_input_ctx`:

```c
static int key_chord_has_binding(int code, int mods) {
  int i; ensure_input_bindings();
  for(i = 0; i < num_input_bindings; ++i)
    if(input_bindings[i].device==DEV_KEY &&
       input_bindings[i].code==code && input_bindings[i].mods==mods) return 1;
  return 0;
}
```

Only a chord we actually migrated reaches `waves_selected` — and those are exactly
the chords that already called it in their old guard. So **migrated keys preserve
their side-effect contract and un-migrated keys never acquire one.** The dispatch
*could* just return 0 for an unbound chord, but only after computing `ctx`; the gate
keeps the side-effectful call from happening at all.

## 4. The mods-normalization rule

The switch reads modifiers two different ways, and the signature must match:

- **letter / printable keysyms** branch on `rstate` (= `state` with `ShiftMask`
  stripped): `rstate==0`, `rstate==ControlMask`, `EQUAL_MODMASK` (Alt).
- **named keysyms** (arrows, Tab, …) branch on the raw `state`: `state==ControlMask`.

So `kmods = (key < 0xff00) ? rstate : state`. `0xff00` is the X11 boundary between
Latin-1/printable keysyms (`< 0x100`) and the function/keypad block (`0xFF00+`).
`waves_selected` itself strips `ShiftMask` internally, so the `over_graph` match is
Shift-insensitive regardless — but the *canvas* row must key on the same `mods` the
switch would have used, hence the per-class rule.

## 5. Why partial (per-chord) migration is safe

You do **not** have to migrate a whole key at once. Migrate plain `f` and leave
`Ctrl-f`/`Alt-f` in the switch: the dispatch finds no `{f, Ctrl, *}` / `{f, Alt, *}`
row → gate returns false → switch runs them, guards intact. Likewise the `over_graph`
rows are seeded **only for chords that already had a guard** — never broaden, or a
chord that didn't route to the graph before would start to. Migration granularity is
the (key, mods) chord, not the keysym.

## 6. Why `f` reaches the dispatch but never the switch

For plain `f`, *both* `canvas` and `over_graph` rows exist, and both resolve to a
registered action (`view.zoom_full` / `graph.forward`). `current_input_ctx` only ever
returns one of those two contexts, so `dispatch_input_action` always finds a row and
returns 1 → `handle_key_press` returns. The deleted `rstate==0` arm of `case 'f'` is
therefore dead, not merely redundant.

## 7. Proving it in both contexts

`tests/headless/test_key_graph_context.tcl` loads a schematic with a graph rect,
maps schematic→screen coordinates **live** (zooming moves the graph, so it
recomputes per event, unlike the wheel test's cached coords), and fires
`KeyPress` events for `f` (keysym 102):

- over the graph → `graph.forward` → **canvas zoom unchanged**;
- on bare canvas → `view.zoom_full` → **canvas zoom changes** (perturb it first
  with a wheel-zoom so "did full-zoom happen?" is observable).

It also asserts the data is present (`key 102 0 canvas view.zoom_full`,
`key 102 0 graph graph.forward`) and that no `Ctrl-f`/`Alt-f` rows exist. 5/5 pass,
engine harness 6/6, all GUI smokes green. `test_accelerators.tcl` still confirms
`f` has no Tcl-level `<Key-f>` bind — it reaches C via the generic `KeyPress`
handler, which now table-dispatches it.

## 8. Transferable lessons

1. **Audit purity before you hoist a call.** A predicate consulted "once per event"
   is fine only if it has no side effects; `waves_selected` did, so the dispatch had
   to be *gated*, not unconditional. The gate is the load-bearing idea here.
2. **Migrate at the granularity of the conflict** — the (key, mods) chord — so an
   un-migrated chord on the same keysym is provably untouched.
3. **Match the source's modifier convention exactly** (`rstate` for letters, raw
   `state` for named keys) — a "cleaner" uniform rule would change behavior.
4. **Seed rows only where a guard existed.** Uniformity is a bug when the source
   wasn't uniform (cf. the Ctrl-wheel lesson from c3).
5. **A dead branch left as a comment** (the `rstate==0` `f` arm) documents *where*
   the behavior went, which the next migrator needs.

## Appendix: the change

| File | What changed |
|---|---|
| `src/callback.c` | `act_zoom_full` + `view.zoom_full` registry row; `key_chord_has_binding()`; DEV_KEY dispatch atop `handle_key_press`; 2 `f` default rows; deleted the `rstate==0` guard from `case 'f'` |
| `tests/headless/test_key_graph_context.tcl` | new (5 checks): `f` over graph vs canvas, live coord mapping |
| `tests/headless/test_accelerators.tcl` | comment/label clarified: `f` routing is now data, still no Tcl bind |
| `claude_suggs/refactor_plan_action_registry_phase3.md` | c4/c5/c6 marked first-batch done |

Commit `922001f5`. Next: the arrow keys (pan + graph-forward, handling the
"arrows ignore mods" wrinkle), then the Group B routing-only sweep (`a`, `A`, `b`,
`B`, `s`, tab-switch) — over_graph rows + guard deletion, canvas behavior left in C.
