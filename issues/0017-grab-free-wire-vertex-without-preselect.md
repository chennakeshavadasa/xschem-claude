# Issue 0017 — dragging a free wire vertex should stretch/shorten it directly, without a pre-select step

**Opened:** 2026-06-20
**Status:** OPEN — feature / UX gap (not a regression). Specified here with a RED-first
plan; not yet implemented.
**Affects:** interactive editing — grabbing the end of a wire. Most relevant to the
`cadence_compat` / fluid-editing experience.
**Severity:** low (workaround exists: select the wire first) but high-frequency, so the
friction is felt constantly.
**Branch:** `fluid-editing`.
**Related:** [[wire-editing-on-move]]; [[cadence-modifier-drag]]; the intuitive
direct-drag dispatch in `handle_button_press` (`src/callback.c`); `add_wire_from_wire`
(callback.c:2044), `edit_wire_point` (callback.c:2102).

---

## 1. Symptom

You cannot click-and-drag the **free (dangling) endpoint** of a wire to move it — e.g.
to drag it *toward the other end and shorten the wire*. Pressing on the endpoint and
dragging instead **starts drawing a brand-new wire** from that point. To actually move
the endpoint you must **first select the wire** (click it), and *then* grab the vertex.
That extra "select first" step is exactly the friction a fluid editor should not have.

```
   want:  ●─────────●   grab the free end ───▶  ●────●     (drag toward the other end = shorter)
          A         B                            A    B'

   today: press B + drag  ──▶  unselect everything, start a NEW wire from B
          (the A–B wire keeps its length; you drew a second wire instead)
```

## 2. Root cause (verified in the dispatch)

In `handle_button_press` (`src/callback.c`), a button-1 press on the closest object is
classified as `already_selected` or not, then:

- **Unselected wire endpoint** (`intuitive && !already_selected`, ~callback.c:5207):
  `add_wire_from_wire()` fires. When the snapped press is exactly on `(x1,y1)` or
  `(x2,y2)` it does `unselect_all(1); start_wire(...)` — i.e. **draw a new wire** — and
  returns "handled" (callback.c:2044–2067).
- **Already-selected wire endpoint** (`cond = already_selected`, ~callback.c:5231/5236):
  `edit_wire_point()` runs, marks the grabbed end `SELECTED1`/`SELECTED2`, sets
  `shape_point_selected`, and `move_objects(START,…)` — i.e. **stretch that vertex**
  (callback.c:2102–2128).

So the *same gesture* (press an endpoint + drag) maps to two different actions purely
based on whether the wire was already selected. The "stretch the vertex" behavior the
user wants already exists — it is just gated behind a prior selection.

## 3. Desired behavior

Pressing on a **free wire vertex** and dragging should **grab and move that vertex**
immediately (no pre-select):

