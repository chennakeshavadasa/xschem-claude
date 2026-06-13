# FAQ

Running Q&A spanning the connected threads of XSCHEM internals work done in
this repo: the input action-registry / binding-table work (branch
`feature/action-registry`), the action-logging / CIW work (branch
`feature/action-logging`), and the scriptability / stable-object-handles work
(branch `feature/stable-object-handles`) — plus general questions about the
XSCHEM data model that come up along the way. Each entry records the **project
state when it was asked** (branch + HEAD commit + phase), because answers are
often tied to how much of a refactor had landed at that moment — a later phase
may make an old "no" a "yes."

Newest entries on top.

---

## Q10. Can you open a schematic or symbol in *read-only* mode?

- **Asked:** 2026-06-12
- **Project state:** branch `feature/stable-object-handles` @ `10c3f2f8`
  (step 1 of stable handles complete; the wire-handle manual just landed).

**No — XSCHEM has no read-only / view-only open mode today.** Every file you
open is loaded into a fully editable in-memory context. There is no
application-level lock, no flag, and no startup option that makes a loaded
schematic non-editable. Specifically, the searches come back empty on all of
these:

- **No `xschem load` flag for it.** The `load` command
  (`scheduler.c`, the `xschem_cmds_l` group) accepts
  `-nosymbols | -gui | -noundoreset | -nofullzoom | -nodraw | -keep_symbols |
  -lastclosed | -lastopened` — controlling *symbol loading, undo, zoom and
  drawing*, none of them editability. There is no `-readonly`, `-view`, or
  `-noedit`.
- **No command-line flag.** The startup option parser (`options.c`) has
  `-x/--no_x` (headless), `-b/--detach`, output/netlist selectors, etc., but
  nothing like `--readonly` or `--view`. (Note `-r` is already taken — it
  means `--no_readline`, not read-only.)
- **No write-permission awareness at open time.** XSCHEM does not `access(…,
  W_OK)` a file when loading it and does not warn that a file is unwritable.
  The permission check happens only at *save*: `save_schematic()`
  (`save.c:~3470`) just does `fopen(schname, "w")` and, if that fails, pops
  `alert_ {file opening for write failed!}`. So you discover a file is
  read-only on the filesystem only when you try to save it.
- **The `modified` flag is not a lock.** `xctx->modified` (set via
  `set_modify()`) only drives the "save your changes?" prompt on close/reload;
  it never prevents an edit.

**The closest things that *do* exist** (and how you might lean on them):

1. **Per-element `lock` attribute.** Any object can carry `lock=true` in its
   property string; `select.c` (the `select_*` functions, ~lines 896–1226 for
   wire / inst / text / rect / poly / line) refuses to select a locked object
   for editing unless you override with Shift-click. This is *per-object, not
   per-file*, it's bypassable, and it doesn't stop programmatic edits — but it
   is the only built-in "don't touch this" mechanism. A script could stamp
   `lock=true` on everything to approximate a soft read-only.
2. **Filesystem permissions.** `chmod -w file.sch` genuinely protects the file
   on disk — XSCHEM will let you open and edit the in-memory copy, but the
   eventual save fails loudly. Read-only-on-disk plus "don't save" is the
   honest current workaround for "I just want to look."
3. **Headless inspection.** For pure querying with zero risk of mutation,
   `xschem -x -q --script <file>` (or `--pipe`) loads the file and lets a
   script read it via the `xschem` query commands without ever opening an
   editable window.

If a real read-only mode were wanted, the natural shape — given the
stable-handles direction — would be a context-level `read_only` flag checked at
the mutation funnel (the same chokepoint the handle work is building), plus an
`access(W_OK)` probe at load that sets it automatically for unwritable files.
That is not implemented; it is noted here as the obvious place it would go.

---

## Q9. What support is there for multiple open schematics/symbols — windows and tabs?

- **Asked:** 2026-06-12
- **Project state:** branch `feature/stable-object-handles` @ `10c3f2f8`.

**Good support — XSCHEM can hold many schematics/symbols open at once, in
either tabs or separate windows, each with its own fully independent state.**
The key facts:

