# `hi_descend` — human-interface descend with view + destination choice

Status: **proposed** (branch `fluid-editing`). Not yet implemented.
Related: `src/callback.c` (canvas key `e`), `src/xschem.tcl`
(`open_sub_schematic`, menu/accelerator `E` at ~`11704`), `src/scheduler.c`
(`xschem descend` ~`1039`, `descend_symbol` ~`1061`, `schematic_in_new_window`,
`new_schematic`, `copy_hierarchy`, `copy_hilights`), `src/actions.c`
(`descend_schematic`, `schematic_in_new_window`), `src/save.c` (`descend_symbol`),
`src/hilight.c` (`copy_hilights`). See also `specs/descend_readonly.md`,
`specs/multi_window_detach.md`, `specs/net_hilight_styles.md`.

## 1. Motivation

Today the `E` key is hard-wired to `xschem descend` — it descends into the
**default** schematic view of the selected instance, **always replacing the
current canvas**. Two things are missing for real navigation:

1. **View choice.** A cell can carry more than one view of each type — several
   *schematic* views (the symbol's default `schematic=` binding plus alternates
   such as `schematic_old`, `schematic_behav`) and one or more *symbol* views. In
   the OpenAccess library layout these live as `library/cell/<view>/` directories
   (e.g. `ngspice/solar_panel/schematic/`, `.../symbol/`). The user should pick
   which view to descend into rather than always getting the default.
2. **Destination choice.** Descend should optionally open the chosen view in a
   **new window** or **new tab** instead of replacing the current canvas — so the
   parent and child levels can be viewed side by side (e.g. highlight a net, then
   open the lower level next to it during debugging). The plumbing already exists
   (`schematic_in_new_window`, `new_schematic`, `copy_hierarchy`, `copy_hilights`,
   the orphaned `open_sub_schematic` proc) but is reachable only through the hidden
   `Alt+E` binding and offers no view/destination choice.

`hi_descend` (hi = *human interface*) unifies both behind the primary `E` key: a
dialog when invoked bare, and a fully scriptable headless path when invoked with
arguments.

## 2. The `E` key now runs `hi_descend`

- **Binding.** The plain-`E` path (currently `callback.c` `case 'e'`, `rstate==0`,
  which calls `descend_schematic(...)`) is repointed to evaluate the Tcl proc
  `hi_descend` (no args). The menu **Edit ▸ Push schematic** (`xschem.tcl:11704`)
  and the toolbar `EditPushSch` button (`xschem.tcl:10284`) likewise call
  `hi_descend`; the accelerator label stays `E`.
- **Modifiers preserved.** `Ctrl+E` (go_back / pop) and the existing
  `Alt/Super+E` (descend in new window — superseded by, but kept as an alias for,
  `hi_descend ... target=new_window`) keep working. `hi_descend` is the new
  *default*, unmodified-`E` entry point.
- **Pre-checks reuse existing guards.** Semaphore/gesture guards and the
  "nothing selected" handling mirror `open_sub_schematic` (`xschem.tcl:4365`):
  exactly one instance must be selected (or the target instance passed as an arg),
  otherwise the dialog opens against that single selection or reports the
  ambiguity.

## 3. Calling convention

```
hi_descend ?view? ?key=value ...?
```

- **No arguments** → open the modal dialog (§4) and let the user choose. This is
  what the `E` key triggers.
- **With arguments** → run **headless**, no dialog. Mirrors the user's example
  `hi_descend "schematic_old" target=new_window`.

Arguments (Tcl-proc friendly, `key=value` to match the requested syntax):

| Token | Meaning | Default |
|-------|---------|---------|
| *(first positional)* `view` | View name to descend into, e.g. `schematic`, `schematic_old`, `symbol`. Matched against the enumerated views (§5). | the cell's default schematic view |
| `view=<name>` | Same as the positional form (explicit). | — |
| `type=schematic\|symbol` | Disambiguate when a view name is ambiguous or omitted; selects `descend` vs `descend_symbol`. | inferred from the resolved view |
| `target=current\|new_window\|new_tab` | Destination (§6). | `current` |
| `inst=<instname>` | Operate on a named instance instead of the current selection (as `open_sub_schematic` already accepts). | current selection |

Unknown view names or an empty cell-view set → return a non-fatal error via
`ciw_echo` (and Tcl error code for scripts), no dialog, no descend.

## 4. The dialog (bare invocation)

A modal Tk dialog (Cadence-style, consistent with the slick property forms),
titled for the target cell, with three groups:

1. **View list.** All views discovered for the selected instance's cell (§5),
   grouped/sectioned by type (Schematic views, Symbol views), the cell's default
   schematic view pre-selected. Single-select. Double-clicking a view = choose +
   OK. Each row shows the view name and its resolved file path (greyed if the file
   is missing, reusing the `cellview` missing/override colour cues at
   `xschem.tcl:2181`).
