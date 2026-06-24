# Net Highlight Styles — Customizable, Command-Driven Net Highlighting

Status: SPEC (Pass 1 = no animation). Author handoff doc.
Related memory: [[hover-highlight]], [[apply-scope-highlight]], [[action-registry]], [[cadence-bindkeys]].

## 1. Goal

Bring xschem net highlighting closer to Cadence Virtuoso's `display.drf` model:
a **command-driven**, **user-customizable** highlight system where the set of
highlight "styles" is defined in a sourced Tcl table rather than hardwired. Unlike
Cadence (which is limited to 10 highlight packets `y0`..`y9`), we support an
**arbitrary number of styles**, each controlling **color, thickness, dash pattern,
and stripe angle**, with **blink and marching-ants animation designed in but deferred
to Pass 2**.

Being command-driven is a deliberate strategic choice: it is the bridge for future
interoperation with simulation waveform viewers and back-annotation tools, which can
drive highlights via `xschem hilight_netname -style N <net>` over the existing Tcl
channel (the `*_backannotate.tcl` files are precedent).

## 2. Scope

### Pass 1 (this spec) — NO animation
- Decouple "highlight style" from "layer color" (the load-bearing refactor).
- A Tcl style table `net_hilight_style`, sourced from a file, compiled on the C side.
- Per-style: **color, width, dash-pattern, stripe-angle-deg** (static visual).
- The animation columns (**blink_ms, anim, rate_persec**) are *parsed and stored from
  day one* but **ignored** in Pass 1. This keeps the file format and command contract
  stable so Pass 2 adds behavior without changing the schema.
- An explicit rebuild command (changing the Tcl variable alone is NOT enough).
- Interactive keyboard shortcuts `9` / `8` / `0` in `cadence_style_rc`, supporting both
  noun-verb and verb-noun interaction.

### Pass 2 (future, out of scope here)
- Blink (`blink_ms`) and marching-ants (`anim`, `rate_persec`) via a timer that
  redraws *only* highlighted nets. No timer infrastructure exists in xschem today;
  this is the only genuinely new subsystem and is intentionally walled off.

## 3. The style table

### 3.1 Variable and file

A Tcl list named `net_hilight_style`, set in a file the user `source`s (or directly in
`~/.xschem/xschemrc` / `cadence_style_rc`). A default table ships in `xschem.tcl` so the
feature works out-of-the-box and reproduces today's behavior.

Each row is a list with these columns, in order:

| Col | Name              | Meaning                                                              | Pass 1 |
|-----|-------------------|---------------------------------------------------------------------|--------|
| 1   | `index`           | Style id (0-based). Determines table ordering / cycling position.    | used   |
| 2   | `color`           | Color spec: `#rrggbb`, X color name (`yellow`), or layer index.      | used   |
| 3   | `width`           | Line thickness. **`1` = same thickness as the thinnest wire.**       | used   |
| 4   | `dash-pattern`    | Tcl list of on/off run lengths, e.g. `{}` solid, `{4 4}`, `{8 4 2 4}`.| used  |
| 5   | `stripe-angle-deg`| Tilt of dash "stripes" on a thick line. Clamped to **[0, 45]**.      | used*  |
| 6   | `blink_ms`        | Blink period in ms (`0` = steady).                                   | stored |
| 7   | `anim`            | Animation mode: `none` / `march_fwd` / `march_rev`.                  | stored |
| 8   | `rate_persec`     | Animation rate (stripe shifts per second) for `anim`.               | stored |

\* `stripe-angle-deg` is parsed, clamped to [0,45], and stored in Pass 1, but **nonzero
angles are rendered as plain 0° dashes until Pass 1.5** (tilted-stripe rendering needs
Cairo hatch; see §7 / Phase 5). The column and clamp behavior are final in Pass 1.

Example (`net_hilight_style_rc`, to be `source`d):

```tcl
# index  color      width  dash         angle  blink anim        rate
set net_hilight_style {
  {0  "#ff0000"   1   {}          0    0    none        0 }
  {1  "#00ff00"   2   {4 4}       0    0    none        0 }
  {2  "yellow"    3   {8 4 2 4}   30   0    none        0 }
  {3  "#0099cc"   2   {6 6}       45   0    none        0 }
  {4  "#ce0097"   1   {}          0    0    none        0 }
  ...
  {37 "cyan"      4   {10 4}      20   0    none        0 }
}
xschem update_net_hilight_style
```

There is **no 10-entry limit**. The table length *is* the number of styles.

### 3.2 Semantics of columns

- **color**: resolved on the C side to an X pixel via the existing
  `find_best_color()` path (same as `hover_highlight_color`/`slickprop_highlight_color`).
  Accepting a bare integer also lets a style alias an existing layer color for
  backward-compatible defaults.
- **width**: `1` maps to the thinnest wire rendering (`XLINEWIDTH(xctx->lw)` baseline);
  values `> 1` are integer multiples of that base width. Widths scale with zoom exactly
  as wire widths do (honoring `change_lw`/`min_lw`), so highlights track the wire.
