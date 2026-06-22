# Plan (RED-first): Detachable tabs & true multi-window

Target branch: `fluid-editing`. Spec: `specs/multi_window_detach.md`.

## Shape of the work

The windowed path (`create_new_window`) already produces a fully independent
toplevel with its own X window + GCs; the tabbed path (`create_new_tab`) reuses the
main canvas. This plan **decouples** the two so they coexist, then makes a context
**movable** between a tab strip and a window. It is mostly C in `src/xinit.c`
(+ a small `scheduler.c` dispatch + Tcl in `library_manager.tcl`/`xschem.tcl`),
so it **needs `make`** (unlike the pure-Tcl library-git work).

**Method: RED-first.** Every atomic step below begins by adding a test that FAILS
against current code (RED), then the smallest change that makes it pass (GREEN),
then a sabotage check (revert the change, confirm the test goes RED again — guards
against `green_but_hollow` tests, see `claude_suggs/green_but_hollow_tests.md`).
One headless file grows across the plan:
`tests/headless/test_multi_window.tcl` — a standalone **GUI smoke** (X required;
`check name ok detail` + `fail` counter; prints `RESULT: ALL PASS` / `RESULT: N
FAILED` and exits nonzero, per the `tests/headless/README.md` "GUI smokes"
convention). It is run directly, **not** registered in `cases.txt` (that manifest
is only for netlist-golden schematics). Invocation:
`DISPLAY=:0 ./xschem --pipe -q --nolog --script ../tests/headless/test_multi_window.tcl`.

## The one invariant to get right

**A tab must render to *its own window group's* canvas, never the hardcoded
`save_xctx[0]->window` (xinit.c:1891).** Every regression risk in this plan traces
back to a place that assumes "the main window is the only canvas" or "there is one
global `.tabs` bar." The introspection seam (`xschem windows`, Phase 0) exists to
make that grouping assertable at every step.

---

## Phase 0 — Introspection seam + force-a-window (the quick win)  ✅ DONE

Status: **implemented & verified** on `fluid-editing` (test_multi_window.tcl
MW1–MW4 GREEN; RED baseline captured first; netlist goldens still PASS; default
tabbed open still yields a tab — only `-window` forces a window).

Smallest end-to-end slice: a query to assert against, and "New Window" that really
opens a window. No data model change yet — just stop the global flag from
overriding a per-open request.

### Step 0.1 — `xschem windows` query  *(RED→GREEN)*
- **RED:** MW1 asserts `xschem windows` returns one element for the base context,
  with fields `{win_path top_path group xwindow current_name}` and `group` == `.`.
  Fails: subcommand does not exist.
- **GREEN:** add a `windows` branch in the scheduler (next to other `get`-style
  introspection) that walks `get_save_xctx()` / `window_path[]` and emits the list.
  Read-only; no state touched.
- **Sabotage:** make it emit `group` as empty — MW1 goes RED.

### Step 0.2 — `new_schematic create_window` verb  *(RED→GREEN)*
- **RED:** MW2/MW3 — with `tabbed_interface=1`, `xschem new_schematic create_window
  .x1 <file>` must yield `[winfo toplevel .x1.drw] == .x1` (not `.`) and a distinct
  X id. Fails: only `create` exists and it honors the global flag → makes a tab.
- **GREEN:** in `new_schematic()` (xinit.c:2189) add a `create_window` what-verb
  that calls `create_new_window(...)` **unconditionally**, bypassing the
  `tabbed_interface` test. (`create_new_window` is already self-sufficient.)
- **Sabotage:** route `create_window` back through the flag — MW2 goes RED in
  tabbed mode.

### Step 0.3 — `load_new_window -window` + Library Manager checkbox  *(RED→GREEN)*
- **RED:** MW4 — `xschem load_new_window -window <f>` opens `<f>` in a separate
  toplevel; and a proc-level check that `libmgr::open_view` with `new_window` set
  routes to the window-forcing command. Fails: `load_new_window` always calls
  `new_schematic("create",…)` (scheduler.c:3657).
- **GREEN:** parse an optional `-window` flag in the `load_new_window` branch →
  `new_schematic("create_window",…)`. Point the Library Manager "New window"
  checkbox (`library_manager.tcl:432`) at `xschem load_new_window -window`.
- **Sabotage:** drop the flag parse — MW4 goes RED.