2. **Destination radio group.** `Current window` (default) · `New window` ·
   `New tab`. (When not in tabbed mode, `New tab` may be disabled or coerced to
   `New window`; follow the existing `tabbed_interface` rules used by
   `schematic_in_new_window`/`new_schematic`.)
3. **OK / Cancel.** OK invokes the same code path as the headless form with the
   chosen `view`/`type`/`target`; Cancel does nothing.

The dialog must be modeless-friendly w.r.t. the canvas the way the property forms
are (don't block highlight animation timers); see issue 0009 lineage.

## 5. View enumeration

For the selected instance's cell, build the candidate view set from both layouts:

- **Classic / attribute layout.** The symbol's default schematic binding via
  `xschem get_sch_from_sym <inst>` (the same call `cellview` uses at
  `xschem.tcl:2197,2576`) → the default `schematic` view; the symbol itself → the
  `symbol` view. Any alternate `schematic=` bindings already known are listed too.
- **OpenAccess library layout.** When the cell resolves under an OA library
  (`library/cell/<view>/`), scan the cell directory for sibling view dirs and
  classify each as schematic-type or symbol-type by the file it contains
  (`.sch`/`.sym`). This is what surfaces named alternates like `schematic_old`.

De-duplicate by resolved absolute path; present view *names* to the user, resolve
to absolute `.sch`/`.sym` paths internally. This enumeration is the one new piece
of logic; everything downstream reuses existing descend primitives.

## 6. Destination handling — retaining connectivity

All three destinations must preserve the **hierarchy path** (so it is a true
descend, not a bare file-open) and **carry highlights** so a net highlighted in the
parent shows highlighted in the child — the debugging use case.

- **`target=current`** — replace the current canvas:
  - schematic view → select the instance, set the chosen view as the descend
    target, `xschem descend` (→ `descend_schematic`).
  - symbol view → `xschem descend_symbol` (→ `descend_symbol`).
  Highlights already persist (same context).
- **`target=new_window` / `target=new_tab`** — generalize `open_sub_schematic`
  (`xschem.tcl:4365`), which already does exactly the right sequence:
  `schematic_in_new_window force` → `copy_hierarchy <old> <new>` →
  `copy_hilights` → `new_schematic switch <new>` → `select instance` →
  `descend`. Extensions needed:
  1. honour the chosen **view** (descend into the selected view, not just the
     default) — for symbol views call `descend_symbol` in the new context;
  2. honour **tab vs window**: `new_tab` forces a tab, `new_window` forces a real
     top-level (the `-window`/`win` flag already threaded through
     `load_new_window`/`schematic_in_new_window`).

Connectivity caveat: `copy_hilights` is a **one-time snapshot** at creation. Live
cross-window highlight sync and the animation-freeze-on-descend behaviour are
**out of scope here** and tracked separately (see issue
`0034-animated-hilights-freeze-on-hierarchy-traversal`).

## 7. Read-only / browse interactions

`hi_descend` does not change the `descend_readonly` browse semantics
(`specs/descend_readonly.md`): the descended child still obeys the mirrored
`descend_readonly` flag in every destination, since all paths funnel through
`descend_schematic`/`descend_symbol`. New windows/tabs inherit the same rule.

## 8. Acceptance / tests

Headless (`--nogui`) over a fixture cell that has ≥2 schematic views and a symbol
view (mirror the OA `schematic`/`symbol` layout; add a `schematic_old`):

- **HID1** `hi_descend` with `target=current` and the default view reproduces
  today's `xschem descend` (same `current_name`, same hierarchy depth).
- **HID2** `hi_descend schematic_old target=current` descends into the **named**
  alternate view (assert `current_name`/loaded file), proving view selection.
- **HID3** `hi_descend symbol target=current` descends into the symbol view
  (equivalent to `descend_symbol`).
- **HID4** `hi_descend <view> target=new_window` and `... target=new_tab` create a
  new context (`get_window_count` increments), descend into the chosen view there,
  and **preserve the hierarchy path** (`copy_hierarchy`) and **highlights**
  (`copy_hilights`) — assert a net highlighted in the parent is highlighted in the
  new context at creation time.
- **HID5** bad/empty view name → non-fatal error, no descend, no new window.
- **HID6** sabotage-verify HID2/HID4 (point the view to the default; confirm the
  assertion goes red) so the test actually discriminates view selection.

**Not auto-tested (manual eyeball):** the dialog itself (Tk popup) — view list
population, default pre-selection, destination radio, missing-file colour cues,
double-click-to-OK.

## 9. Out of scope

- Live, bidirectional highlight propagation between open windows (snapshot only).
- Fixing animated-highlight freeze across hierarchy traversal (issue 0034).
- Creating new views / editing the symbol's `schematic=` binding from this dialog
  (that is `cellview`'s job).
- Per-hierarchy-level read-only memory (unchanged from `descend_readonly`).