**Two interchangeable modes, one switch.** The Tcl boolean
`tabbed_interface` (`xschem.tcl`, `set_ne tabbed_interface 1` — **default on**)
chooses between:
- **Tabbed** — all schematics share one top-level X11 window, switchable via a
  tab bar (`create_new_tab` / `switch_tab` / `destroy_tab` in `xinit.c`);
- **Windowed** — each schematic gets its own top-level window
  (`create_new_window` / `switch_window` / `destroy_window`).
`new_schematic()` (`xinit.c`) reads the flag at runtime and dispatches to the
right pair, so the *same commands* drive both.

**Each open schematic is a separate `Xschem_ctx`.** This is the important part
for scripting: every tab/window owns a complete, independent copy of the editor
state — its own `wire[]`, `inst[]`, selection, undo stack, zoom, hierarchy
stack, *and (per the stable-handles work) its own wire-id counter.* They live
in a `save_xctx[MAX_NEW_WINDOWS]` array (`xinit.c`); the global `xctx` always
points at the active one, and switching tabs/windows just repoints it. A wire
id is unique **within one context**, not across contexts — two tabs can both
have a wire with id 5.

**The Tcl commands a script uses** (all verified against `scheduler.c`):

| Command | What it does |
| --- | --- |
| `xschem new_schematic create <win_path> [file]` | open a new tab/window (empty, or with `file` loaded). `win_path` is `{}` for auto, or e.g. `.x1.drw` |
| `xschem new_schematic switch <win_path>` | make that tab/window active (`win_path` may be `previous` or a schematic name) |
| `xschem new_schematic destroy <win_path>` | close one tab/window |
| `xschem new_schematic destroy_all [force]` | close all extra tabs/windows |
| `xschem tab_list` | list every open tab/window as `{win_path} {filename}` rows |
| `xschem get current_win_path` | path of the active tab/window (`.drw` for the main one, `.x1.drw`, `.x2.drw`, …) |
| `xschem get ntabs` | number of *extra* tabs (0 = only the main one) |
| `xschem get schname` / `sch_path` / `currsch` | name / hier-path / hierarchy level of the active context |

**The hard limit is `MAX_NEW_WINDOWS = 20`** (`xschem.h`) — try to open a 21st
and `create_new_window` / `create_new_tab` refuse with "no more free slots."

**Don't confuse "open windows" with "hierarchy depth."** These are two
different stacks:
- *Descending* into a sub-circuit (double-click an instance) pushes onto the
  **hierarchy stack** `sch[CADMAXHIER]` (`CADMAXHIER = 40`) **inside the same
  context and the same window** — `currsch` counts the depth (0 at top). You're
  still in one `xctx`, looking deeper into one design.
- *Opening* a file in a new tab/window allocates a **brand-new `xctx`** with its
  own `currsch = 0`. A genuinely separate design, separate undo, separate
  everything.

So "20" bounds how many separate designs you can have open; "40" bounds how
deep you can drill into any one of them.

---

## Q8. Besides wires, what object types does XSCHEM have?

- **Asked:** 2026-06-12
- **Project state:** branch `feature/stable-object-handles` @ `10c3f2f8`.
  The stable-handle work so far covers **wires only**; this question is about
  what the other types are, since they are the roadmap for the rest of the
  identity work.

**XSCHEM schematics/symbols are built from seven drawable object types, plus
the symbol *definition* that instances point at.** They are all defined
together near the top of `xschem.h` and each lives in its own array on `xctx`.
The type constants (`xschem.h:265–271`) double as a bitmask:

| Const (value) | Struct | `xctx` array | What it is |
| --- | --- | --- | --- |
| `WIRE` (1) | `xWire` | `wire[]` | a net segment (the type the handle work started on) |
| `xRECT` (2) | `xRect` | `rect[layer][]` | rectangle / box — also pins, graphs, embedded images (by layer) |
| `LINE` (4) | `xLine` | `line[layer][]` | a graphical line (by layer) |
| `ELEMENT` (8) | `xInstance` | `inst[]` | a placed **component instance** (a reference to a symbol) |
| `xTEXT` (16) | `xText` | `text[]` | a text label / annotation |
| `POLYGON` (32) | `xPoly` | `poly[layer][]` | a polyline / polygon (by layer) |
| `ARC` (64) | `xArc` | `arc[layer][]` | a circular arc or (via attrs) circle/ellipse (by layer) |