**End of Phase 0: you can put two schematics on two monitors.** Each forced window
is a standalone toplevel (today it has no tab strip of its own — that is Phase 1).

---

## ⮕ REORDER (decided after Phase 0 probe): detach-first

A probe revealed the single `.tabs` strip is hardcoded across `switch_tab`,
`setup_tabbed_interface`, `swap_tabs`, `tab_context_menu`, `next_tab`/`prev_tab`
(all literal `.tabs`), so full Phase 1 (per-window tab strips) is a large, high-risk
refactor. But the **headline feature — tear a tab into its own window — does not
need it**: a detached tab can become a *standalone single-schematic* window reusing
the Phase 0 `create_new_window` machinery. So **Step 1.1 was kept (group
attribution, already delivered by Phase 0), then we jumped to Phase 2 (detach)**.
Steps 1.2–1.3 (per-window tab strips, so a torn-off window can itself hold tabs)
are **DEFERRED** to a later full-Chrome-parity pass. User-approved.

## Phase 1 — Per-window tab ownership (break the single-`.tabs` assumption)

Make the tab strip and canvas **belong to a group**, so a window can hold tabs.

### Step 1.1 — group attribution in `xschem windows`  ✅ DONE (pinned, MW1b)
Delivered by Phase 0's `top_path`-derived `group`; MW1b pins it (forced window is
its own group `.x1`, tabs are group `.`). No separate RED — Phase 0 already made it
correct; MW1b is a regression guard.

### Step 1.2 — a tab renders to its group's window  ⏸ DEFERRED (full-parity pass)
- **RED:** extend MW1 — open a forced window (Phase 0) **and** a tab; assert the
  tab's `group` is `.` and the forced window's `group` is `.x1` (two distinct
  groups). Fails: every context currently reports the same/global grouping.
- **GREEN:** derive `group` from the context's `top_path` (xschem.h:1222) rather
  than assuming `save_xctx[0]`. No behavior change yet — only honest reporting.
- **Sabotage:** hardcode `group` to `.` — MW1’s two-group assertion goes RED.

