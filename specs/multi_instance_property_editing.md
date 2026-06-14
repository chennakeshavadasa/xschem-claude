# Spec — multi-instance property editing (Cadence-style)

*Status:* **DRAFT / design.** No implementation yet. Builds on the slick
per-field property form ([[slick-property-forms]], branch `slick-property-forms`)
and the stable instance handles ([[stable-object-handles]]).

*Summary:* when several instances are selected and the user opens the Properties
form, give Cadence-grade support: a **Next / Prev** walk through the targets, an
**"Apply to"** scope (Only Current / All Selected / All), automatic **greying of
attributes that cannot apply to many** (e.g. `name`), and **on-canvas
highlighting** that distinguishes *selected* from *being-edited* and reflects the
current scope live.

---

## 1. What happens today (verified in the code)

When you select N instances and invoke Edit Properties (`xschem edit`, key `Q` →
`edit_property(0)`, `editprop.c:1157`):

1. The selection array is rebuilt; the **first** selected object decides the type
   (`set_first_sel`, `editprop.c:1288`). For instances it calls
   `edit_symbol_property(x, j)` on that **first** instance only.
2. If more than one object is selected, **`preserve_unchanged_attrs` is forced on**
   (`editprop.c:1282`). The dialog opens showing the **first** instance's
   properties (via the slick form → `slickprop::edit_form`, which sets
   `tctx::retval` to that instance's string).
3. On **OK**, `update_symbol()` (`editprop.c:834`) **loops over every selected
   instance** (`for(k=0;k<xctx->lastsel;++k)`, `:885`) and, because
   `preserve_unchanged_attrs` is on, applies only the **changed** tokens to each:
   `set_different_token(&inst.prop, new_prop, old_prop)` — "modify only the token
   values that differ between *new* and *old*" (`token.c:204-207`), where *old* is
   the **first** instance's original string. Each instance keeps its own other
   attributes. Per-instance unique-name enforcement then runs (`:948` ff).

**So the effective behavior today is "All Selected, changed-fields-only" — but
with no UI for it:** the user is silently editing the first instance, can't tell
they're affecting N, has no scope choice, no navigation, no greying, and the
canvas highlight doesn't change. (There is a niche `edit_symbol_prop_new_sel`
chain-loop at `:1295` that re-edits the next mouse-clicked instance; the slick
form does not drive it.)

### 1.1 The good news: the apply engine already exists

The hard part — "apply the fields I changed to a set of instances, preserving
each one's other attributes" — is already built and battle-tested
(`set_different_token` + the `update_symbol` loop). This dovetails exactly with
the slick form's model: the form already tracks **dirty fields** and emits
`new_prop` = first-instance + my edits (subst-into-original). `set_different_token`
then extracts precisely those edits and fans them out. **This feature is therefore
mostly a UI + scope-selection + highlighting layer over an engine that already
does the work** — not a new editing core.

---

## 2. The gap vs. Cadence

| Cadence capability | xschem today |
| --- | --- |
| Next / Prev through the target instances | — (edits the first only) |
| "Apply to": Only Current / All Selected / All | partial: implicitly "All Selected, changed-only" when >1, no control |
| Grey attributes that can't apply to many (name…) | — (relies on per-instance unique-name fixups after the fact) |
| Canvas highlight: *selected* vs *being-edited*, scoped, live | — (selection highlight only, static) |

---

## 3. Desired behavior

### 3.1 "Apply to" scope selector

A dropdown in the form header with three modes:

- **Only Current** — changes apply to the one instance currently shown.
- **All Selected** — changes apply to every selected instance (today's implicit
  behavior, now explicit). Default when N > 1.
- **All** — changes apply to a larger set (see the open question in §6.A about
  whether "All" means *all instances of the same symbol/master* — recommended —
  or *all instances in the schematic*).

The scope only governs **which instances receive the change set on OK**; it does
not change what the form displays (that is Next/Prev, §3.2). Default scope:
*Only Current* when one instance is selected, *All Selected* when several are.

### 3.2 Next / Prev navigation

Two buttons (and ideally `Alt+Right`/`Alt+Left`) that step the **currently
displayed** instance through the target set, with a position readout
("Instance 2 of 7"). Navigation lets the user inspect/seed from each instance
before applying. The cross-cutting design question — do pending edits persist
across navigation, and are they applied per-step or only on OK — is §6.B; the
recommended model is a single **change set** (the dirty fields) applied to the
scope on OK, with Next/Prev re-seeding the displayed values from each instance
while the change set rides along.

### 3.3 Greying attributes that can't apply to many

When the scope is **All Selected** or **All**, attributes that are inherently
per-instance are shown **disabled (greyed, read-only)**:

- **`name`** always (instance names must be unique — applying one name to many is
  meaningless and the engine would have to uniquify anyway).
- Any attribute the symbol marks as per-instance (a future template hint, e.g.
  `unique=name,...`); for v1 a built-in rule covering `name` is enough.

A greyed field is excluded from the change set, so each instance keeps its own.
When the scope returns to **Only Current**, the fields re-enable.

### 3.4 On-canvas highlighting (the "cool factor")

Three visual states, distinct from each other:

1. **Selected** — the existing selection look (`draw_selection`, `gc[SELLAYER]`,
   `move.c:210`).
2. **Being edited — current** — the single instance whose values are shown now
   (Next/Prev moves this), drawn with a distinct, stronger accent.