And separately:

- **`xSymbol`** (`sym[]`) — a loaded **symbol definition** (the master). It is
  not a placed object you draw; it is the template an `xInstance` references.
  Editing a `.sym` file edits one of these; placing it in a schematic creates
  an `xInstance` (`ELEMENT`) that points at it.

**Two structural facts a script author should know**, because they shape how
each type is addressed and how much identity work each will need:

1. **Three types are flat arrays; four are per-layer.** `wire`, `text` and
   `inst` are single arrays indexed by one number — hence `xschem select wire
   5`, one index. But `rect`, `line`, `poly` and `arc` are arrays *per drawing
   layer* (`xRect **rect;` = one array per `cadlayers`) — so they are addressed
   by **(layer, index)**: `xschem select rect <color> <n>`. That extra
   coordinate is why their commands look different from wires'.
2. **The scatter the identity work has to tame differs by type.** Instances are
   the planned next target precisely because they have the worst remaining
   lifecycle scatter (`xctx->instances++` happens in `paste.c`, `move.c`,
   `actions.c`, …), the mirror image of the wire situation that Q7 describes.
   The recipe proven on wires — census every birth/death/compaction site,
   funnel them through one family of functions, then stamp a per-context
   monotonic id at the funnel — repeats type by type. Wires were chosen first
   as the simplest specimen; instances, then the per-layer graphical types,
   follow the same playbook.

The asymmetry in *query* support across these types (instances are addressable
by name and have a rich query family; wires and the graphical types are
index-only) is catalogued in `tcl_introspection_wire.md` §3 — that, plus
identity, is what the uniform `xschem object` API is eventually meant to even
out.

---

## Q7. Toward "anything through code": what is the *first* thing to address in the code?

- **Asked:** 2026-06-12
- **Project state:** branch `feature/stable-object-handles` @ `cdf9bd9e`. The
  Tcl-introspection analysis (`tcl_introspection_wire.md`) and the C-vs-C++
  objects tutorial are committed; no design or implementation yet.
- **Context:** the end goal is SKILL-class scriptability — the user can query
  and drive everything from code. Wires were the probe specimen. What's the
  keystone change?

**Not the handles themselves — the fact that the object store has no owner.**
The expectation was that `storeobject()` (`store.c:226`) is the single factory
for wires. Grepping disproved it: `xctx->wires++` also happens at **four
sites inside `check.c`** (236, 520, 595, 685 — the connectivity checker
splits and creates wires directly), and `xctx->instances++` happens in
`paste.c`, `move.c` and `actions.c`. Deletion/compaction is similarly
scattered (`check.c:298,399`, `move.c:147`, `select.c:513`).

Every capability the goal decomposes into — stable ids, coherent caches,
undo-safe references, mutation logging, change events — needs to hook the
same three events: *object born, object died, object moved in memory*. Today
those events have half a dozen doors each. So the first move is a **pure,
behavior-identical refactor: funnel object lifecycle through one chokepoint
per event.** It is the same move that already paid off twice in this
codebase: the `scheduler()` command funnel made action-logging nearly free,
and the binding-table funnel made key remapping free. xschem funnels
*commands*; it has never funneled *state mutation* — that is the missing
half of the architecture.

Build order that falls out by dependency: (1) census + funnel (verbatim,
characterization-tested); (2) identity — stamp a monotonic id at the funnel's
birth point, maintain id→index at death/compact; (3) coherence — cache
invalidation moves into the funnel, killing the stale-query bug class
wholesale; (4) only then the user-visible uniform API (`xschem object @id`,
selection as ids). Constraints carried from day one: both undo backends must
round-trip identity (memory undo copies structs — free; disk undo
round-trips through the `.sch` format — needs a decision), and the drawing
hot path stays untouched (the funnel costs one call on human-speed mutation
only).

---

## Q6. Is it true C is a subset of C++?

- **Asked:** 2026-06-12
- **Project state:** branch `feature/stable-object-handles` @ `cdf9bd9e`,
  right after the C-vs-C++ objects tutorial (`objects_in_c_vs_cpp.md`) landed.

