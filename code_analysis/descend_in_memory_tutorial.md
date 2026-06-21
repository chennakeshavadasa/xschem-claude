# Tutorial: from a save-prompt bug to an in-memory hierarchy

A real-world walkthrough of how a one-line bug report ("why does descending into
a cell ask me to save?") turned into a small architectural feature in XSCHEM —
preserving the parent schematic in memory so descending never has to save or risk
losing edits.

This is a **living document**: it grows one part at a time as the work proceeds.
Every concept is paired with the concrete decision, command, or code from this
exact effort, so you can see the reasoning *in situ* rather than in the abstract.

Companion docs:
- Design/plan: `specs/descend_hierarchy_in_memory.md`
- Progress + resume state: `specs/descend_handoff.md`

Covered so far: **Parts 1–4 (Steps 0–6).**

---

## Part 1 — Diagnosis: a report is a symptom, not a cause

### Lesson 1 — Trace the mechanism; don't guess from the symptom

The report: *"Right-click → Descend on a non-primitive cell pops a 'save?' dialog.
Nothing was modified."*

The tempting guess is "descend has a save step." The truth was one layer deeper.
`descend_schematic()` (`src/actions.c`) only saves **if the schematic is already
flagged modified**:

```c
if(xctx->modified) {
  ret = save(1, 0);          /* -> ask_save dialog */
  ...
}
```

So the real questions became: (a) why is `xctx->modified` set on a file the user
never touched, and (b) why only for non-primitive cells? Question (b) had a tidy
answer — a *type gate* runs **before** the modified check:

```c
if((sym)->type && strcmp(type,"subcircuit") && strcmp(type,"primitive"))
  return 0;                 /* leaf devices bail out here, never reach the save */
if(xctx->modified) { ... }  /* only descendable cells get this far */
```

`res`/`capa` are `type=resistor`/`capacitor` → they return before the check, so
they never prompt. Subcircuits fall through and do.

**Takeaway:** the first job is to find the *actual* line that produces the
behavior. "Descend prompts" was a symptom of "modified was already set" — a
completely different bug than it appeared.

### Lesson 2 — Reproduce first, and reproduce in the user's mode

Before changing anything, reproduce headlessly so you can iterate fast:

```sh
src/xschem --no_x -q --script repro.tcl     # prints `xschem get modified`
```

Plain load → `modified=0`. No repro! The user runs a **cadence-style** config.
Re-running with their rc (`src/cadence_style_rc`) → `modified=1` right after
`load_new_window`. The bug only exists in a particular mode.

**Takeaway:** a non-reproduction is information. "Works for me" usually means
"my configuration differs from theirs." Match the environment before concluding.

### Lesson 3 — When you can't see the cause, instrument it

`modified` was set *somewhere* during load. Rather than read every candidate, we
made the program tell us. A temporary backtrace at the moment the flag flips:

```c
int set_modify(int mod) {
  if(mod == 1 && xctx->modified == 0) {       /* TEMP: catch the 0->1 transition */
    void *bt[24]; int n = backtrace(bt, 24);
    backtrace_symbols_fd(bt, n, 2);
  }
  ...
}
```

The frames came back as addresses; `addr2line -f -e src/xschem <addr>` resolved
them to:

```
set_modify  <-  trim_wires  <-  load_schematic  <-  create_new_tab ...
```

**Takeaway:** a five-line instrument that prints a backtrace beats an afternoon of
reading. Resolve static-function addresses with `addr2line`. Then *remove* the
instrument — it was scaffolding, not a fix.

### Lesson 4 — Behavior emerges from interacting features

The backtrace named `trim_wires`, but *why* did it run on load, and only in
cadence mode? Following the chain:

```
cadence_compat=1
  └─ a Tcl trace sets autotrim_wires=1            (xschem.tcl)
       └─ load_schematic() runs trim_wires()       (save.c, gated on autotrim_wires)
            └─ it compacts redundant wires -> set_modify(1)   (check.c)
```

No single component is "wrong." A convenience (auto-join wires) + a mode that
enables it + a file with trimmable wires = a freshly-opened file marked dirty.

**Takeaway:** in a system with many toggles, bugs live in the *interactions*. Map
the chain end to end; the fix usually belongs at one specific link, not the ends.

**The Part-1 fix** (`save.c`): a load-time normalization must not make an untouched
file look edited. Snapshot the flag around the trim and restore it:

```c
int mod_before_norm = xctx->modified;
check_collapsing_objects();
if(reset_undo && tclgetboolvar("autotrim_wires")) trim_wires();
if(reset_undo && !mod_before_norm && xctx->modified) set_modify(0);
```

Genuine edits still set `modified`; only the self-inflicted load-time change is
undone.

---

## Part 2 — The architecture, and a deeper question

### Lesson 5 — Know your data model before redesigning behavior

The user made a design argument: *descending isn't discarding — you'll return, so
why prompt at all? Prompt on close or when going back up, where edits are actually
at risk.* Correct in principle — but is it how the code works? Read the model:

- **`xctx`** is one global context with **one** set of object arrays
  (`wire`, `inst`, `sym`, ...). Only the *current* hierarchy level is in memory.
- **Descend** (`actions.c`): `load_schematic(child)` loads the child **over** the
  parent's arrays. The parent's geometry is gone from memory; only small per-level
  metadata (`zoom_array[]`, `sch_path[]`, `hier_attr[]`, ...) is stacked.
- **go_back** (`actions.c`): `load_schematic(parent)` **re-reads the parent from
  disk**.

So in the *current* code, descending **does** discard the in-memory parent, and
returning rebuilds it from the file. The save-prompt was the only thing making
unsaved parent edits survive a round trip.

**Takeaway:** validate the user's mental model against the implementation. Here
the ideal behavior was right but *not yet true* — which reframed the task from
"remove a prompt" to "make descend non-destructive."

### Lesson 6 — Prove the data-loss claim; don't assert it

Before removing the prompt, we proved what removing it (naively) would cost:

| step | parent wires |
|------|------|
| load | 1 |
| add a wire (now modified) | 2 |
| descend, decline save | — |
| **go_back** | **1**  ← the added wire is gone |

A scripted, repeatable experiment turned "I think this loses data" into "here is
the data loss." That evidence justified the bigger fix instead of a one-liner.

**Takeaway:** when a change's safety is in question, build the smallest experiment
that demonstrates the failure. Evidence beats argument and prevents shipping a
plausible-but-wrong shortcut.

### Lesson 7 — Separate the symptom fix from the design change

Two independent problems were now clear:
1. **Spurious `modified` on load** — a real bug, fixed in isolation (Part 1).
2. **Descend is destructive** — an architectural gap requiring real work (Part 2).

We shipped (1) immediately (it solves the actual report) and planned (2) behind a
written spec. Crucially, we *kept the save-prompt* until the redesign made it
safe to remove — never trade a safe annoyance for silent data loss.

**Takeaway:** unbundle "fix the reported bug" from "fix the underlying design."
Ship the safe, small fix now; gate the risky redesign behind a plan and tests.

---

## Part 3 — Building the feature, test-first

### Lesson 8 — RED-first: write the test that *defines* done, and watch it fail

The very first implementation step was a **failing** test
(`tests/headless/test_descend_preserve.tcl`) encoding the goal:

- **S1**: edit the parent, descend (declining the save), `go_back` → the edit must
  still be there, and `modified` must still be 1.
- **S2**: descend must not pop the prompt at all.

Run on the unchanged code, it failed in exactly the right way (the four *setup*
checks passed; the two *acceptance* checks failed). A test that fails for the
expected reason is a specification you can execute.

Two practical points:
- **Self-contained fixture.** Rather than depend on a fragile library schematic,
  we generated a tiny parent/child pair under
  `tests/headless/fixtures/descend/` (a `type=subcircuit` symbol whose `<name>.sch`
  exists, so descend resolves it). Tests shouldn't rely on unrelated files.
- **Make the test observe the seam.** The test stubs `ask_save` to *return "no"
  and count calls* — so it both prevents the dialog from blocking headless and
  can assert (later) that the prompt is gone.

**Takeaway:** a RED test first makes "done" objective and stops scope creep. If it
doesn't fail — or fails for the wrong reason — fix the test before the code.

### Lesson 9 — Reuse battle-tested machinery instead of inventing it

The feature needs to snapshot/restore an entire schematic in memory. XSCHEM
already does exactly that, correctly, for **undo**: `mem_push_undo` /
`mem_pop_undo` deep-copy every object type (wires, instances, symbols via
`copy_symbol`, texts, per-layer rects/lines/polys/arcs, all `prop_ptr` strings)
into an `Undo_slot`.

So we didn't write a new serializer. We **extracted** the existing bodies into
reusable, slot-agnostic functions:

```c
void mem_serialize_slot(Undo_slot *s);              /* current drawing  -> slot */
void mem_restore_slot(Undo_slot *s, int set_modify);/* slot -> current drawing  */
```

and generalized the helpers they call (`free_undo_*`) from `(int slot)` to
`(Undo_slot *)` so they work on *any* slot, not just the undo ring `uslot[]`.
`mem_push_undo`/`mem_pop_undo` kept their stack bookkeeping and now just delegate.

An earlier idea — swap the whole `Xschem_ctx` pointer like the tab system does —
was rejected: it collides with the `currsch`-indexed metadata arrays and the
cross-level highlight code, which assume a single context. Reusing the undo
serializer keeps one context and touches far less.

**Takeaway:** the cheapest correct code is code that already exists and is already
tested. Look for the operation you need *already happening* elsewhere, and factor
it out rather than reimplementing.

### Lesson 10 — Refactor behind a safety net, in behavior-neutral steps

Steps 2–3 changed *no behavior* — they only moved code. The guard was the existing
undo test (`wireedit_14`) plus the full suites, run after each extraction:

```sh
cd src && make xschem
bash tests/headless/wireedit/run_wireedit.sh      # 18/18
cd tests && tclsh run_regression.tcl              # no FAIL/GOLD/FATAL
```

Because the refactor was mechanical and the tests were green before and after, a
later real bug can't hide in "the refactor."

**Takeaway:** make refactors provably behavior-neutral and commit them separately
from behavior changes. When something breaks later, `git bisect` lands on the
commit that *meant* to change behavior.

### Lesson 11 — C memory lifecycle: lazy alloc, teardown, and where *not* to free

The per-level store is `Undo_slot hier_slot[CADMAXHIER]` plus
`hier_slot_valid[]` / `hier_slot_modified[]`, all zeroed because `xctx` is
`my_calloc`'d. Each slot's inner arrays are allocated **lazily** at first use
(`mem_init_hier_slot`) and freed in two places:

- **per level** on `go_back` (consume the snapshot), and
- **all** at context teardown (`free_xschem_data`).

The subtle part is **where not to free**: the design note literally says "free in
`clear_drawing`" — which is *wrong*. Descend's child-load calls `clear_drawing()`,
so freeing snapshots there would wipe the parent snapshot you just took. Lifecycle
bugs are usually about the *one* call site you didn't expect to run.

**Takeaway:** for every allocation, name its free sites *and* the call sites that
must **not** free it. In C the second list is where the bugs hide.

### Lesson 12 — Compose with existing code instead of replacing it

`go_back` already does a lot besides loading geometry: file identity, window
title, netlist directory, read-only state. Rather than reproduce all that, we let
`load_schematic` run as before and then **overlay** the preserved geometry:

```c
load_schematic(1, filename, set_title, 1);          /* identity/title/etc. as today */
if(snapshot exists && keep_in_memory) {
  mem_restore_hier(currsch);                         /* swap in preserved drawing */
  set_modify(1);
}
```

It costs one disk read we then partly discard — but it reuses every bookkeeping
detail `load_schematic` already gets right. Optimize later; be correct now.

**Takeaway:** "load then overlay" is often safer than "replace." Touch the minimum
and lean on code that already handles the long tail of details.

### Lesson 13 — Keep the old path one boolean away (a bisect switch)

The new behavior is gated by a Tcl variable, `descend_keep_in_memory` (default 1).
Setting it to 0 restores the exact legacy disk-reload path. That's not for end
users — it's so we can A/B the two implementations in one binary while validating.

**Takeaway:** when you replace a code path, leave a switch to the old one during
bring-up. It turns "is this my change?" from a rebuild into a variable assignment.

---

## Part 4 — Fidelity: "it works" is not "it's faithful"

### Lesson 14 — Test equivalence, not just success

S1 proved edits *survive*. It did not prove the round trip is *exact*. Step 6 added
`test_descend_fidelity.tcl`, which:

1. loads the parent fresh and `saveas` to a file,
2. loads it, descends, `go_back`s, and `saveas` to a second file,
3. asserts the two `.sch` files are **byte-identical** (every object type and
   property), plus checks zoom restoration and a clean `modified` flag.

Comparing the *saved files* is a strong, cheap equivalence check: the file format
already serializes everything, so you don't need a per-field reader.

**Takeaway:** "the feature works" and "the result is identical to the baseline"
are different claims. A round-trip that saves and diffs catches drift that a
behavioral test sails past.

### Lesson 15 — The bug the fidelity test caught: cached/derived state leaks

The diff was not empty:

```
< N 0 -60 0 0 {}
---
> N 0 -60 0 0 {lab=INA}
```

Two unlabeled wires came back with a derived net name (`lab=INA`) **baked into
their saved props**. Bisecting *where*: not `go_back`, not the snapshot timing —
it was as early as **selecting the instance to descend into**. Net resolution
(`prepare_netlist_structs`) writes derived names into live wire props; the legacy
disk reload silently *laundered* that, while our faithful snapshot preserved it.

Method that found it: A/B the three save outputs — `fresh`, `disk-reload round
trip` (flag off), `memory round trip` (flag on):

```
DISK vs FRESH: identical
MEM  vs FRESH: DIFFER     <- the regression is ours, and only in the memory path
```

**Takeaway:** an in-memory snapshot captures *cached/derived* state too, not just
the authored model. When "faithful to memory" diverges from "faithful to disk,"
decide which one you actually want — and prove which path introduced the gap.

### Lesson 16 — The fix that is also a better design

Why did we snapshot at all? To preserve **unsaved edits**. If the parent was
*not* modified, there are no edits to preserve and the disk file is authoritative
*and* clean. So `go_back` overlays the snapshot **only when the parent was
modified**:

```c
if(!from_embedded_sym && xctx->hier_slot_modified[currsch]) {
  mem_restore_hier(currsch);   /* dirty parent: in-memory truth wins  */
  set_modify(1);
} else {
  mem_free_hier_slot(currsch); /* clean parent: trust the disk reload */
}
```

A clean parent now returns byte-identical to disk (fidelity test green); a dirty
parent keeps every edit (S1 green). The baking is confined to files that are
already dirty and about to be saved anyway. One predicate fixed the fidelity bug
*and* narrowed the feature to exactly the case that needs it.

**Takeaway:** the best fix often shrinks the feature. Ask "when is this machinery
actually needed?" — guarding on that condition frequently removes the bug for free.

---

## Appendix — the toolbox used here

- **Headless repro:** `src/xschem --no_x|--nogui -q --nolog --script f.tcl`
- **Inspect state from Tcl:** `xschem get modified|wires|instances|xorigin|zoom`,
  `xschem getprop wire i lab` (beware: returns *derived* values, not raw props).
- **Backtrace an event:** `backtrace()/backtrace_symbols_fd()` +
  `addr2line -f -e src/xschem <addr>` for static symbols.
- **Equivalence by file:** `xschem saveas f.sch schematic` then `diff` (strip the
  volatile version header line).
- **A/B a code path:** a default-on config flag (`descend_keep_in_memory`).
- **Guard rails:** `wireedit/run_wireedit.sh`, `tests/run_regression.tcl`, run
  after every step; commit refactors and behavior changes separately.

*Next parts will cover Step 7 (removing the prompt safely), embedded symbols,
the tab/context interaction, and leak-hunting — added as those steps land.*
