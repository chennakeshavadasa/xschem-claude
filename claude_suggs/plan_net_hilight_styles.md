# Plan — Net Highlight Styles (Pass 1, no animation)

Spec: `specs/net_hilight_styles.md`. This plan covers Pass 1 only. Animation (blink,
marching ants) is Pass 2 and is designed-for but not built here.

Guiding principle: land the **decoupling + static styling + commands** first (low risk,
reuses existing GC/dash/color machinery), then the **interactive keys** (modes), and
keep **nonzero stripe-angle rendering** isolated as the last, deferrable phase because it
is the only piece that needs new Cairo hatch rendering.

---

## Phase 0 — Survey confirmations (done)
Key anchor points confirmed by code survey:
- Highlight value→color: `get_color()` `hilight.c:359`, `incr_hilight_color()` `:372`,
  `draw_hilight_net()` `:~2191`; `Hilight_hashentry.value` `xschem.h:807`;
  `xctx->hilight_color` `xschem.h:1074`.
- GC precedent: `gc_hover`/`gc_scope` create `xinit.c:445` (`create_gc`), config
  `xinit.c:1089-1117`; width via `change_linewidth` `xinit.c:2374` + `XLINEWIDTH`.
- Dash: `drawline` dash branch `draw.c:1396-1411` (`XSetDashes`,`LineOnOffDash`); Cairo
  `my_cairo_drawline` `draw.c:1261-1264` (`cairo_set_dash`).
- Color resolve: `find_best_color()`; defaults `light_colors`/`dark_colors`
  `xschem.tcl:12601-12635`.
- Modes: `ui_state` `xschem.h:221`; `update_statusbar` `callback.c:5713`;
  `abort_operation` `callback.c:173`; Escape `callback.c:4905`; Button1 dispatch
  `callback.c:5189`.
- Find net: `find_closest_obj` / `find_closest_wire` `findnet.c:28`,
  `find_closest_net_or_symbol_pin` `findnet.c:201`; net name `xctx->wire[n].node`.
- CIW/status: `statusmsg` `scheduler.c:28`; `log_action`/`ciw_echo` `util.c:346`.
- Selection query: `xschem get lastsel` `scheduler.c:1764`, `first_sel` `:1698`,
  `xschem selection` `:6595`; types `WIRE=1 … xTEXT=16 ELEMENT=8` `xschem.h:265`.
- Keybind: `cadence_style_rc` (`src/`); `xschem bind key` → `action_cmd_bind`
  `callback.c:3265`; registry `set_input_binding` `:2906`, `dispatch_input_action`
  `:3088`, `handle_key_press` `:3686`. Digits `8/9` bare are no-ops, `0` toggles pin
  logic — safe to override.

---

## Phase 1 — Style-table data model + decoupling (color only)
**Outcome:** highlights are indexed by *style*, not layer color; visual output is
identical to today (default table reproduces layer cycling). No new visuals yet.

C structures (`xschem.h`):
```c
typedef struct {
  int   index;
  unsigned int color;     /* resolved X pixel */
  int   color_layer;      /* layer fallback for get_color() compat, -1 if pure pixel */
  int   width;            /* multiples of base wire width; >=1 */
  char *dash;             /* raw "on off ..." spec, NULL/"" = solid */
  int   dash_len; char dash_arr[16];
  int   angle;            /* 0..45, clamped */
  int   blink_ms;         /* Pass 2 */
  int   anim;             /* 0 none,1 fwd,2 rev — Pass 2 */
  int   rate_persec;      /* Pass 2 */
  GC    gc;               /* per-style GC: color+width+dash baked in */
} NetHilightStyle;
```
Add to `Xschem_ctx`: `NetHilightStyle *net_hilight_style; int n_net_hilight_styles;`.

Edits:
- `hilight.c`: add `get_hilight_style(int value)` → `&xctx->net_hilight_style[value %
  n]`. Reduce `get_color()` to return `get_hilight_style(value)->color_layer` (or the
  resolved color) so any color-only caller is unaffected.
- `incr_hilight_color()`: advance modulo `xctx->n_net_hilight_styles`.
- Build a **default table** (in C or `xschem.tcl`) = one steady/solid/width-1 style per
  active layer, so behavior is unchanged when the user supplies no table.

**Verify:** build clean; `tclsh run_regression.tcl` green (highlighting golden output
unchanged). Sabotage-check per [[green-but-hollow]]: temporarily set a default style to
a wrong color, confirm a highlight test actually changes, then revert.

---

## Phase 2 — Per-style width + dash rendering (GC pool, 0° barcode)
**Outcome:** color + thickness + dash pattern all honored. Stripe-angle still 0.

- `xinit.c`: `build_net_hilight_gcs()` — for each style, `XCreateGC`, set foreground to
  the resolved pixel, `XSetLineAttributes(width, dash?LineOnOffDash:LineSolid, …)`, and
  `XSetDashes` from `dash_arr`. Create alongside `gc_hover`/`gc_scope`; free in the
  matching teardown. Width maps `style.width` → `XLINEWIDTH(xctx->lw) * style.width`.
- `hilight.c::draw_hilight_net()`: replace `drawline(get_color(entry->value), THICK,…)`
  with a draw that uses `style->gc` (a `drawline_gc`-style helper, or temporarily point
  the layer GC at the style attributes). Mirror for the Cairo path
  (`my_cairo_drawline` + `cairo_set_dash`, `cairo_set_line_width`).
- Endpoint dots (`filledarc`) take the style color.

**Verify:** manual GUI smoke test — define 3 styles (solid thin, dashed medium, dashed
thick), highlight three nets, confirm distinct width+dash. Regression still green.

---