**Almost, but not literally — and the gap runs in three layers** (all
demonstrated live with gcc/g++ during the session):

1. **Valid C that C++ rejects:** `int *new = malloc(n)` fails twice over —
   `new` is one of ~30 extra C++ keywords, and C++ forbids the implicit
   `void *` conversion every C `malloc` call relies on. `char *s = "hello"`
   loses the `const`. Plus implicit function declarations, K&R definitions,
   tentative definitions — the C89 idioms.
2. **Valid C that C++ never adopted:** VLAs, `restrict`, flexible array
   members, `_Generic`, compound literals, full C99 designated initializers.
   Modern C is not contained in modern C++ either.
3. **The dangerous layer — compiles in both, means different things:**
   `sizeof('a')` is **4 in C** (character constants are `int`) and **1 in
   C++** (`char`); file-scope `const` linkage differs; enum conversions
   differ. No diagnostic fires.

What people correctly mean is the pragmatic version: a large common dialect
("Clean C") compiles identically under both, and xschem's C89 is a few
mechanical fixes from it. For the handles work the relevant direction is:
everything in the tutorial — factory functions, deep-copy discipline,
accessor-only mutation, generational handles — is expressible in C89. We
borrow C++'s *design ideas*, not its syntax.

---

## Q5. Is the CIW a full-fledged Tcl interpreter? And what would Ctrl-Backspace word-delete and Up-arrow history take?

- **Asked:** 2026-06-11
- **Project state:** branch `feature/action-logging` @ `094ee4a2`. Phase 0 (log
  file), the CIW (incl. the sash UX rework), Layer A slice 1 (Tcl-backed action
  logging) and `--nolog` are done; Layer A slice 2 is planned.
- **Prompted by an experiment:** the user typed `set a 10`, `set b 20`,
  `expr {$a + $b}` into the CIW and it printed `30`.

**Yes — and it's even better (or scarier) than "a" Tcl interpreter: it is THE
application's own interpreter.** When you press Return, the CIW runs your line
with `uplevel #0 $cmd` — "evaluate this at the top level of the running
program." There is no sandbox, no separate baby interpreter. That has three
consequences worth understanding:

1. **State persists between commands.** Your `set a 10` created a real global
   variable in the live program — that's exactly why `expr {$a + $b}` could see
   it two commands later. You can define procs, run loops, `source` whole
   files.
2. **You share the interpreter with the GUI itself.** Everything xschem's menus
   and dialogs can do, you can do — reconfigure widgets, call any `xschem …`
   subcommand. The flip side: a long-running loop freezes the UI until it
   finishes, because your command runs on the same thread that redraws the
   screen.
3. **Your session is being recorded.** Successful commands are appended to
   `Xschem.log` (that's the design — the file is a faithful, replayable session
   record), so `set a 10` is now part of the log. Failed commands are written
   as `# failed:` comments so replaying the file never aborts.

One honest limitation: each Return must be a **complete** command. The CIW
doesn't (yet) check `info complete`, so you can't type an open
`foreach x {1 2} {` and finish it on the next line — it errors immediately.
Type the whole construct on one line (it wraps in the entry area).

**What the two conveniences take — both are small, pure-Tcl widget bindings in
`ciw.tcl`; no C changes at all:**

*Ctrl-Backspace deletes a word.* Tk's text widget doesn't bind
`<Control-BackSpace>` by default on X11, but its index arithmetic does all the
real work — `{insert -1c wordstart}` literally means "the start of the word
just before the cursor":

```tcl
bind .ciw.c.e <Control-BackSpace> {
  .ciw.c.e delete {insert -1c wordstart} insert
  break    ;# stop the class binding from ALSO deleting one character
}
```

The only refinement worth adding is shell-like whitespace handling (skip the
spaces behind the cursor first, then eat the word) — a few more lines.

