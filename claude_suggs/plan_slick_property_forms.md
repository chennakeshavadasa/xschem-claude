# Plan — slick per-property edit forms (Cadence-style)

*Goal:* replace XSCHEM's raw single-text-box property editor (the "Edit
Properties" dialog) with a structured Tk form that gives **one validated entry
field per property**, eliminating malformed `token=value` input, with **Enter =
OK** (from any field) and **Escape = Cancel** (any time, discard changes).

Status: **PLAN ONLY — no code yet.** Branch `slick-property-forms`. Analysis
below is run-verified against the build on this branch.

> **Decisions ratified by the user (2026-06-13):**
> 1. **Cadence-style** — the form shows *all declared* symbol attributes (from the
>    template), not just ones already set on the instance.
> 2. **Strict** — the user may not add undeclared properties through the form; the
>    declared template set is the field list (with one safeguard for pre-existing
>    undeclared tokens, §4.5).
> 3. **Structured form is the ONLY path** — no "Raw view" text-box fallback. This
>    raises the stakes on lossless round-trip (§6): the form must faithfully
>    represent and preserve *every* property string it can be opened on.
> 4. **Multi-line supported where needed** — fields that hold multi-line values get
>    a multi-line widget; see the expanded §4.4.

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

**Multi-line values are first-class in the data model** (verified): an attribute
value may contain literal newlines, stored inside the quotes. From
`xschem_library/devices/code.sym`:

```
format="
@value
"
```

i.e. the `format` token's value is `\n@value\n`. The form must round-trip such
values losslessly (§4.4, §6); `get_tok`/`subst_tok` already carry the newlines
and quoting, so the work is on the widget side, not the data side.

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
 lab    [ xxx (default)         ]   ← declared in template, unset → greyed default placeholder
 value  +-------------------------+ ⤢ ← known multi-line attr → text widget
        | .model mymod ...        |    (Enter = newline, Ctrl+Enter = OK)
        +-------------------------+
 ...
                                        [ OK ]  [ Cancel ]
 (strict: declared fields only; no free-form add, no Raw view — decisions 2 & 3)
