# Plan — slick per-property edit forms (Cadence-style)

*Goal:* replace XSCHEM's raw single-text-box property editor (the "Edit
Properties" dialog) with a structured Tk form that gives **one validated entry
field per property**, eliminating malformed `token=value` input, with **Enter =
OK** (from any field) and **Escape = Cancel** (any time, discard changes).

Status: **PLAN ONLY — no code yet.** Branch `slick-property-forms`. Analysis
below is run-verified against the build on this branch.

---

## 1. What the dialog is today (the screenshot)

The "Edit Properties" window is the Tcl proc **`edit_prop {txtlabel}`**
(`src/xschem.tcl:7372`). It is the instance/symbol attribute editor. Its core is
a single multi-line `text` widget (`.dialog.symprop`) holding the object's
**entire raw property string**, e.g.

```
name=E1 TABLE="1.4 0.0 1.6 4.0"
```

The user edits that string by hand. Around it: a Symbol entry + Browse/Load/
Del, three checkbuttons (No change properties / Preserve unchanged props / Copy
cell), and an "Edit Attr" combobox that lets you isolate one token at a time.

**Why it's bad:** the user types free-form `token=value` text, so `penguin=shark`
is accepted silently; long unstructured strings are unreadable; there is no
field-level structure, default visibility, or validation.

## 2. The C ↔ Tcl contract (the key enabler)

The property editors all follow the same protocol, and it is what makes a slick
form **mostly a Tcl-only change**:

1. **C** (`editprop.c`, e.g. `edit_property()` / `edit_symbol_property()`) puts
   the object's current property string into the Tcl variable `tctx::retval`,
   then calls the Tcl dialog proc.
2. **The Tcl dialog** lets the user edit, then on OK sets `tctx::retval` to the
   **new** property string and `tctx::rcode` to `ok` (Cancel leaves `rcode`
   empty).
3. **C** checks `tctx::rcode != ""`, reads `tctx::retval`, and applies it to the
   selected object(s) via `set_different_token` / `my_strdup` (honoring the
   `preserve_unchanged_attrs` / `no_change_attrs` globals the checkbuttons set).

**Consequence:** if the new form still produces the same `tctx::retval` string
and `tctx::rcode` flag, **no C code changes are required.** The form is a pure
reskin of `edit_prop` that parses `tctx::retval` into fields and reassembles it
on OK. This is the single most important architectural fact in this plan — it
makes the change low-risk and incremental.

## 3. The pieces already in place (verified)

Everything a field-based form needs already exists and is reachable from Tcl:

| need | primitive | verified result |
| --- | --- | --- |
| list a prop string's tokens (field names) | `list_tokens <prop>` | `list_tokens "name=p0 lab=PLUS"` → `name lab` |
| the declared-attribute set + defaults | `xschem getprop instance <n> cell::template` | → `name=p1 lab=xxx` (**the Cadence "all properties" source**) |
| read one token's value (quoted form) | `xschem get_tok <prop> <tok> [flags]` | flag `2` returns the re-substitutable quoted form |
| write one token back (lossless quoting) | `xschem subst_tok <prop> <tok> <val>` | used today by the "Edit Attr" combobox |
| the full current prop string | `xschem getprop instance <name>` | → `name=p0 lab=PLUS` |