- **dash-pattern**: an empty list `{}` is solid. A non-empty list is fed to Xlib
  `XSetDashes` (and `cairo_set_dash`) as the on/off run pattern. With width > 1, each
  "on" run is a band across the line = a **stripe**; with `angle = 0` the bands are
  perpendicular to the wire (a barcode).
- **stripe-angle-deg**: tilts the stripes. `0` = perpendicular (native dash). As the
  angle grows the stripes shear toward parallel-with-the-wire, which is degenerate, so
  the input is **clamped to a maximum of 45°** (and minimum 0°). When clamping occurs,
  `update_net_hilight_style` emits a **warning to the log/CIW** naming the offending
  style index and the original vs clamped value.
- **blink_ms / anim / rate_persec**: parsed, validated, and stored in Pass 1; have no
  visual effect until Pass 2.

## 4. Decoupling style from layer color (the refactor)

Today (`hilight.c`):
- `Hilight_hashentry.value` (per net) and `xInstance.color` hold a **color index**.
- `get_color(value)` maps it modulo `n_active_layers` onto a **layer color**.
- `incr_hilight_color()` advances `xctx->hilight_color` modulo `n_active_layers*cadlayers`.

After Pass 1:
- `value` / `inst.color` hold a **style index** into the compiled style table.
- A new resolver `get_hilight_style(value)` returns a `NetHilightStyle*` (color pixel,
  width, dash, angle, …). The legacy `get_color()` becomes a thin wrapper that returns
  `style->color_layer` for any code path still asking only for a color.
- `incr_hilight_color()` advances modulo **`n_net_hilight_styles`** (the table length).
- **Backward compatibility**: the default table is generated to reproduce the current
  layer-color cycling (one steady, solid, width-1 style per active layer), so existing
  behavior, tests, and `.sch`-embedded highlights are unchanged when no custom table is
  provided.

Touch points (from code survey):
- `src/hilight.c`: `get_color()` (~359), `incr_hilight_color()` (~372),
  `draw_hilight_net()` (~2191) — switch the `drawline(get_color(...), THICK, ...)` calls
  to select the style's GC (color+width+dash) instead of a layer color.
- `src/xschem.h`: `Hilight_hashentry` (~807), `xctx->hilight_color` (~1074); add the
  style-table array, count, and GC pool fields to `Xschem_ctx`.
- `src/xinit.c`: build/destroy the per-style GC pool alongside `gc_hover`/`gc_scope`
  (`create_gc` ~445, the hover/scope GC config ~1089-1117).

## 5. Commands

### 5.1 `xschem update_net_hilight_style`
Re-reads the `net_hilight_style` Tcl variable, (re)compiles it into the C style array,
resolves colors to pixels, **clamps stripe angles to [0,45] with a warning per clamp**,
rebuilds the per-style GC pool, and triggers a redraw. **Must be called after changing
the table** — the Tcl variable alone has no effect because styles are compiled into GCs.
(Naming: `update_net_hilight_style` chosen for prefix consistency with the
`net_hilight_style` variable; see open decision in §8.)

### 5.2 `xschem hilight_netname [-style N] [-fast] <net>` (extend existing)
`-style N` highlights `<net>` with style index `N` explicitly (no cursor advance). This
is the **waveform-viewer / back-annotation bridge**. Without `-style`, behavior is
unchanged (uses the current cursor + auto-increment rules).

Analogous `-style` extension for `xschem hilight` / `hilight_instname` where it makes
sense.

### 5.3 Existing commands reused unchanged
- `xschem unhilight_all` — clear all highlights (bound to key `0`).
- `xschem unhilight` — clear highlights on the current selection.

### 5.4 Style cursor / increment semantics
A "current style cursor" (`xctx->hilight_color`, repurposed as a style index) advances
by one **each time a highlight is applied**, and **wraps**: after the last row it
returns to row 0 and cycles (advance is modulo table length,
`n_net_hilight_styles`). Re-highlighting the same net therefore moves it to the next
style. This governs both interactive paths (§6). Explicit `-style N` does not advance
the cursor (and is itself taken modulo the table length so an out-of-range index is
always valid).

## 6. Interactive keyboard shortcuts (in `cadence_style_rc`)

All three bind via the data-driven action registry
(`xschem bind key <keysym> 0 canvas <action>`), preempting the legacy C digit handlers
(`'8'`/`'9'` are no-ops bare; `'0'` toggles pin logic — all safe to override in this rc).
The status-bar prompt reuses the wire-draw mechanism (`update_statusbar`, the
`{DRAW WIRE! }` slot `.statusbar.10`); the CIW message uses `ciw_echo` (per
[[ciw-feedback-channels]], not `puts`/statusbar).

### 6.1 Key `9` — Highlight net (noun-verb AND verb-noun)
- **Noun-verb** (selection contains net wire(s) and/or label(s)): highlight the selected
  net(s) using the style cursor, advancing the cursor per net highlighted. **The
  selection is LEFT INTACT** (do not `unselect_all`). Command completes immediately.