- drag **toward** the other end → the wire **shortens**;
- drag **away** → the wire **lengthens** (this subsumes today's "extend");
- orthogonal-wiring / snap behave as they already do for a selected-wire vertex drag.

It must feel identical to grabbing the vertex of an already-selected wire — because under
the hood it is the same `edit_wire_point` → `move_objects` path; only the *press-time
routing* changes.

## 4. Design decisions to settle first (present, don't pick unilaterally)

**(a) Disambiguation vs `add_wire_from_wire`.** Press-on-endpoint currently *means*
"draw a new wire." We must decide what each case maps to. Recommended split, keyed on
whether the endpoint is **free/dangling** (on no instance pin AND not shared/touched by
another wire):

| endpoint | recommended press+drag | rationale |
|---|---|---|
| **free / dangling** | **grab + stretch the vertex** (new) | nothing to "continue"; moving the loose end is the obvious direct manipulation; subsumes extend, adds shorten |
| **connected** (on a pin / junction) | keep `add_wire_from_wire` (draw a new branch wire) | branching the net off a real connection point is meaningful there |

Tradeoff: at a free end you lose "start a disconnected new wire from this point" — that
remains available via the explicit wire tool (`w`). This is the crux decision; alternative
is to keep direction-based disambiguation (decide at first motion), which is more complex
and makes the "away" drag inconsistent.

**(b) Gating.** Gate the new behavior on **`cadence_compat`** first, so stock/intuitive
behavior is byte-unchanged and the change is opt-in (matches how the rest of the
fluid-editing work shipped). A later decision can widen it to plain `intuitive_interface`
if desired.

**(c) "Free vertex" predicate.** Need a small helper in `callback.c` scope:
`wire_endpoint_is_free(n, which)` = the endpoint is on **no** instance pin **and** is
**not** coincident with / touched by another wire. (`move.c` already has the static
`point_on_any_pin` / `point_on_other_wire` ideas for the Phase-5 work; mirror them, or
expose a shared predicate.)

## 5. Plan to fix (RED-first, atomic)

> Each phase is independently shippable and sabotage-verified. Keep behind `cadence_compat`
> until the eyeball passes.

- **Phase 0 — characterize + test scaffold.** Add a gesture test
  `tests/headless/test_wire_vertex_grab.tcl` driving the real dispatch via
  `xschem callback .drw <press|motion|release> …` (the `test_cadence_drag` pattern; needs
  a window). Fixtures: a lone free wire `A=(0,0)–B=(100,0)`. RED assertions:
  (1) press at `B` + drag to `(60,0)` with `cadence_compat` on ⇒ wire becomes `(0,0)–(60,0)`
  (one wire, shortened), NOT two wires. Confirm it is RED today (today it draws a new wire).
  Also add a headless unit test of the **free-vertex predicate** (build wires/pins, assert
  free vs connected) so the geometry logic is covered without a window.

- **Phase 1 — the free-vertex predicate.** Implement `wire_endpoint_is_free()`; unit-test
  it (free dangling end = true; end on a pin = false; end shared with another wire =
  false). No behavior change yet.

- **Phase 2 — route free-vertex press to the vertex grab.** In `handle_button_press`,
  *before* the `add_wire_from_wire` call, add: if `cadence_compat && intuitive &&
  !already_selected` and the press is exactly on a wire endpoint that is **free**, then
  select that wire, mark the grabbed end (`SELECTED1`/`SELECTED2`), set
  `shape_point_selected`, and `move_objects(START,…)` — i.e. the `edit_wire_point` body,
  but for the *unselected* case. Return handled so `add_wire_from_wire` does not also fire.
  Factor the shared logic so `edit_wire_point` and this new path don't diverge. TC RED→GREEN.

- **Phase 3 — guards + completion.** Confirm the release path completes the vertex stretch
  identically to the pre-selected case (it is the same `move_objects` completion, so this
  is mostly a verification phase). Guard: connected endpoints still `add_wire_from_wire`
  (draw new wire); non-cadence/stock path byte-unchanged; mid-span press still selects +
  moves the whole wire; orthogonal-wiring vertex drag still Manhattan.

- **Phase 4 — eyeball + decide widening.** Manual test on a real schematic; decide with
  the user whether to enable under plain `intuitive_interface` (decision 4b) and whether a
  connected-endpoint variant is wanted.

## 6. Test strategy & guards

- **Gesture level (windowed):** `xschem callback .drw …` driver, like
  `tests/headless/test_cadence_drag.tcl` (real `.drw`, WSLg-flaky → rerun). Asserts the
  end-to-end press→drag→release shortens the wire and yields one wire, not two.
- **Headless unit:** the free-vertex predicate, built from in-memory wires/instances.
- **Must not regress:** stock (`cadence_compat=0`) press-on-wire-end still draws a new wire
  (`test_gesture_bindings` / a dedicated assertion); `add_wire_from_wire` for connected
  endpoints; whole-wire move on mid-span press; `test_cadence_drag` (16) still green.
- **Sabotage-verify** both directions: drop the new routing ⇒ the grab test reddens and
  the new-wire test stays green; force the predicate true everywhere ⇒ connected-endpoint
  test reddens.

## 7. Notes

- The completion side is **already proven**: grabbing the vertex of an *already-selected*
  wire works today, and that is the exact `edit_wire_point` → `move_objects` path this
  feature reuses. The whole change is press-time **routing**, which keeps it small and
  low-risk.
- This composes with the wire-editing-on-move work: a shortened/stretched vertex still
  goes through the same `move_objects` END (trim/cleanup), so colinear merges and
  prop-preservation (issue/TC12) apply for free.