3. **Being edited — in scope** — every instance the change set *will* touch given
   the current "Apply to" value, drawn with a second distinct accent.

The highlight updates **live** as the user changes scope or navigates: choosing
*All Selected* lights all selected; *All* lights the whole set; *Only Current*
lights just the displayed one; Next/Prev moves the "current" accent. On close,
the canvas reverts to the plain selection.

---

## 4. How it maps onto xschem's architecture

- **Form (Tcl, `slickprop::`).** Owns the scope dropdown, Next/Prev, the
  position readout, the greying, and the per-instance display. It already has the
  dirty-field model (the change set) and the field grid. New state: the target
  list (the selected instances, by **stable instance id** so it survives any
  reindexing — leveraging [[stable-object-handles]]), the current index, the scope.
- **Apply (C, `update_symbol`).** Largely reusable. The form computes `new_prop`
  from the displayed instance + the change set; the scope decides which instances
  the C loop visits. Today the loop walks `sel_array`; for *Only Current* it would
  visit one, for *All* it would walk a wider set. The cleanest seam: the form
  passes C the **target id list** + the change set; a thin C entry applies
  `set_different_token` per target. (Alternatively, keep the existing `sel_array`
  loop and have the form adjust the selection to match the scope before OK — less
  clean, mutates selection.)
- **Highlight (C draw).** Needs a new transient "edit-scope" overlay. A new
  `xschem` subcommand — e.g. `xschem edit_highlight {current <id>} {scope <id> <id> …}`
  — records the ids and triggers a draw pass that overlays those instances with
  the two accents (a `draw_temp_symbol`-style overlay in distinct GCs, beside the
  existing `draw_selection`). The form calls it whenever scope/navigation changes
  and clears it on close. Referencing instances **by stable id** is exactly what
  the handles work enables.

---

## 5. Phasing (incremental, each shippable)

1. **P1 — make the implicit explicit.** Add the "Apply to" dropdown (Only Current
   / All Selected) wired to the *existing* engine: *Only Current* edits just the
   shown instance; *All Selected* keeps today's behavior. Grey `name` when scope
   is multi. No navigation, no new highlight yet. Small, high-value, low-risk.
2. **P2 — Next/Prev.** Walk the displayed instance through the selected set, with
   the "k of N" readout; settle the change-set-vs-navigation model (§6.B).
3. **P3 — the highlight.** The C edit-scope overlay (two accents) updated live
   from scope/navigation; the marquee "cool factor."
4. **P4 — "All".** Add the third scope once §6.A is decided; needs care
   (greying/attribute-set mismatches across different masters).

P1 alone closes most of the usability gap, because the apply engine is already
there.

## 6. Open questions / decisions to ratify

- **A. What does "All" mean?** *All instances of the same symbol/master*
  (recommended — their attribute sets match, so applying a changed token is
  meaningful) vs *all instances in the schematic* (the user's literal phrasing,
  but applying e.g. `value` to a resistor and a MOSFET is ill-defined). Could also
  offer both ("All like this" vs "All").
- **B. Edits across Next/Prev.** One change set applied to the scope on OK
  (recommended, simplest, matches the engine) vs per-instance pending edits
  (closer to editing each instance individually, but much more state). Also: is
  there an **Apply** button (apply without closing, then keep navigating) like
  Cadence?
- **C. Display when values differ.** With *All Selected*, instances may hold
  different values for the same attribute. Show the current instance's value
  (recommended) — and should a field whose value varies across the set be marked
  (e.g. "<*>" or a muted hint) so the user knows applying it will overwrite
  differing values? (A nice Cadence-like touch for P2/P3.)
- **D. Greying source.** Hardcode `name` for v1 vs a symbol-template hint
  (`unique=...`) so symbols can declare additional per-instance attributes.
- **E. Highlight styling.** Exact colors/relief for *being-edited-current* vs
  *being-edited-scope*, and theme (light/dark) behavior; reuse SELLAYER-style GCs
  or add dedicated ones.
- **F. Undo granularity.** One undo entry for the whole multi-apply (the engine
  already pushes a single undo via the `pushed` guard, `editprop.c:901/911`) —
  confirm that remains true for the new scopes.

## 7. Grounding (code references)

- Dispatch + multi-select handling: `edit_property` `editprop.c:1157`, the
  `lastsel>1 → preserve_unchanged_attrs` force `:1282`, the type switch `:1291`,
  the chain-edit loop `:1295`.
- The apply engine: `update_symbol` loop `editprop.c:885`, `set_different_token`
  `token.c:204-207`, unique-name fixups `editprop.c:948`.
- The form: `slickprop::edit_form` / dirty-field model (`src/property_form.tcl`),
  the C↔Tcl contract (`tctx::retval`/`tctx::rcode`, `symbol`,
  `no_change_attrs`/`preserve_unchanged_attrs`).
- Selection highlight: `draw_selection` `move.c:210`, drawn with `gc[SELLAYER]`.
- Stable instance ids (for referencing targets across edits / in the highlight
  command): `xschem instance_id`/`instance_index`, `xschem object instance @id`.

---

*This is a design spec, not a plan. Recommended next step: ratify §6.A and §6.B,
then implement P1 (the "Apply to" dropdown + name-greying over the existing
engine) on the `slick-property-forms` branch.*