The existing "Edit Attr" combobox (`xschem.tcl:7524-7567`) is a **working
reference implementation of the per-token read/write round-trip**, including the
fiddly quote-escaping dance (`regsub` escape `"`/`\`, wrap in `"`, `subst_tok`).
The new form reuses exactly that per field — *do not reinvent the quoting.*

## 4. The design

### 4.1 Field model — why it kills `penguin=shark`

The form shows **one row per property**: a fixed **label = the token name** and an
**entry/value widget**. The user edits *values only*; token names are labels, not
text the user types. Malformed `token=value` soup becomes structurally
impossible. Adding a genuinely new property is a separate, explicit, *validated*
affordance (§4.5), not free text.

```
 name   [ E1                    ]
 TABLE  [ 1.4 0.0 1.6 4.0       ]   ← quotes handled by the round-trip, hidden from the user
 lab    [ xxx                   ]   ← from the template, shown even though unset on this instance
 ...
 [+ add property]   [Raw view]            [ OK ]  [ Cancel ]
```

### 4.2 Where the field list comes from

Union, in this order, deduped:
1. **Symbol template tokens** (`list_tokens [xschem getprop instance <n>
   cell::template]`) — the *declared* attributes, so the form shows every field
   the symbol defines even if the instance hasn't set it (Cadence behavior). The
   template value is the **default/hint**.
2. **Instance prop tokens** (`list_tokens $tctx::retval`) — any extra attributes
   actually set on this instance beyond the template.

Decision to ratify (§7.B): for a declared-but-unset attr, show the template
default, or show empty with the default as a greyed placeholder?

### 4.3 Reassembly on OK (the correctness core)

On OK, rebuild the prop string from the fields. Two viable strategies:

- **(a) subst into the original** — start from `tctx::retval_orig`, and for each
  field the user *changed*, `subst_tok` the new value in. Preserves untouched
  tokens byte-for-byte (incl. ordering/quoting) → safest for round-trip fidelity.
- **(b) assemble fresh** — build `tok=val tok=val …` from all fields. Cleaner, but
  risks reordering/reformatting tokens the user didn't touch.

**Recommend (a)** — it makes "open the form and click OK with no edits" a
guaranteed no-op, which is the cardinal invariant (§6). Track a **dirty flag per
field** so only edited tokens are substituted (this also pre-wires the
later multi-object "apply only changed fields" feature, §8).

### 4.4 Long / multi-line values (the main UX wrinkle)

Some values are long or multi-line (`value`, `spice`, `verilog`, `model`,
`TABLE`, spice device cards). A single-line `entry` is wrong for those. Plan:

- **Heuristic:** if a value contains a newline or exceeds N chars, render a small
  multi-line `text` widget (or an `entry` plus a `…` button that opens a focused
  sub-editor for that one field).
- **Keep a "Raw view" toggle** that swaps the whole form back to today's single
  text box. This is the escape hatch for unknown/edge structures and a de-risking
  fallback — ship it from day one.

### 4.5 Adding / deleting a property

- **[+ add property]** opens a row with an editable name + value; the name is
  **validated** (non-empty, no whitespace, matches `^[A-Za-z_][A-Za-z0-9_]*$`)
  before it is accepted — this is the *only* place a new token name is typed, and
  it is guarded, so the junk-input problem stays solved.
- Per-row **delete** (×) removes a token (reuses the empty-value / token-removal
  path).

### 4.6 Validation (phased)

- **v1 — structural only.** Separate fields already remove the malformed-string
  class of error; no per-value rules yet. This alone meets the stated goal.
- **v2 — per-attribute validators (future).** A small built-in map for well-known
  attrs (`dir` ∈ {in,out,inout}; booleans → checkbox; `name` non-empty;
  numeric-only where known), surfaced as a red border + blocked OK on invalid.
  Templates carry no rich type system today, so this starts as a curated map,
  optionally extended by `type=`/`format=` hints if a symbol provides them.

### 4.7 Keyboard contract (explicitly requested)

- **Enter** in any field → invoke OK. Now safe because fields are single-line
  entries (Enter is no longer needed to insert a newline, unlike the current text
  box which binds **Shift**-Enter to OK at `xschem.tcl:7516`). Multi-line value
  widgets are the exception — there, Enter inserts a newline and Ctrl-Enter / the
  OK button commits (document this).
- **Escape** any time → Cancel and discard. Drop the current conditional guard
  (`xschem.tcl:7517-7522`) that only cancels when nothing changed; make it
  unconditional, matching the request.

### 4.8 Features to preserve

The reskin must keep: the Symbol entry + Browse/Load/Del, the three checkbuttons
(their globals `no_change_attrs` / `preserve_unchanged_attrs` / `copy_cell` are
read by C — keep the widgets and variable names), and the OK/Cancel/WM-close
semantics. The "Edit Attr" combobox becomes redundant (per-field editing
supersedes single-token isolation) — remove it, or repurpose it as a "jump to
field" selector.

## 5. Scope: which dialogs

`edit_prop` (instance/symbol — the screenshot) is the target and the hardest, so
do it first. The same pattern generalizes to the dialog family (later, via a
shared `build_property_form` proc):

| proc | edits | priority |
| --- | --- | --- |
| `edit_prop` (`:7372`) | instance / symbol attributes | **v1** |
| `text_line` | graphical objects (rect/line/poly/arc/wire) props | v2 |
| `enter_text` | text object (string + size) | v2 |
| `graph_edit_properties` (`:3448`) | graph objects | v3 |
| `edit_vi_prop` / `edit_vi_netlist_prop` | external editor | leave as-is (power escape hatch) |

Factor the parse→fields→reassemble logic into reusable procs so each dialog is
thin.

## 6. The cardinal invariant & testing

**Invariant: opening the form on any object and clicking OK with no edits must
leave the property string byte-identical.** Quoting, escaping, ordering, empty
values, multi-line values, embedded `"`/`\`, and `TABLE="…"`-style space-bearing
values must all round-trip losslessly. This is the #1 risk and the #1 test.

Testing approach (Tk dialogs are awkward headless, so split the work):

- **Headless round-trip suite (the core).** Factor parsing/assembly into pure
  Tcl procs (`prop_to_fields`, `fields_to_prop`) with **no widget dependency**,
  and unit-test them: for a corpus of real prop strings (pull from
  `xschem_library/devices/*.sym` templates + instances), assert
  `fields_to_prop(prop_to_fields(p)) == p`. Hammer the hostile cases (quotes,
  escapes, multi-line, empties). This catches the quoting bugs without a display.
- **Sabotage / green-but-hollow.** Each test fails first; after GREEN, perturb the
  assembler (e.g. drop quoting) and confirm the round-trip tests redden. Assert
  *exact* strings, not "non-empty". [[green-but-hollow]]
- **GUI smoke (manual / `verify` skill).** Enter→OK, Escape→Cancel, add/delete
  property, Raw toggle, long-value widget, on a couple of real symbols.

## 7. Decisions to ratify (present, don't pick)

- **A. C changes: zero or some?** Pure-Tcl reskin (keep the `tctx::retval`/`rcode`
  contract — recommended, lowest risk) vs. a richer C-side field API
  (`xschem object_fields <handle>` returning name/value/type/default as a list of
  dicts — cleaner, composes with the stable-handles `object` API, but more work).
  Recommend Tcl-only for v1, note the C field-API as the v2 upgrade.
- **B. Unset declared attrs:** show the template default, or empty with a greyed
  default placeholder?
- **C. Reassembly strategy:** subst-into-original (recommended, lossless) vs.
  assemble-fresh.
- **D. Raw toggle:** ship the legacy text box as a switchable "Raw view"
  (recommended) or drop it entirely?
- **E. Add-property:** allow arbitrary new tokens (validated), or restrict to the
  template's declared set (stricter, more Cadence-like for fixed cells)?

## 8. Forward hook — multi-object / all-objects (the user's "later")

Bake one thing in now so the later feature is cheap: **track which fields the
user edited** (the dirty set, §4.3). The eventual "apply to all selected / all in
view" then means: for each target object, `subst_tok` only the dirty fields into
*its* prop string — which is exactly what the existing C
`preserve_unchanged_attrs` + `set_different_token` path already does. So the form
should expose "the set of changed (token,value) pairs," and the apply loop
(C or Tcl) iterates objects. Designing the form around *dirty fields* rather than
*the whole string* is the one decision that makes §8 nearly free later.

## 9. Effort

- **v1 (`edit_prop` reskin, Tcl-only, Raw fallback, Enter/Escape, headless
  round-trip suite):** ~2–3 days, dominated by the quoting round-trip and the
  long-value UX.
- **v2 (shared proc + `text_line`/`enter_text`, per-attr validators):** ~2 days.
- **multi-object apply (§8):** ~1–2 days once the dirty-field model exists.

Recommend shipping **v1 on `edit_prop`** first behind a "Raw view" fallback, get
it in front of the user, then generalize.

## 10. Open questions for the user

1. Should declared-but-unset symbol attributes appear in the form by default
   (Cadence does), or only attributes already set on the instance?
2. For fixed library cells, do you want to *forbid* adding undeclared properties
   (strict template), or keep the freedom to add any (validated) token?
3. Is a "Raw view" toggle (the old text box) acceptable as a permanent escape
   hatch, or do you want the structured form to be the only path?
4. How important is multi-line value editing in v1 (e.g. for `value`/spice cards),
   vs. deferring rich multi-line to v2?

---

*Grounding: `edit_prop` `src/xschem.tcl:7372-7600`; the C contract
`editprop.c` (`edit_property`/`update_symbol`, `tctx::retval`/`tctx::rcode`,
`set_different_token`, `preserve_unchanged_attrs`); token primitives
`scheduler.c` `get_tok` (`:2291`), `subst_tok` (`:6987`), `list_tokens`
(`:3259`), `getprop ... cell::template` (`:2105`); template store
`xctx->sym[].templ` (`token.c`). Runtime checks (template + list_tokens +
get_tok) verified via a scratch script on `mos_power_ampli.sch`. Companion:
`object_query_api.md` (the handle/`object` API a v2 C field-API would compose
with).*