```

### 4.2 Where the field list comes from (Cadence-style, strict)

The field list is driven by the **symbol template** — the declared attributes —
so the form shows every field the symbol defines, set or not (decision 1):

1. **Declared fields** = `list_tokens [xschem getprop instance <n>
   cell::template]`. Each declared token is a row. Its value is the **instance's**
   value if set, else the **template default** (shown as a greyed placeholder so
   the user sees the default but it isn't written unless edited — §7.B answer).
2. **Pre-existing undeclared tokens** = instance tokens not in the template. Under
   **strict** mode the form does **not** let the user *add* new undeclared tokens
   (§4.5), but it must not silently drop ones that already exist (there is no Raw
   fallback to recover them — decision 3). So show them in a clearly-labelled
   **"Extra (undeclared)"** section: editable and deletable, but no "add" there.

This keeps the form Cadence-strict for new input while guaranteeing **no existing
data is hidden or lost** — essential given the form is the only path.

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

### 4.4 Long / multi-line values

Multi-line is fully supported (decision 4); it is a widget concern, not a data
concern (the value already round-trips, §3). Four parts:

**a. Widget choice.** Tk `entry` is single-line only, so a multi-line field uses a
small `text` widget (a few rows, own scrollbar, resizable); short fields stay
`entry`.

**b. Deciding a field is multi-line** — combine three signals:
- **Known multi-line attributes** — `value`, `format`, `*_format`
  (spice/spectre/verilog/vhdl/tedax), `template`, `model`, `descr`, etc. These get
  a multi-line widget *even when currently empty/short* (a fresh `code` instance's
  `value` still wants a big box). This is the declarative, Cadence-aligned signal.
- **Heuristic** — current value contains `\n` or exceeds N chars → multi-line.
- **Manual expand** — a per-field ⤢ toggle to grow any field, covering misses.

**c. The Enter-key consequence (the one unavoidable trade-off with "Enter = OK").**
In a `text` widget Enter *must* insert a newline. So:
- single-line `entry` field: **Enter → OK**;
- multi-line `text` field: **Enter → newline**, **Ctrl+Enter (or Shift+Enter) →
  OK**, plus the always-available OK button.
This is the standard editor convention; show a one-line hint by multi-line fields.
**Tab** has the same issue (a `text` widget eats Tab) — rebind Tab to focus-next
so it still walks fields.

**d. Lossless round-trip of newlines + quoting** (§6) — the value `\n@value\n` must
survive open→OK byte-for-byte. Reuse `get_tok`/`subst_tok` (which already carry
newlines) and the subst-into-original strategy (§4.3); the round-trip test corpus
must include multi-line symbols (`code.sym`, `launcher.sym`, the `ngspice_*`
family). With no Raw fallback (decision 3), this is non-negotiable.

### 4.5 Adding / deleting a property (strict)

Under **strict** mode (decision 2) there is **no general "add arbitrary property"**
affordance — the declared template set *is* the editable field list, which is the
Cadence-for-fixed-cells behavior and keeps junk input impossible by construction
(the user never types a token name for a declared field; they fill values).

- **Declared fields:** value-only editing; the token name is a fixed label.
- **Pre-existing undeclared tokens** (the "Extra" section, §4.2): editable and
  **deletable** (per-row ×, reusing the token-removal path), so the user can clean
  them up — but none can be *added*.
- **Future / non-strict symbols:** if some symbols later want user-extensible
  attributes, a guarded **[+ add property]** (name validated
  `^[A-Za-z_][A-Za-z0-9_]*$`, non-empty, no whitespace) is the controlled opening
  — kept out of v1 per the strict decision.

### 4.6 Validation (phased)

- **v1 — structural only.** Separate fields already remove the malformed-string
  class of error; no per-value rules yet. This alone meets the stated goal.
- **v2 — per-attribute validators (future).** A small built-in map for well-known
  attrs (`dir` ∈ {in,out,inout}; booleans → checkbox; `name` non-empty;
  numeric-only where known), surfaced as a red border + blocked OK on invalid.
  Templates carry no rich type system today, so this starts as a curated map,
  optionally extended by `type=`/`format=` hints if a symbol provides them.

### 4.7 Keyboard contract (explicitly requested)

- **Enter** in a single-line field → invoke OK (safe: an `entry` never needs Enter
  for a newline, unlike the current text box which binds **Shift**-Enter to OK at
  `xschem.tcl:7516`). **Multi-line fields are the documented exception** (§4.4c):
  Enter inserts a newline, **Ctrl/Shift-Enter** commits, the OK button always
  commits.
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
values must all round-trip losslessly. This is the #1 risk and the #1 test —
**and decision 3 (no Raw fallback) makes it a hard release gate**: since the form
is the only path, a value it can't faithfully represent is a value the user can no
longer edit safely. **Gate: the round-trip suite must be green across the *entire*
shipped symbol library** (`xschem_library/devices/*.sym` templates + a sweep of
example schematics) before the structured form replaces the text box.

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

## 7. Decisions

- **A. C changes: zero or some?** *Open (recommend Tcl-only for v1).* Pure-Tcl
  reskin keeps the `tctx::retval`/`rcode` contract (lowest risk). A richer C-side
  field API (`xschem object_fields <handle>` → name/value/type/default dicts,
  composing with the stable-handles `object` API) is the v2 upgrade.
- **B. Unset declared attrs:** **RATIFIED (decision 1)** — shown, with the template
  default as a greyed placeholder that is *not written* unless the user edits it.
- **C. Reassembly strategy:** *recommend subst-into-original* (lossless; the §6
  gate + decision 3 make fresh-assembly too risky). Confirm.
- **D. Raw toggle:** **RATIFIED (decision 3)** — no Raw fallback; structured form is
  the only path. (Raises §6 to a release gate.)
- **E. Add-property:** **RATIFIED (decision 2)** — strict; no arbitrary new tokens
  in v1. Pre-existing undeclared tokens are shown/editable/deletable but not
  addable (§4.5).

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

*(The four scoping questions are now resolved — see the ratified-decisions box at
the top. Remaining smaller calls:)*

1. **C7.A** — v1 pure-Tcl reskin (recommended) vs. building the C `object_fields`
   API now? (Recommend Tcl-only first; it fully meets the goal.)
2. **C7.C** — confirm subst-into-original reassembly (recommended for losslessness).
3. **Multi-line widget feel** — fixed N-row boxes with scrollbars, or auto-growing
   up to a cap? And is Ctrl+Enter the preferred "commit from a multi-line field"
   chord (vs. Shift+Enter)?
4. **"Extra (undeclared)" section** — for the rare instance that already carries a
   non-template token, is show-and-allow-delete the behavior you want (recommended,
   prevents silent data loss), or should the form refuse such objects?

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