*Up/Down recalls history.* Three pieces, ~15 lines:
1. a global list that `ciw_exec` appends each executed command to;
2. `<Up>`/`<Down>` bindings that replace the entry's content with the
   previous/next list item (each ending in `break`, so the cursor-movement
   class binding doesn't fire);
3. the standard nicety: the first Up stashes whatever you'd half-typed, so
   pressing Down past the newest entry brings your draft back.

One design trade-off to know about: because the entry is now a multi-line-
capable text widget, Up natively means "move the cursor up one display line"
inside a tall, wrapped command. Binding it to history steals that. The simple
answer (what terminals and Virtuoso do) is history-always; the fancier version
triggers history only when the cursor is on the first display line.

Both features are listed in the spec's §6 "explicitly not v1" bucket — doing
them is consciously pulling future items forward, justified because they're
cheap and the CIW is a window you type into constantly.

## Q4. So far, how has this work made the code easier to read and maintain?

- **Asked:** 2026-06-08
- **Project state:** branch `feature/action-registry` @ `21ea55f4`. We are partway
  through **Phase 3c** (moving keyboard/mouse handling into the lookup table); the
  scroll wheel, the right-drag zoom gesture, the no-modifier `f` and arrow keys, and
  the graph-routing of six more keys are done. **Phase 3d** (deleting the old
  hard-wired code) has not started.

**The honest headline first: the code is currently a bit *longer*, not shorter.**
This phase is an investment. We added the new "controls list" machinery (the lookup
table, the part that reads it, and the commands to edit it) *before* we could start
removing the old hard-wired handling. So the file grew by roughly 425 lines. That
reverses later, in Phase 3d, when the old code gets deleted now that the new system
can replace it. So far we've only begun that removal (about 30 lines gone in the
most recent step).

**What is genuinely easier to read today:**

