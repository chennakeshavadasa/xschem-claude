# Net Highlight Style Editor — A No-Docs GUI for Editing Highlight Styles

Status: SPEC (handoff doc). Builds on the completed feature in
[`specs/net_hilight_styles.md`](net_hilight_styles.md).
Related memory: [[net-hilight-styles]], [[action-registry]], [[action-logging]],
[[cadence-bindkeys]], [[hover-highlight]].

> **Status (2026-06-26):** reviewed over two rounds with the requester; **all open decisions are
> resolved** (see §11). Ready to implement — atomic steps in
> `claude_suggs/plan_net_hilight_style_editor.md`.

---

## 1. Goal

Let a user **edit the net-highlight-style table entirely through a GUI, without reading
any documentation**. Today the table (`net_hilight_style`) is a Tcl list of 8-column rows
that a user can only change by hand-editing a sourced rc file or typing
`net_hilight_style_*` procs at the console (see §2). This utility replaces that with a
discoverable, self-explanatory dialog: pick colors from a swatch/dropdown, set the stripe
angle with a slider, type the blink and marching-ants rates into labelled entry fields whose
effect is shown by a **live preview** — so the user never has to decode raw units (`blink_ms`,
`rate_persec`) or magic strings (`march_fwd`/`march_rev`) from docs.

