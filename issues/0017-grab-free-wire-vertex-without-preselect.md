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
dragging instead **starts drawing a brand-new wire** from that point — and worse, leaves
you in **persistent wire-draw mode** (`STARTWIRE`), which you must then dismiss with a
**double-click + ESC**.

So today, to move/grow/shorten a free wire end you perform a 4-step ritual:
**select the wire → click-drag the end → double-click → press ESC.** We want this to be
just **click-drag-release, done.**

```
   want:  ●─────────●   grab the free end ───▶  ●────●     (drag TOWARD other end = shorter)
          A         B                            A    B'    commit on release, no mode

          ●─────────●   grab the free end ───▶  ●─────────────●   (drag AWAY = grow)
          A         B                            A             B'  commit on release, no mode

   today: press B + drag  ──▶  unselect everything, start a NEW wire from B,
          stay in wire-draw mode  ──▶  must double-click + ESC to finish
```

The user's clarification (2026-06-20): **both** directions are wanted from the one
gesture — TOWARD shortens, AWAY grows (same outcome as today's "extend") — but the
gesture must **commit on release**. The thing to eliminate is the lingering wire-draw
mode, not the grow result.

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
immediately (no pre-select), as a single **press-drag-release** gesture that **commits on
release**:

- drag **toward** the other end → the wire **shortens**;
- drag **away** → the wire **grows** (same outcome as today's "extend", different
  mechanism);
- **on release the action is committed — NO persistent wire-draw mode, no double-click,
  no ESC**;
- orthogonal-wiring / snap behave as they already do for a selected-wire vertex drag.

This is exactly the `edit_wire_point` → `move_objects` path that already exists for an
*already-selected* wire: it moves the grabbed endpoint and commits on button release. It
does **not** use `start_wire`, so it never enters `STARTWIRE` mode. The whole change is
**press-time routing**: send the free-endpoint press to this vertex-grab instead of to
`add_wire_from_wire`/`start_wire`. That single redirect kills both annoyances at once —
the pre-select step *and* the lingering wire-draw mode.

## 4. Design decisions to settle first (present, don't pick unilaterally)

**(a) Disambiguation vs `add_wire_from_wire` — DECIDED (user, 2026-06-20).** Press-on-
endpoint currently *means* "draw a new wire (and stay in wire-draw mode)." The split,
keyed on whether the endpoint is **free/dangling** (on no instance pin AND not
shared/touched by another wire):

| endpoint | press+drag | rationale |
|---|---|---|
| **free / dangling** | **grab the vertex → `move_objects`, commit on release** (new) | one gesture covers shorten (toward) and grow (away); nothing to "continue" at a loose end; **no wire-draw mode** |
| **connected** (on a pin / junction) | keep `add_wire_from_wire` (draw a new branch wire) | branching the net off a real connection point is meaningful there; out of scope here |

Resolved tradeoff: at a free end we intentionally **drop** "start a disconnected new wire
from this point (in wire-draw mode)" — that is precisely the irritation being removed; the
explicit wire tool (`w`) still covers deliberate new-wire drawing. Direction-based
disambiguation is explicitly **rejected** — the user wants both directions handled by the
one commit-on-release vertex grab, not a mode for "away".

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
  a window). Fixtures: a lone free wire `A=(0,0)–B=(100,0)`. RED assertions (all with
  `cadence_compat` on):
  (1) **shorten** — press at `B`, drag to `(60,0)`, release ⇒ wire is `(0,0)–(60,0)`
  (one wire, shorter), NOT two wires;
  (2) **grow** — press at `B`, drag to `(150,0)`, release ⇒ wire is `(0,0)–(150,0)`
  (one wire, longer), NOT a second wire;
  (3) **commit on release** — after either gesture, `xschem get ui_state` has **no
  `STARTWIRE` bit** (we are not left in wire-draw mode). All three are RED today (today the
  press starts a new wire and stays in `STARTWIRE`). Also add a headless unit test of the
  **free-vertex predicate** (build wires/pins, assert free vs connected) so the geometry
  logic is covered without a window.

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
  end-to-end press→drag→release: shortens (toward) and grows (away) the *same* wire (one
  wire, not two), **and that `ui_state` has no `STARTWIRE` bit afterwards** (committed, not
  stuck in wire-draw mode).
- **Headless unit:** the free-vertex predicate, built from in-memory wires/instances.
- **Must not regress:** stock (`cadence_compat=0`) press-on-wire-end still draws a new wire
  *and still enters wire-draw mode* (`test_gesture_bindings` / a dedicated assertion);
  `add_wire_from_wire` for **connected** endpoints (the deliberate new-branch-wire gesture,
  wire-draw mode intact); whole-wire move on mid-span press; `test_cadence_drag` (16) still
  green.
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