## Phase 3 — Commands, default table, settings file, docs
- `scheduler.c`: add `xschem update_net_hilight_style` — read `net_hilight_style` Tcl
  var (`tclgetvar` + Tcl list parse, or `Tcl_ListObj` via eval), compile to the C array,
  resolve colors, **clamp `angle` to [0,45] emitting a warning per clamp** through
  `statusmsg`/`ciw_echo` naming the style index, rebuild GC pool, redraw.
- `scheduler.c`: extend `hilight_netname` (and `hilight`) to parse `-style N`
  (explicit style, no cursor advance).
- `xschem.tcl`: ship default `net_hilight_style` (set_ne) reproducing Phase-1 defaults;
  call the compile once at startup after rc sourcing.
- New `src/net_hilight_style_rc` example (sourced, sets the table + calls
  `xschem update_net_hilight_style`).
- Docs: short section in the appropriate doc + comments in `xschemrc` showing the table
  format (mirrors how `light_colors`/`dark_colors` are documented).

**Verify:** edit table → `xschem update_net_hilight_style` → highlights change; bad
angle (e.g. 70) → clamped to 45 + warning in CIW. `-style 3` path highlights with the
exact style.

---

## Phase 4 — Interactive keys 9 / 0 / 8 (modes, noun-verb + verb-noun)
- `xschem.h`: add `STARTHILIGHTNET`, `STARTUNHILIGHTNET` ui_state bits.
- `scheduler.c`: subcommands `hilight_net_interactive` / `unhilight_net_interactive`:
  - If `xctx->lastsel` has wire/label objects → noun-verb: apply (add/remove) highlight
    on the selection using the cursor (advance per net), **leave selection intact**.
  - Else → set the corresponding `ui_state` mode bit and draw the prompt.
- `callback.c`:
  - `update_statusbar` (~5713): prompt branches for the two modes.
  - Button1 dispatch (~5189): when a mode bit set, `find_closest_obj`, resolve net,
    add/remove highlight (route through `hilight_net()` / hash `XDELETE`), advance
    cursor on add, redraw, `return`. Transient (no leftover selection).
  - `abort_operation` (~173) + Escape (~4905): clear the mode bits.
  - CIW prompt via `ciw_echo` on mode entry.
- `cadence_style_rc`: register/locate action ids and bind:
  ```tcl
  xschem bind key 57 0 canvas net.hilight          ;# '9'
  xschem bind key 48 0 canvas net.unhilight_all    ;# '0'  -> xschem unhilight_all
  xschem bind key 56 0 canvas net.unhilight        ;# '8'
  ```
  (Actions are Tcl-backed wrappers calling the subcommands, validated by
  `find_action_def`.)

**Verify (per [[user-run-config]], run with cadence_style_rc):**
- Select a wire, press 9 → highlighted, still selected. Press 9 again → next style.
- Select a label, press 9 → its net highlighted, still selected.
- Deselect all, press 9 → status+CIW prompt; click nets → each gets next style; ESC
  exits; prompt clears.
- Press 0 → all cleared.
- Select net, press 8 → highlight removed, still selected. Deselect, press 8 → mode;
  click highlighted net → its highlight removed; ESC exits.

---

## Phase 5 — Nonzero stripe-angle rendering (DEFERRED to Pass 1.5)
NOTE (locked 2026-06-23): Pass 1 = Phases 1-4 only. The `stripe-angle-deg` column,
parsing, clamp-to-[0,45], and warning are implemented in Phase 3; nonzero angles render
as plain 0° dashes until this phase lands. This phase is Pass 1.5.

Native dashes are perpendicular-only, so tilted stripes need custom rendering:
- Cairo path: build the thick-wire rectangle (quad) from the segment + width, set it as
  a clip, and stroke a family of parallel segments at `wire_angle + 90° - angle`, spaced
  per the dash pattern, thickness = the "on" run. Resolution-independent.
- `HAS_CAIRO` absent → fall back to angle 0 (plain dash) + one-time warning.

Isolated so Phases 1-4 ship a fully useful feature (color + width + dash + 0° barcode)
even if this phase slips.

**Verify:** a style at 30° and one at 45° render visibly tilted stripes on thick wires;
70° in the table is clamped to 45 with a warning; Xlib-only build degrades to 0°.

---

## Pass 2 (future, NOT in this plan)
Timer-driven blink (`blink_ms`) + marching ants (`anim`,`rate_persec`). Tick calls only
`draw_hilight_net()` (cheap — highlights are a small screen fraction); marching ants
animate the `XSetDashes` dash_offset (currently always 0) / `cairo_set_dash` offset.
Per-window timers. No xschem timer infra exists yet — this is the only new subsystem and
is deliberately deferred.

---

## Risks / watch-items
- **Decoupling regressions**: defaults must reproduce current cycling exactly; guard with
  regression + sabotage check.
- **Stripe-angle complexity**: the one item that can balloon; keep it last and behind
  `HAS_CAIRO`.
- **GC lifecycle / per-window**: build and free the style GC pool per `xctx`; rebuild on
  theme change and on `update_net_hilight_style`.
- **Digit-key override**: confirm registry binding preempts the legacy `'0'` pin-logic
  handler under `cadence_style_rc`.
- **Memory**: use `my_malloc`/`my_strdup` (`_ALLOC_ID_`) for the style array and dash
  strings.

## Decisions (LOCKED 2026-06-23)
1. Command name: **`update_net_hilight_style`**.
2. Multi-net noun-verb: **per-net cursor advance** (N nets -> N successive styles).
3. Stripe-angle: **Pass 1.5** — Pass 1 is Phases 1-4 (color+width+dash+0° barcode);
   column/clamp/warning still implemented in Phase 3.