- **Verb-noun** (nothing selected): enter **Highlight-Net mode**:
  - Status bar shows a persistent prompt (e.g. `HIGHLIGHT NET — click a net/label, ESC to exit`).
  - A matching prompt is echoed to the CIW log via `ciw_echo`.
  - Each left-click highlights the net/label under the cursor with the current style,
    then **advances the cursor** (so successive clicks — even on the same net — cycle
    styles).
  - Mode persists until **ESC** (handled in `abort_operation`).
  - Clicks in mode are transient (they do not leave the net selected).

Both "net" forms are supported: a **wire** (`xctx->wire[n].node`) and a **label**
(a label/pin instance). Implementation resolves the clicked/selected object via
`find_closest_obj` and routes through the existing `hilight_net()` (which already
handles wires, labels, pins, and propagation).

### 6.2 Key `0` — Unhighlight all
Bound directly to `xschem unhilight_all`. Removes all net highlights.

### 6.3 Key `8` — Remove specific net highlight (noun-verb AND verb-noun)
- **Noun-verb** (selection contains net/label): remove highlight on the selected net(s)
  (`xschem unhilight`), leaving the selection intact.
- **Verb-noun** (nothing selected): enter **Unhighlight-Net mode** — same prompt/CIW/ESC
  pattern as §6.1, but each click removes the highlight on the net/label under the cursor
  (hash `XDELETE` + redraw). Persists until ESC.

### 6.4 Modes — implementation notes
- New `ui_state` bits, e.g. `STARTHILIGHTNET` and `STARTUNHILIGHTNET`
  (`xschem.h` ~221), modeled on `STARTWIRE`.
- Prompt added as a branch in `update_statusbar` (`callback.c` ~5713).
- ESC clears the bits in `abort_operation` (`callback.c` ~173) and the Escape case
  (~4905).
- Click handling: a branch in the Button1 dispatch (`callback.c` ~5189) that, when a
  mode bit is set, finds the net under the cursor and add/removes its highlight, then
  returns (does not fall through to normal selection).

## 7. Pass 1 phase breakdown
See the implementation plan (`claude_suggs/plan_net_hilight_styles.md`). Summary:
1. Style-table data model + decoupling (color only; visual parity, now style-indexed).
2. Per-style width + dash rendering via a GC pool (the 0° barcode case).
3. `update_net_hilight_style` (with angle clamp+warn) + `-style N` command arg +
   default table in `xschem.tcl` + example `net_hilight_style_rc` + docs.
4. Interactive keys `9`/`0`/`8`: modes, noun-verb/verb-noun, prompts, CIW, ESC,
   `cadence_style_rc` bindings.
5. (Flagged / deferrable to Pass 1.5) Nonzero stripe-angle rendering via Cairo clip+hatch;
   Xlib-only builds fall back to angle 0 with a one-time warning.

## 8. Decisions (LOCKED 2026-06-23)
1. **Update-command name**: `update_net_hilight_style`.
2. **Multi-net noun-verb increment**: advance the cursor **per net** — N selected nets
   get N successive styles (matches Cadence's "each highlight a new color").
3. **Stripe-angle scope**: **deferred to Pass 1.5.** Pass 1 ships color + width + dash +
   0° barcode (Phases 1-4). Nonzero stripe angles (Cairo hatch rendering) come after.
   The `stripe-angle-deg` column and the clamp-to-45°+warning in
   `update_net_hilight_style` are still implemented in Pass 1 so the schema and command
   contract are final; only the *rendering* of nonzero angles is deferred (until then a
   nonzero angle is accepted, stored, and rendered as a plain 0° dash).

## 9. Non-goals / constraints
- **Styles apply to wires.** Per the "just wires" scope, the width/dash/custom-color
  style is applied to highlighted **wire segments**. Instances/pins/labels on a
  highlighted net keep the existing layer-color highlight. For default and layer-index
  styles this is visually consistent (same layer color on wire and symbol); for a
  **custom RGB** style the wire shows the custom color while symbols on the net show the
  nearest fallback layer color. Generalizing the style to the instance render path
  (`draw_symbol`) is a possible follow-up.
- **Export renderers** (`svgdraw.c`, `psprint.c`) and the ngspice plot-color generator
  resolve highlights through the layer-index path (`get_color`), so exported SVG/PDF/PS
  reflect highlight *color* (approximately, via a fallback layer for custom RGB) but not
  width/dash. On-screen rendering is the Pass-1 deliverable.
- **Custom named colors** are resolved to a pixel once (at `update_net_hilight_style`).
  On a TrueColor visual (the modern default) those pixels are stable across colorscheme
  changes. On legacy palette (PseudoColor) visuals, re-run `xschem
  update_net_hilight_style` after switching colorscheme to re-resolve them. (Not hooked
  into `build_colors`, which is on the redraw/dim hot path.)
- No animation in Pass 1 (blink, marching ants) — schema only.
- C89 throughout; nonzero stripe angles require Cairo (`HAS_CAIRO`); Xlib-only builds
  degrade gracefully to angle 0.
- Per-window/per-tab correctness: each `xctx` owns its GC pool; the rebuild iterates
  live windows (relevant given multi-window work, [[multi-window-detach]]).