1. **Commands have names now.** Before, what a key did was spelled out as raw math
   and function calls buried inside one enormous 1,600-line block. Now each behavior
   is a small, clearly named piece (e.g. "zoom full", "scroll up", "hand this to the
   waveform graph"). You can tell what a key does by its name instead of decoding it.

2. **"Which key does what" is now a plain list, separate from "what it does."**
   Previously those two ideas were tangled together in every case. Now there's an
   editable list of "this input → this command," and you can print the whole list
   with one command to see every shortcut at a glance. That single, readable
   overview simply did not exist before.

3. **A copy-pasted block is being deleted.** The exact same five-line check —
   "if the mouse is over a waveform graph, hand the event to the graph" — had been
   pasted into the code about twenty times. We've removed it from the scroll-wheel
   handling entirely and from six keyboard shortcuts so far, each time replacing the
   duplicated code with a single line in the list. More removals are queued.

4. **One shared path instead of three different ones.** The wheel, the mouse-drag
   gestures, and the keyboard now all flow through the same handling, with one clear
   rule for which binding wins. A maintainer learns one mechanism, not three.

5. **The tricky, easy-to-break details are now written down.** The handful of subtle
   rules that used to be invisible traps (why certain shortcuts must stay as-is, why
   one check has to happen before another) are now explained in comments right where
   they matter, plus a short tutorial and these FAQ entries — so the next person
   doesn't have to rediscover them the hard way.

**Bottom line:** any individual shortcut is clearer (named, self-explaining, with its
reasoning attached), and the system as a whole is now navigable through one readable
list instead of a giant undocumented block. The raw line count is temporarily higher;
it drops below where it started once Phase 3d removes the now-replaceable old code.

---

## Q3. In plain language (high-school level): what are the next couple of steps, and what's the end goal?

- **Asked:** 2026-06-08
- **Project state:** branch `feature/action-registry` @ `cd5b5c9a` (wheel, zoom-rect
  gesture, and the no-modifier `f` + arrow keys are data-driven; Group B sweep next).

**Next couple of steps**

1. **"Group B" keys sweep.** A handful of keys (`a`, `b`, `s`, Ctrl+tab-switch
   arrows, …) each carry a copy-pasted "if the mouse is hovering over a waveform
   graph, hand this to the graph instead" check buried in a 1600-line block of C.
   The next step lifts just that check out into the lookup table (a plain list of
   "this input → does that"). The keys' normal jobs (open a dialog, save a file)
   stay in C; only the graph-routing part becomes data. This deletes a lot of
   duplicate code. (Caveat found while scoping: some of these keys check an
   "are we busy?" counter *before* the graph check, so they must be migrated
   carefully or deferred — see the semaphore-ordering note in the Phase 3c work.)
2. **Let an action run a Tcl command, not just C.** Today the table can only point a
   key at a built-in C function. Most menu items are written in Tcl (the scripting
   layer). Teaching the table to also say "this key runs *this script command*"
   unlocks migrating dozens more keys.

**End goal (the analogy)**

Think of a TV remote whose buttons are *soldered* to fixed jobs — you can't make the
red button do the green button's thing without rebuilding the remote. That's how
XSCHEM's keyboard/mouse handling works today: every shortcut is hard-wired deep in
the code.

We're replacing it with a **"Controls" settings list**, like the rebind-your-keys
menu in a video game. One master list says *"this key / mouse button / scroll does
this action,"* and:

- **You can edit it** in a config file to remap anything — no recompiling. (Already
  true for the scroll wheel and the arrow keys; see Q2.)
- **The help/cheat-sheet builds itself** from that same list, so it can't drift out
  of sync with what the keys actually do.
- Once everything is moved over, the old hard-wired code is **deleted**, leaving the
  program smaller and easier to maintain.

In one line: **turn soldered buttons into a remappable controls menu — for every
key, mouse button, and scroll — and let the help screen generate itself from it**,
done one small, fully-tested batch at a time so nothing breaks.

---

## Q2. Can a user remap the mouse wheel — **Ctrl+wheel = zoom, plain wheel = vertical pan, Shift+wheel = horizontal pan** — via `.xschemrc` / `--script`? (And why didn't the original author's `replace_key` snippet work?)

- **Asked:** 2026-06-08
- **Project state:** branch `feature/action-registry` @ `bfec8793` (Phase 3a wheel
  fully data-driven; 3b gestures; 3c c4/c5 first key `f`). Wheel dispatch goes
  through the in-C binding table (`xschem bind wheel ...`).

**Answer: Yes — fully supported and verified.** Put these in `~/.xschem/xschemrc`
(or `./.xschemrc`, or a `--script` file):

```tcl
# zoom with Ctrl+wheel
xschem bind wheel up   ctrl canvas view.zoom_in
xschem bind wheel down ctrl canvas view.zoom_out
# vertical pan with plain wheel
xschem bind wheel up   0    canvas view.pan_up
xschem bind wheel down 0    canvas view.pan_down
# Shift+wheel already pans horizontally (view.pan_left / view.pan_right) by default
```

Verified against observable state after firing synthetic wheel events
(`xschem callback .drw 4 <mx> <my> 0 <4|5> 0 <state>`; state 0/1/4 = plain/Shift/Ctrl):

| Input | Result | Verdict |
|---|---|---|
| plain wheel | `zoom` unchanged, `yorigin` moves | vertical pan ✅ |
| Ctrl+wheel  | `zoom` changes                   | zoom ✅ |
| Shift+wheel | `zoom` unchanged, `xorigin` moves | horizontal pan ✅ |

`xschem bindings dump` reflects the swap. (Swap `up`↔`down` for the opposite scroll
direction.) Timing is safe: `xschem bind` calls `ensure_input_bindings()`, which
lazily seeds the defaults *then* applies the override; `init_input_bindings()` is
guarded by `input_bindings_initialized`, so it never re-runs and clobbers the user's
rows — order of `.xschemrc` vs GUI bring-up does not matter.

**Why the original author's `replace_key` snippet didn't work.** `replace_key` is a
separate, *older, Tcl/Tk-level* mechanism (`set_replace_key_binding` →
`key_binding`, xschem.tcl:10994/1121). It installs a more-specific Tk binding such
as `<Control-Button-4>` that re-emits an `xschem callback` with a **rewritten
modifier mask** (e.g. mapping `Control-Button-4` → the state of a plain
`ButtonPress-4`), tricking the C wheel handler into seeing a different chord. It is
fragile in ways that bite silently:

- **Tk 8.7 / 9.0 deliver the wheel as `<MouseWheel>`, not `<Button-4/5>`**
  (xschem.tcl:9981 only binds `<MouseWheel>` when `tclversion > 8.7`). On those
  builds the `<Control-Button-4>` overrides never fire — the physical event isn't a
  Button-4 event. **Most likely cause of the failure.**
- Depends on Tk binding-specificity and on which widget (`.drw` vs the toplevel) the
  generic `<ButtonPress>` (xschem.tcl:9996/9998) vs the `replace_key` binding land
  on — subtle, easy to get subtly wrong.
- Piggybacks on the C button-mask stripping (`callback.c:4507`) as an undocumented
  implementation detail.

**Why the binding table is robust instead.** It dispatches **in C, after** the
event is normalized to "wheel up/down + clean modifier mask" — independent of Tk
version or how Tk delivered the event. It is the intended replacement for
`replace_key` for wheel/button/(now) key remapping.

**Caveats.**
1. Over a waveform graph, plain/Shift wheel still routes to the graph
   (`graph.forward` over_graph rows, unchanged); the canvas rebind only affects
   bare-canvas wheeling. Ctrl+wheel stays canvas-zoom even over a graph (its branch
   in `handle_mouse_wheel` forces `ctx=ACTX_CANVAS`).
2. Keep `graph_use_ctrl_key` at its default `0`. Setting it `1` reserves Ctrl+wheel
   for graph interaction, and `handle_mouse_wheel` returns early for Ctrl — so the
   canvas zoom binding won't be reached.

---

## Q1. Can a user remap the zoom-rectangle gesture from RMB-drag to **Ctrl+RMB-drag** with the current code?

- **Asked:** 2026-06-08
- **Project state:** branch `feature/action-registry` @ `898639af` (Phase 3a/3b done,
  Phase 3c c4/c5 first batch — key `f` — done). Mouse buttons: only the *bare*
  Button3 zoom-rect chord is data-driven (Phase 3b).

**Answer: No — not with the code at that commit, even though the binding can be created.**

`xschem bind button 3 ctrl canvas view.zoom_rect` parses and stores a valid row
(`parse_mods("ctrl") → ControlMask`, code 3). But the **press handler never reaches
the table dispatcher for a *modified* Button3 chord.**

`handle_button_press` (`callback.c`) is an `if / else-if` chain, and the data-driven
`dispatch_button_chord()` sits at the *end* of it (`callback.c:4560`). Earlier
`if`/`else if` branches hardcode the modified-Button3 chords and match first:

```c
if     (!excl && button==Button3 && state==ControlMask && semaphore<2) { … select_connected_nets(1); }  // 4522 ← Ctrl+RMB caught HERE
else if(!excl && button==Button3 && EQUAL_MODMASK && …)                { break_wires_at_point(…); }       // 4530/4536  (Alt+RMB)
else if(!excl && button==Button3 && state==ShiftMask && …)             { select_connected_nets(0); }      // 4542  (Shift+RMB)
…
else if(!excl && semaphore<2 && dispatch_button_chord(button, state, mx, my)) return;                      // 4560 ← table only reached here
```

`state` *is* correctly button-mask-stripped at `callback.c:4507`, so
`dispatch_button_chord` would see `mods==ControlMask` and *could* match the row — but
it is never called for Ctrl+Button3 because the hardcoded branch at 4522 wins and the
dispatch is in a later `else if`. Only **bare** Button3 falls through (the plain-RMB
context menu was moved to the release path, freeing the no-modifier slot).

**The completion side is already ready.** On Ctrl+RMB *release*, `state ==
Button3Mask|ControlMask`, so the exact-match context-menu branch
`if(state == Button3Mask)` (`callback.c:4779`) is skipped and the Phase 3b
fallthrough `else if((ui_state & STARTZOOM) && semaphore<2) end_place_move_copy_zoom()`
(`callback.c:4789`) completes the gesture. So only the **initiation** is blocked.

**What it would take** (a natural Phase 3 follow-on, same pattern as the key work):
1. Extract the hardcoded modified-Button3 branches into `act_*` fns
   (`select_connected_nets`, `break_wires_at_point`) + `{button 3 ctrl/shift/alt
   canvas}` rows; **or**
2. Move `dispatch_button_chord` earlier so a user-bound chord pre-empts the hardcoded
   default ("table-first, hardcoded-fallthrough" precedence, like the keys now have).

**UX consequence:** Ctrl+RMB is already a feature (select instance + connected nets,
stopping at junctions), so rebinding it to zoom means relocating that feature to
another chord.