The utility must be **discoverable two ways** — from the **Command Palette** (Ctrl+Shift+P)
and from the **Tools menu** — and must **draw attention to itself the first time**: until
the user has ever launched it, its Command-Palette entry is shown in a **distinct attention
color** (font color, since a Tk listbox can't bold a single item — §4.1).

This is purely an *editing front-end*. It does not change the style schema, the C
rendering/animation engine, or how styles get *applied to nets* (the `9`/`8`/`0` keys and
`net_hilight_apply` already do that). It edits the **table of style definitions**.

---

## 2. Background — what already exists (ground truth)

### 2.1 The row model (the thing being edited)
`net_hilight_style` is a Tcl global: a list of rows, each an **8-column list**
(`src/xschem.tcl:513-519`, struct `NetHilightStyle` in `src/xschem.h`):

| # | Column | Type / domain | Notes |
|---|--------|---------------|-------|
| 0 | `index` | int, **== row position** | Auto-managed; never user-typed. |
| 1 | `color` | layer index `0..cadlayers-1`, **or** an X11 color name, **or** `#RRGGBB` | Default rows use a *layer index* (e.g. `4`). |
| 2 | `width` | int ≥ 1 (C clamps 1..100) | Line thickness. |
| 3 | `dash` | Tcl list of on/off run lengths; `{}` = solid | Each run 1..255. Angle & marching are meaningless without a dash. |
| 4 | `angle` | int 0..45 (deg) | Stripe/hatch tilt; only meaningful with a dash. |
| 5 | `blink_ms` | int ≥ 0 (ms); 0 = steady | 50% duty cycle. |
| 6 | `anim` | `none` \| `march_fwd` \| `march_rev` | Marching-ants direction. |
| 7 | `rate_persec` | int ≥ 0 (dash-periods/sec) | Marching speed; needs `anim≠none` **and** a dash. |

Validation/clamping is mirrored in two places that the GUI must stay consistent with:
the Tcl normalizer `net_hilight_style_norm` (`src/xschem.tcl:526-541`) and the C parser
`parse_net_hilight_styles` (`src/hilight.c:434-540`).

### 2.2 The fault-tolerant editor procs (the API the GUI sits on)
`src/xschem.tcl:512-650`. The GUI is a thin Tk layer over these — it should **not**
reimplement table mutation:

- `net_hilight_style_default_row {idx}` → `{idx 4 1 {} 0 0 none 0}`.
- `net_hilight_style_norm {row idx}` — fill/clamp one row to 8 clean columns, force `index==idx`.
- `net_hilight_style_current` — the live table (materializes the layer-derived default if empty).
- `net_hilight_style_replace {rows}` — **table becomes exactly these rows** (renumbered). ← the
  GUI's main write path for whole-table edits (move/duplicate/reorder).
- `net_hilight_style_merge {rows}` — overwrite by each row's `index` column (the *overwrite* action).
- `net_hilight_style_append {rows}` — add rows at the end (the *add* action).
- `net_hilight_style_remove {indices}` — delete by position; renumber survivors (the *delete* button).
- `net_hilight_style_reset` — discard customization, re-derive the default.

Every one of these calls `xschem update_net_hilight_style` (the C recompile + redraw) before
returning, so **any GUI edit routed through them is live in the open schematic immediately**,
animation included. There is **no dedicated move/duplicate proc** — the GUI computes the new
list and calls `net_hilight_style_replace` (§7).

### 2.3 Persistence today (a gap this spec fills)
There is **no automatic persistence**. The table lives only in memory; to survive a restart
the user must hand-add it to a sourced rc file. The utility must add a writeback, following
xschem's established idiom: write a small **Tcl-sourceable file under `$USER_CONF_DIR`
(`~/.xschem`)** and source it at startup — exactly how `recent_files`
(`write_recent_file` `src/xschem.tcl:1506`, `load_recent_file` :1441), `simrc`, and `colors`
already work.

### 2.4 Discoverability plumbing
- **Command Palette**: `command_palette` / `palette_refilter` in `src/action_registry.tcl:369-498`.
  It is fuzzy-filtered over `action_table`, which is loaded from `src/actions.csv`. Results are
  shown in a plain Tk **`listbox`** (`:475`). **A Tk listbox supports per-item *colors*
  (`itemconfigure -foreground`) but NOT per-item *fonts*** — which is why the first-launch emphasis
  is a font **color**, not bold (§4.1, resolved).
- **Tools menu**: hand-written in `src/xschem.tcl:12004-12404` (only the *File* menu is
  generated from `actions.csv`). So the entry is added in **two** places: a hand-written
  `add command` in the Tools section, and a row in `actions.csv` for the palette + cheat-sheet.

---

## 3. User-facing summary (what the user asked for)

1. Launchable from the **Command Palette** and the **Tools menu**.
2. A flag "has the user launched this utility"; while false, the palette entry is shown in a
   **distinct attention color** (font color, not bold — see §4.1). The flag **auto-persists** via a
   harmless one-line `~/.xschem` marker (it carries no style data), so "ever launched" is permanent
   across sessions (§4.3); only the style *table* is gated behind an explicit Save (§8).
3. The dialog shows **the existing style table**, one row per style, each **cell an
   appropriate widget** — no guessing, no docs:
   - color names → a **dropdown sourced from the app's own color database** (X11 `rgb.txt`);
     `#RRGGBB` → a **color picker with preview**;
   - angle → a **slider**;
   - blink → a **labelled entry field** with a **live preview** (unit shown on the form);
   - marching ants → a direction dropdown + a **labelled speed entry**, with a **live preview**
     (no exposed `march_fwd`/`march_rev`).
   - Preview is an on-form animated canvas; the read-only mini-schematic window remains a documented
     fallback only.
4. A **free-to-edit row at the top** (all cells default) where the user composes values, then
   chooses **Add / Overwrite (by row index)** from a dropdown and presses **Update**.
5. A **separator line** below the free-to-edit row.
6. With the cursor in a field of a **table row** (not the free row), per-row buttons enable
   (else greyed): **Move Up**, **Move Down**, **Delete**, **Duplicate** (new row immediately
   below; renumber as needed).

---

## 4. Discoverability

### 4.1 Command Palette entry + first-launch emphasis

Add to `src/actions.csv`:
```
tools.net_hilight_style_editor,command,tools,Net highlight styles…,,net_hilight_style_editor,,,Edit net highlight colors, dashes, blink and marching-ants without editing rc files,
```
(The label contains no comma; the help does — so the help field must be quoted per RFC-4180,
matching the existing quoted rows. Final CSV will quote it.)

**First-launch emphasis (RESOLVED — font color, not bold).** A global `net_hilight_editor_seen`
(0/1, default 0; see §4.3 for its session-vs-persistent semantics) drives the emphasis. Because a
Tk listbox cannot do per-item fonts but **can** do per-item colors, the palette **keeps its
existing listbox** and emphasizes the row whose `id` is `tools.net_hilight_style_editor` with a
**distinct foreground color** via `itemconfigure <i> -foreground <accent>` — no widget change, no
bold, no label prefix. `palette_refilter` already inserts rows in a loop (`:404-417`); after the
insert, if the row id matches **and** `net_hilight_editor_seen == 0`, color that line. The emphasis
disappears the moment `net_hilight_editor_seen` becomes 1.

### 4.2 Tools menu entry
Hand-written, next to "Library Manager" (`src/xschem.tcl:~12397`):
```tcl
$topwin.menubar.tools add command -label "Net highlight styles…" -command {net_hilight_style_editor}
```

### 4.3 The "seen" flag + its persistence (RESOLVED — harmless marker auto-written)
The requester's rule is about **potential damage, not the location**: harmless information *can and
should* be auto-written to `~/.xschem` for persistence; only **the highlight-style table itself**
(which could change appearance in the user's other projects) is gated behind an explicit Save (§8).
The "has the user looked at this editor" flag is exactly the harmless kind, so it auto-persists.

- New global `net_hilight_editor_seen` (default 0).
- **On first open**, `net_hilight_style_editor` sets `net_hilight_editor_seen 1` and **auto-writes a
  tiny, Tcl-sourceable marker file `$USER_CONF_DIR/net_hilight_editor_seen`** containing exactly
  `set net_hilight_editor_seen 1` (modeled on `write_recent_file`, `catch`-guarded). This is a UI
  breadcrumb only — it carries **no** style data, so it cannot affect any other project.
- The marker is **sourced at startup** (if present), after `set_ne net_hilight_style {}`
  (`src/xschem.tcl:~13386`), alongside `load_recent_file`. So "ever launched" persists permanently
  and the palette emphasis (§4.1) is gone for good after the first open, in every future session.
- The style **table** is a *separate* file and is **never** auto-written — only the explicit,
  user-located **Save…** writes it (§8). Keeping the two files separate is what lets the harmless
  flag persist freely while the potentially-disruptive table stays opt-in.

---

## 5. The editor window

### 5.1 Layout

```
┌─ Net highlight styles ───────────────────────────────────────────────────────────┐
│  [ Live preview ]   ← shared canvas (§5.3), reflects the row with field focus      │
│                                                                                    │
│      Color        W   Pattern        Angle    Blink(ms)  March    Speed(per/s)     │
│  NEW ▏[■▾][pick]│ [1]│ [6 4 ][ex▾]│ [──●──]│ [ 250  ]│ [Fwd▾]│ [ 2 ]             │ ← free-to-edit row
│       action:[Add ▾]   (if Overwrite:) row #:[ 2 ]      [ Update ]                  │
│  ────────────────────────────────────────────────────────────────────────────────│ ← separator
│  0 ▏[■▾][pick]│ [1]│ [    ][ex▾]│ [──●──]│ [  0   ]│ [Off▾]│ [ 0 ]               │ ┐
│  1 ▏[■▾][pick]│ [3]│ [6 4 ][ex▾]│ [─●───]│ [  0   ]│ [Fwd▾]│ [ 2 ]               │ │ existing table
│  2 ▏ …                                                                         │   │ ┘ (scrollable)
│                                                                                    │
│  Row ops:  [Move ↑] [Move ↓] [Delete] [Duplicate]  (enabled only when a TABLE row  │
│                                                      — not NEW — has field focus)   │
│  [ Reset to defaults ]                    [ OK ] [ Apply ] [ Save… ] [ Cancel ]     │
└────────────────────────────────────────────────────────────────────────────────────┘
```
(`[ex▾]` = the dash-examples dropdown that fills the entry to its left; `[■▾]` = color swatch +
named-color dropdown; `[pick]` = `tk_chooseColor`. Blink/Speed are plain entry fields with unit
labels; only Angle is a slider.)

- The **table area is scrollable** (the table can exceed `cadlayers` rows).
- The **`index`/row-number column is read-only** (display only) — the invariant `index==position`
  is owned by the editor procs, never typed.
- **Column set (RESOLVED — all 8 columns).** The request named color/angle/blink/marching, but the
  row also carries **`width`** and **`dash`**, and marching has a *speed* as well as a *direction*.
  All are exposed or they would be silently flattened on Save. Per-row columns:
  **Color · Width · Pattern(dash) · Angle · Blink · Marching · Speed** (Index shown, not edited).

### 5.2 Per-cell widgets (no docs required)

- **Color** (RESOLVED — use the app's own color source) — a **swatch button** + a **`ttk::combobox`**
  whose list is: *Layer 0…N* (each existing layer color), then **the X11 named colors from the same
  source the engine uses**, then **`Custom…`**. The engine resolves color names via
  `find_best_color()` → `XAllocNamedColor` (`src/xinit.c:277,286`), i.e. the **X11 `rgb.txt`**
  database (`/usr/share/X11/rgb.txt`, 754 entries) — the same place `red`/`orange`/`yellow` come
  from. The dropdown is **populated by reading that `rgb.txt`** at dialog build time (fallback: a
  bundled copy of the standard X11 names if the file is absent on some platform), so the offered
  names are exactly the supported ones. Choosing `Custom…` (or clicking the swatch) opens
  **`tk_chooseColor`** (`src/xschem.tcl:8506`) and stores `#RRGGBB`.
  - **Storage nuance:** a row is a Tcl list, so a **multi-word** rgb.txt name (`light goldenrod
    yellow`) would split into 3 elements and corrupt the row. The editor offers/stores the
    **single-token CamelCase** form (`LightGoldenrodYellow`, also rgb.txt-provided and X11-valid) or,
    failing that, the `#RRGGBB` from `winfo rgb`. Each name is validated via `winfo rgb` (the same
    resolution X11 does) before it is applied. Stored cell value = layer int, single-token name, or `#RRGGBB`.
- **Width** — `spinbox` 1..100.
- **Pattern (dash)** (RESOLVED — entry + examples dropdown, the requester's design) — an always-visible
  **text entry** holding the raw on/off run-length list (e.g. `6 4`; empty = solid), **accompanied by
  a `ttk::combobox` of named examples** {Solid, Dash `6 4`, Dot `2 3`, Dash-Dot `6 3 2 3`,
  Long-Dash `12 4`, …}. **Picking an example fills the entry** with that list and updates the preview;
  the entry stays freely editable for custom patterns. Angle/Marching/Speed widgets **disable when the
  pattern is empty/Solid** (they have no effect without a dash; matches the C warnings).
- **Angle** — `scale` 0..45° (slider, as originally requested), live-updating the preview.
- **Blink** (RESOLVED — entry field, not a slider) — a **text entry** for the period with a unit
  label on the form, e.g. `Blink (ms):` `[ 0 ]` (0 = steady). The **preview** swatch blinks at the
  entered rate so the user sees the result without guessing; the entry is the source of truth.
- **Marching** — a `ttk::combobox` {Off, Forward, Reverse} → `anim` = `none`/`march_fwd`/`march_rev`,
  plus a **Speed text entry** (not a slider) with a unit label, e.g. `Speed (periods/s):` `[ 0 ]`.
  The **preview** shows the dashes crawling in the chosen direction/speed.

### 5.3 Preview

**Primary (RESOLVED): an on-form animated `canvas`** (~220×40 px) at the top of the dialog,
adjacent to the rows, drawing a short horizontal wire segment using the **focused row's**
color/width/dash/angle and animating blink + marching with a Tcl `after` tick. This reuses the
feature's own timing semantics (`blink_ms` 50% duty; march offset `dir·rate·P·frac(t)`), either
re-implemented in ~15 lines of Tcl or, cleaner, by exposing a tiny read-only C query
(the engine already has `net_hilight_style_on_now` / `net_hilight_march_offset` and the
`net_hilight_test_now` hook). The preview updates whenever the focused row's fields change.

**Fallback (the requester's suggestion): a tiny read-only, non-interactive schematic window**
showing one highlighted net, placed adjacent to the form — used only if the canvas preview proves
unable to reproduce the real look. It must block all interaction (no zoom/pan/select) and reuse
the real renderer so the preview is exact.

---

## 6. The free-to-edit row + action + Update

The free row is where the user **composes one style** and then commits it. Pinned at the **top**,
all cells initialized from `net_hilight_style_default_row`, same widgets as table rows (§5.2), its
row-number cell shows `NEW`.

Next to it: an **action `ttk::combobox`** with two choices, then an **Update** button.

- **Add** — append the composed style as a brand-new row at the end of the table.
  `net_hilight_style_append {<composed row>}`.
- **Overwrite** — replace one *existing* row with the composed style. **Which row?** The one whose
  number the user types in a small **`row #` spinbox** that appears right beside the dropdown when
  "Overwrite" is chosen (range 0..N-1; defaults to 0). Press Update → that row's values are replaced
  by the free-row values. `net_hilight_style_merge {<row with index = that number>}`.

> Plain-language example: the table has rows 0,1,2. The user dials the free row to a thick red
> dashed style. With **action = Add**, Update creates a new **row 3** = that style. With **action =
> Overwrite, row # = 1**, Update makes **row 1** become that style and rows 0 and 2 are untouched.

After Update the table view refreshes from `net_hilight_style_current`; the free row keeps its
values so the user can add several similar styles quickly. Add always appends (re-positioning is the
job of Move/Duplicate in §7).

> (RESOLVED 2026-06-26: the `row #` spinbox is the chosen mechanism — confirmed over the
> focus-row alternative.)

---

## 7. Per-row operations

Buttons **Move ↑ / Move ↓ / Delete / Duplicate** act on the **table row that currently owns field
focus**. They are **greyed out** unless a *table* row (not the free row) has focus — tracked via
`<FocusIn>` bindings on that row's widgets recording a `current_edit_row` index (and `<FocusOut>`/
free-row focus clearing it).

All four recompute a new list and route through the existing procs (no new core code):
- **Move ↑/↓** — swap the focused row with its neighbour; `net_hilight_style_replace` (renumbers).
- **Delete** — `net_hilight_style_remove {focused}`.
- **Duplicate** — insert a copy **immediately below** the focused row; `net_hilight_style_replace`
  renumbers everything after it (satisfying "increment existing row numbers as necessary").

After any op the table view rebuilds and focus follows the moved/duplicated row so repeated ops chain.

---

## 8. Apply & persistence semantics (RESOLVED — live apply; the style table persists only on explicit, located Save)

Core rule from the requester, refined: the gate is about **potential damage, not the file
location.** A harmless UI breadcrumb (the "seen" flag) auto-persists to `~/.xschem` (§4.3); the
**style table** — which would change highlight appearance across the user's *other* projects — is
written only by an **explicit, user-located Save…**. Edits always apply *live* to the running
session regardless.

### 8.1 Live apply (no file writes)
Every committed change (Update, Move, Delete, Duplicate, per-cell edit-commit, Reset) flows through
an editor proc → `xschem update_net_hilight_style`, so the open schematic and any highlighted nets
reflect it **at once** — the dialog *is* the live preview for real nets, not just the swatch. None
of this touches disk.

### 8.2 Buttons: OK / Apply / Save… / Cancel
- **Apply** — force-(re)apply the current table to the running session and redraw, **stay open**.
  (Largely redundant under live-apply, but explicit and reassuring; also the commit point if a
  future variant batches edits instead of applying per-keystroke.)
- **OK** — keep the current (already-live) state and **close**. Writes nothing to disk.
- **Cancel** — **revert** the running session to the table as it was when the dialog opened, then
  close. Implemented by snapshotting `net_hilight_style` on open and, on Cancel, restoring it +
  `xschem update_net_hilight_style`. This is the "discard my experiments" escape hatch. (A config
  already written by an earlier **Save…** stays on disk — Cancel reverts the live session, not files.)
- **Save…** — the only path that writes a file (§8.3).

### 8.3 Save… — explicit location, with a warning when it is not the auto-load path
1. Open a **`tk_getSaveFile`** dialog defaulting to directory `$USER_CONF_DIR` and filename
   `net_hilight_style` (so the obvious choice is the auto-loaded location).
2. Write a **Tcl-sourceable** file via `write_net_hilight_style_conf <path>` (modeled on
   `write_recent_file`, `catch`-guarding I/O):
   ```tcl
   # xschem net highlight styles — generated by the Net highlight style editor
   set net_hilight_editor_seen 1
   set net_hilight_style { {0 …} {1 …} … }
   catch {xschem update_net_hilight_style}
   ```
3. **If `path` == `$USER_CONF_DIR/net_hilight_style`** (the path sourced at startup, §4.3): it will
   load automatically next session. Confirm quietly (status/CIW line).
4. **If `path` is anywhere else:** pop up a warning dialog —
   > Saved to `<path>`. This file will **not** be loaded automatically next session. To use it,
   > start xschem with:  `xschem --script <path>`  — or add  `source <path>`  to your
   > `~/.xschem/xschemrc`. (This command has also been printed to the CIW log.)

   and **echo the exact load command to the CIW log** via the CIW channel `ciw_echo`
   (see [[ciw-feedback-channels]] — use `ciw_echo`, not `puts`/the statusbar), e.g.:
   `ciw_echo "# to load these highlight styles next session: xschem --script {<path>}"`.

### 8.4 Notes
- A **dirty** flag tracks edits since the last Save…; **OK** and **Cancel** do **not** write the
  style table. **Closing the window via the WM ✕ button behaves like Cancel** (revert the live
  session to the open-time snapshot) — RESOLVED.
- **Reset to defaults** → `net_hilight_style_reset` (live), itself a savable state.
- The harmless **seen** marker (§4.3) is auto-written to `$USER_CONF_DIR/net_hilight_editor_seen`
  on first open; it is independent of Save… and of OK/Cancel.

---

## 9. Implementation map (where things go)

| Piece | Location |
|------|----------|
| `proc net_hilight_style_editor {{topwin {}}}` (the dialog) | new, `src/xschem.tcl` near the other `net_hilight_style_*` procs (`:512+`), or a new sourced `src/net_hilight_style_editor.tcl` loaded like `mouse_bindings.tcl` |
| `proc write_net_hilight_style_conf {path}` (located write) | `src/xschem.tcl`, modeled on `write_recent_file` (`:1506`); called from **Save…** via `tk_getSaveFile` |
| Save… location warning + CIW echo | in the dialog: `tk_getSaveFile` → compare to `$USER_CONF_DIR/net_hilight_style` → `tk_messageBox` + `ciw_echo` ([[ciw-feedback-channels]]) |
| Open-time snapshot / Cancel revert | dialog locals: snapshot `net_hilight_style` on open; Cancel restores + `xschem update_net_hilight_style` |
| Auto-written **seen marker** `$USER_CONF_DIR/net_hilight_editor_seen` (harmless; first open) | new `write_net_hilight_editor_seen` (one line: `set net_hilight_editor_seen 1`), `catch`-guarded |
| Startup load (source the seen marker, and `$USER_CONF_DIR/net_hilight_style` if present) | `src/xschem.tcl`, beside `load_recent_file` / after `set_ne net_hilight_style {}` (`:13386`) |
| Named-color dropdown source | read `/usr/share/X11/rgb.txt` (the file `find_best_color`→`XAllocNamedColor` uses, `src/xinit.c:277,286`) at dialog build; bundled fallback; validate names via `winfo rgb` |
| Tools-menu item | `src/xschem.tcl:~12397` |
| Palette row | `src/actions.csv` (new `tools.net_hilight_style_editor` row) |
| Palette color emphasis + `net_hilight_editor_seen` check | `src/action_registry.tcl` `palette_refilter` (`:404-417`): after the row insert, `$w.l itemconfigure <i> -foreground <accent>` when id matches and `seen==0` (no widget change) |
| Optional C preview query | `src/hilight.c` (reuse `net_hilight_style_on_now`/`net_hilight_march_offset`) |

No change to the row schema, the C compile path, or the apply/animation engine. The **style table**
is never auto-written — only the user-driven, located **Save…** writes it. The only automatic
`~/.xschem` write is the harmless one-line **seen marker** (§4.3).

---

## 10. Testing / acceptance

Headless-constructible where possible (Tk required for the dialog itself):
- **Procs round-trip:** drive Add/Overwrite/Move/Delete/Duplicate through the dialog's internal
  helpers and assert the resulting `net_hilight_style` equals a hand-computed expected list
  (reuse the `net_hilight_style_*` invariants: `index==position`, clamping).
- **Persistence round-trip:** Save… to a temp path → re-source it in a fresh interpreter →
  identical table + `net_hilight_editor_seen 1`. Save… to the auto-load path → present at startup.
- **Located-Save warning:** Save… to a path ≠ `$USER_CONF_DIR/net_hilight_style` raises the warning
  and the CIW receives the exact `xschem --script {<path>}` load line; Save… to the auto-load path
  does not warn.
- **Cancel reverts:** snapshot table, make edits (live), Cancel → table back to snapshot and the
  rendered highlights revert.
- **First-launch emphasis + permanent de-emphasis:** with `net_hilight_editor_seen 0`,
  `palette_refilter` color-marks the row. Opening the dialog sets the flag to 1 **and** writes
  `$USER_CONF_DIR/net_hilight_editor_seen`; re-sourcing that marker in a fresh interpreter yields
  `net_hilight_editor_seen 1`, so the row is unmarked in this and every future session.
- **Color source parity:** every name offered in the dropdown resolves via `winfo rgb` (the same
  X11 path `find_best_color` uses), and a chosen multi-word name is stored as a single-token name or
  hex so the saved row remains a valid 8-element Tcl list.
- **Live apply:** an edit changes the rendered highlight of an already-highlighted net (sample via
  the existing `net_hilight_dump_pixmap` / `net_hilight_test_now` hooks from the animation tests).
- **Widget↔model consistency:** every widget's value is a subset of what `net_hilight_style_norm`
  accepts (no widget can produce a value the normalizer would silently clamp), and blink/speed entry
  fields reject non-integers before apply.

---

## 11. Open questions / holes

**Resolved in review (2026-06-26, two rounds):**
- Palette emphasis = **font color, not bold** (keep the listbox; §4.1).
- Color cell = unified swatch + dropdown, **populated from the app's own X11 `rgb.txt` source**
  (not a curated list); multi-word names stored as CamelCase/hex (§5.2).
- Blink and march **Speed are plain entry fields with unit labels** (not sliders); **only Angle is a
  slider**; preview shows the result (§5.2).
- Dash = **always-visible text entry + an examples dropdown that fills it** (§5.2).
- Preview = **on-form animated canvas** (§5.3).
- Persistence: **live apply always**; the harmless **"seen" flag auto-persists** to a one-line
  `~/.xschem` marker; the **style table writes only via explicit located Save…**, with a warning +
  CIW echo when the path isn't the auto-load one (§4.3, §8).
- **WM ✕ = Cancel/revert** (§8.4).
- **All 8 columns** (incl. Width and Dash) are exposed (§5.1).
- **Overwrite target = the `row #` spinbox** in the free row (§6) — confirmed over the focus-row form.
- **One shared preview** that follows the focused row (§5.3) — confirmed (not per-row swatches).
- **Dialog modality** = non-modal, single instance, editing the one global table all windows share — confirmed.
- **Dash examples** = {Solid, Dash `6 4`, Dot `2 3`, Dash-Dot `6 3 2 3`, Long-Dash `12 4`} — confirmed.

**No open questions remain.** The spec is fully specified; implementation plan in
`claude_suggs/plan_net_hilight_style_editor.md`.

---

## 12. Out of scope (this spec)

- Changing the style **schema** or the C render/animation engine.
- The UI for **applying** a style to specific nets (already: `9`/`8`/`0`, `net_hilight_apply`,
  `hilight_netname -style`).
- A general palette-emphasis / "new feature" framework — the bold flag here is purpose-built for
  this one action (though §4.1-A would make per-row emphasis reusable).