### Step 1.2 — a tab renders to its group's window  *(RED→GREEN)*
- **RED:** MW6-precursor — create a tab **inside a forced window** (`.x1`) and
  assert (via `xschem windows`) its `xwindow` equals `.x1`'s id, not the main
  window's id. Fails: `create_new_tab` hardcodes `xctx->window =
  save_xctx[0]->window` (xinit.c:1891).
- **GREEN:** replace that line with "the owning group's X window id" — looked up
  from the target `top_path`'s drw via `Tk_WindowId`, falling back to
  `save_xctx[0]->window` only for the main group. Recreate GCs against it.
- **Sabotage:** restore the hardcoded line — the tab paints to the wrong window;
  test RED.

### Step 1.3 — per-group tab bar widget  ⏸ DEFERRED (full-parity pass)
- **RED:** MW-bar — after creating a 2nd tab in group `.x1`, assert the tab button
  lives under `.x1.tabs` (that group's strip), not the global `.tabs`. Fails: tab
  buttons are always packed into `.tabs` (xinit.c:1876).
- **GREEN:** `build_widgets <top>` gains a `<top>.tabs` strip; `create_new_tab`
  packs the button into the **owning group's** strip; `swap_tabs`/`tab_context_menu`
  resolve `%W`'s group from its widget path. Main group keeps `.tabs`.
- **Sabotage:** pack into `.tabs` unconditionally — MW-bar RED.

---

## Phase 2 — Detach a tab into a new window  ✅ DONE (the headline feature)

Status: **implemented, verified & sabotage-checked** on `fluid-editing`.
`detach_tab()` (xinit.c) re-homes a tab onto a fresh toplevel in the background
(operates on the detached context, restores the active one — main strip
undisturbed): builds the toplevel+widgets, repoints `xctx->window`, `free_gc()` →
`create_gc()` → `build_colors` → `resetwin`, drops the `.tabs.xN` button +
`tab_queue REMOVE`. `switch_tab`'s `xctx->window = save_xctx[0]->window` is now
guarded so a detached window (non-empty `top_path`) keeps its own X window. Reachable
from the tab right-click menu → **"Detach to window"** (`tab_ctx_cmd … detach`).
Tests MW5/MW6/MW5b GREEN; sabotage (disable re-home) turns MW5 RED. Single
schematic per detached window (per-window tabs are the deferred 1.2–1.3 pass).

### Step 2.1 — `new_schematic detach <win_path>`  ✅ DONE (MW5/MW6/MW5b)
- **RED:** MW5 — make a tab, `detach` it, assert via `xschem windows` it moved from
  group `.` to a new group `.xN`, its `xwindow` changed, and the old `.tabs.xN`
  button no longer exists. Fails: no `detach` verb.
- **GREEN:** add a `detach` what-verb: build a toplevel (`toplevel`/`build_widgets`/
  `pack_widgets`) + get its X id; on the target context **free old GCs, repoint
  `xctx->window`, `create_gc()`, `resetwin(1,…)`**; re-`set_bindings` /
  `set_replace_key_binding`; destroy the source `.tabs.xN` button; update
  `top_path`/`current_win_path` and the group mapping. If the source group drops to
  one context, hide its strip.
- **Sabotage:** skip the `create_gc()` re-init — MW6 (next) goes RED / crashes.

### Step 2.2 — both windows still draw  *(RED→GREEN)*
- **RED:** MW6 — after detach, force a redraw in **both** windows (`xschem draw`
  after `new_schematic switch` to each) and assert no X error / non-empty render.
  Fails if GCs were not validly recreated against the new window (BadDrawable).
- **GREEN:** ensured by 2.1's GC re-init + pixmap reset; this test pins it.
- **Sabotage:** repoint `xctx->window` but reuse the old GCs — MW6 RED.

---

## Phase 3 — Re-attach / move between windows + relax mode lock

### Step 3.1 — `new_schematic attach <win_path> <dest_top>`  *(RED→GREEN)*
- **RED:** MW7 — detach, then `attach` the context into an existing group; assert
  `xschem windows` shows the regrouping and the dest strip gained a tab.
- **GREEN:** the inverse of detach — re-home into an existing group's window/GCs/
  strip instead of a fresh toplevel; destroy the now-empty torn-off toplevel.
- **Sabotage:** leave the old group mapping in place — MW7 RED.

### Step 3.2 — un-disable the "Tabbed interface" toggle  *(RED→GREEN)*
- **RED:** MW8 — with ≥2 contexts, assert `.menubar.view` "Tabbed interface" entry
  is **not** `disabled`. Fails: xinit.c:1726/1852 disable it on 2nd context.
- **GREEN:** remove the two `entryconfigure … -state disabled` calls; make the
  toggle apply via detach/attach on the current context rather than a global rebuild.
- **Sabotage:** restore the disable — MW8 RED.

### Step 3.3 — drag gesture (manual eyeball, no auto-test)
- Wire dropping a `.tabs.xN` button onto another group's strip → `attach`; tearing
  it off into empty space → `detach`. Built on existing `swap_tabs`
  (xinit.c:1870-1872). **Not headless-testable** (drag + WM); validate by hand and
  note it in the spec's manual-eyeball list.

---

## Phase 2.5 — Real-usage hardening (from manual GUI testing in cadence mode)  ✅ DONE

Manual testing (`xschem --script src/cadence_style_rc`) surfaced that routing the
common "New window" path through `create_new_window` exposed latent bugs in the
rarely-used windowed path. Fixed:

- **Zombie window on close (critical).** Closing a real window while
  `tabbed_interface=1` dispatched to `destroy_tab` (deletes the context, tries to
  remove a non-existent `.tabs.xN` button, **never destroys the toplevel**) → a
  dead, content-still-visible window. Fix: `new_schematic("destroy")` now routes by
  the TARGET context's kind (`is_window_context()` → non-empty `top_path`), not the
  global flag — a window always goes to `destroy_window` (which destroys the
  toplevel). Test **MWc**.
- **Custom keybindings missing in new windows.** cadence_style_rc binds shortcuts
  to the widget `.drw` (e.g. `Control-x`→descend, with `break`); new `.xN.drw`
  canvases never got them, so Control-x fell through to the C default (cut). Fix:
  `clone_canvas_bindings .drw <newcanvas>` after `set_bindings` in
  `create_new_window` + `detach_tab` copies the user's widget binds. Test **MWk**.
- **New/detached windows lost behind launcher / on another monitor.** Added
  `wm deiconify; raise` on creation/detach.
- **Blank window until the mouse moves.** `create_new_window` relied on an Expose
  event to paint (set `pending_fullzoom`, no explicit draw); WSLg drops that first
  Expose → blank canvas until a motion/zoom event. Fix: paint explicitly at the end
  of `create_new_window` (mirror `create_new_tab`: `zoom_full` or `draw`).
- **Keys dead in new windows (CTRL-W/CTRL-Q/`f`).** The first raise/focus focused
  the **toplevel frame** `.xN`; the `<KeyPress>` binding lives on the **canvas**
  `.xN.drw`, so keystrokes were swallowed (mouse motion silently re-focused the
  canvas via `<Motion>`, masking it). Fix: `focus -force` the **canvas**. Tests
  **MWf** (canvas has focus) + **MWw** (synthesized CTRL-W reaches the handler and
  closes the window end-to-end).
- **Library Manager buttons clipped (pack-order bug, pre-existing).** The expanding
  3-pane `$w.pw` was packed before the bottom status/button bars, claiming the whole
  760x460 cavity (treeview `-height 20`) and pushing Open/Place/Refresh/Close off the
  bottom. Fix: pack the fixed bottom bars first, the pane last. Verified headless.

## Phase 2.6 — Mixed-mode context routing (2nd manual-test round)  ✅ DONE

The 1st hardening round let windows *exist* in tabbed mode but the core event/
context machinery still keyed off the global flag, so a 2nd round of testing found:

- **Input routed to the wrong window (critical).** `handle_window_switching`
  (callback.c) did ALL per-window context switching inside `if(!tabbed_interface)`;
  the tabbed `else` was empty. With ≥2 real windows in tabbed mode, `xctx` never
  followed focus → every click/key/zoom hit the last-touched schematic. Fix: gate the
  switch block on `!tabbed_interface || win_is_real || cur_is_real` (a real window =
  non-empty `top_path`), and route real-window switches in `new_schematic`
  (`switch`/`switch_no_tcl_ctx`) to `switch_window` even in tabbed mode. Pure-tabbed
  and pure-windowed paths are untouched (both flags 0 → old behavior). Test **MWs**
  (FocusIn on each window's canvas → `current_win_path` follows).
- **Crash on CTRL-SHIFT-N** (`schematic_in_new_window force`, emergency-save files):
  it reads the selected instance from `xctx` then creates a new schematic — with the
  wrong-context bug above, `xctx` was a stale/foreign window → deref crash. Not
  reproduced after the routing fix; the wrong-context precondition is gone.
- **Geometry clamp (requested).** New + detached windows call `size_new_window`
  after `set_geom`: only when the window comes up >90% of screen (restored-maximized
  geometry / WM), shrink to `::new_window_size_frac` (default 0.5) of screen width
  (capped 1800 so it can't span a multi-monitor X screen) × 85% height. Normal-size
  windows are left as-is (verified: a 1067-wide window is not touched).

**Still open (flagged, separate subsystems — not multi-window):**
- CTRL-ALT-S `locate_selected_in_libmgr` selects only the Library, not L/C/V — bug is
  downstream in `library_inst_lcv` (library_defs.tcl) or `libmgr::open`'s cell/view
  selection (likely the listbox→treeview migration). Library-manager subsystem.
- Window closes don't log to the CIW — the `destroy` dispatch never `log_action`s
  (only final `xschem exit` does). Action-log gap.

## Phase 4 — Regression sweep + docs

- Run `tests/headless/run.sh` (or `run_nogui.sh` where applicable) + the
  parallel regression suite (`tests/run_regression.tcl`); confirm tab/window cases
  and existing `issues/0010` (hover-after-tab-switch) still pass.
- Update `specs/multi_window_detach.md` status → implemented; add a
  `code_analysis/` note on the window-group model; update `MEMORY.md`.

## Flagged risks (not hidden)

- **GC / pixmap lifetime on re-home** is the sharpest edge: a stale GC bound to a
  destroyed window is a BadDrawable crash. MW6 is the guard; every detach/attach
  step ends by drawing in the affected window.
- **`save_xctx[0]` assumptions are diffuse.** Beyond xinit.c:1891 there may be
  other "main window is the canvas" spots (menu reconfig at 1725/1851, simulate-bg).
  Phase 1.2 fixes the rendering one; grep `save_xctx\[0\]` and triage the rest
  before Phase 2.
- **WM behavior is untestable headless** (focus, geometry, live drag) — explicitly
  manual, consistent with `specs/library_manager_launch.md`.
- **Layout persistence is out of scope** — a torn-off layout is lost on exit until
  the follow-on.
