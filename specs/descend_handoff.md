# Descend-preserve work — session handoff / resume

## RESUME PROMPT (paste after /clear)

> Continue the descend autosave work on branch `fluid-editing`. The design PIVOTED
> from an in-memory snapshot to an editor-style `cellName~.sch` backing file — read
> the "DESIGN PIVOT" section of `specs/descend_hierarchy_in_memory.md` (plan) and
> this file first. Steps 1–6 (in-memory, now superseded) and B1–B3 (backing file)
> are DONE and committed; resume at **B4** (remove the dead in-memory machinery:
> hier_slot[], mem_*_hier, descend_keep_in_memory, `get hier_slots`). Build + run
> the suites after each step, commit per step, and EXTEND the living tutorial
> `code_analysis/descend_in_memory_tutorial.md` with each step's lesson(s).
>
> Backing-file model: a genuine edit (`set_modify(1)`) writes `cellName~.sch`
> (`write_backup`, save.c); a real `save_schematic` removes it; `load_schematic`
> guards itself with `xctx->no_autosave`; `go_back` loads the `~` if present
> (identity restored to cellName). autosave_backup flag (default 1). `*~.sch/.sym`
> gitignored. Tests: test_backup_file, test_autosave_hook, test_descend_preserve
> (S1 green / S2 red until B5), test_descend_efficiency, test_descend_fidelity.

## Where things stand (2026-06-20)

Branch `fluid-editing`. Goal: descending into a sub-schematic must never prompt
to save and never lose unsaved parent edits; prompts only at window-close and
go_back. Mechanism: snapshot the parent into `hier_slot[]` (reusing the undo
serializer) on descend; restore from it on go_back.

### Committed
- `4dbed77` Part 1: load-time auto-trim no longer flags a fresh file modified.
- `4b03b7d` Step 1: RED acceptance test `tests/headless/test_descend_preserve.tcl`
  + fixture `tests/headless/fixtures/descend/` (parent→child).
- `2909f2e` Steps 2–3: extracted `mem_serialize_slot` / `mem_restore_slot`;
  `free_undo_*` generalized to `(Undo_slot *)`.
- `094eb49` Step 4: `hier_slot[CADMAXHIER]` + `hier_slot_valid/modified[]` store
  + `mem_init/free_hier_slot(s)`; freed in `free_xschem_data`.
- `d38074c` Step 5: descend snapshots parent (`mem_snapshot_hier`), go_back
  overlays it (`mem_restore_hier`) after the disk load_schematic. Flag
  `descend_keep_in_memory` (default 1). **S1 GREEN.**
- `12bae6d` Step 6: fidelity test `test_descend_fidelity.tcl` (+ richer fixture
  `descend_fid_parent.sch`). Found that net resolution (even `select`) bakes
  derived `lab=` into wire props; the snapshot captured it so a clean parent
  came back non-identical to disk. **Fix:** go_back overlays the snapshot ONLY
  when the parent had unsaved edits (`hier_slot_modified`); a clean parent uses
  the authoritative disk reload → byte-identical. Snapshot also moved before
  descend's `prepare_netlist_structs`.

### Acceptance test status
`env -u DISPLAY ./src/xschem --nogui --pipe -q --nolog --script tests/headless/test_descend_preserve.tcl`
- S1 (no data loss): **PASS**
- S2 (no prompt): **RED** — flips at Step 7 (remove descend save block).
Fidelity: `tests/headless/test_descend_fidelity.tcl` → ALL PASS.

### Suites (all green)
- `bash tests/headless/wireedit/run_wireedit.sh` → 18/18
- `cd tests && tclsh run_regression.tcl` → no FAIL/GOLD/FATAL
  (needs `XSCHEM_SHAREDIR=<repo>/src`)
- Rebuild: `cd src && make xschem`

## Key implementation facts
- Shared serializer: `mem_serialize_slot`/`mem_restore_slot` in
  `in_memory_undo.c`; hierarchy wrappers `mem_snapshot_hier(lvl)` /
  `mem_restore_hier(lvl)` (returns 1 if restored). Slots lazily allocated
  (`mem_init_hier_slot`), freed per-level on go_back + all on teardown.
- descend snapshots at the PARENT level index (before `currsch++`),
  `actions.c` ~2672. go_back overlays after `currsch--` + load_schematic,
  `actions.c` ~2773.
- go_back **overlay** approach: keep disk `load_schematic` (file identity/title/
  netlist-dir bookkeeping), then `mem_restore_hier` swaps in preserved geometry
  ONLY when `hier_slot_modified[currsch]` is set (parent had unsaved edits);
  otherwise free the slot and keep the clean disk reload. Confines net-name
  baking to already-dirty parents and keeps clean parents byte-identical.
- Embedded-symbol returns (`.xschem_embedded_`) deliberately still use the disk
  path; go_back just frees the slot. That's Step 8.

## Remaining steps (RED-first)
- **Step 6**: validate restore fidelity — extend S1 to assert zoom, netlist
  output, and hilight survive go_back vs a disk-reload baseline. Decide whether
  to drop the now-redundant disk read in the overlay.
- **Step 7**: add S2 RED assertion already present; remove the
  `if(xctx->modified) save(1,0)` block in `descend_schematic` (`actions.c` ~2562).
  → S2 GREEN. (Keep go_back + close prompts.)
- **Step 8**: embedded symbols — snapshot already deep-copies `sym[]`; make
  go_back restore embedded edits from memory and drop redundant temp-reload.
- **Step 9**: tab interaction — `hier_slot[]` rides per-tab ctx; audit
  `switch_tab`; new `test_descend_tab`.
- **Step 10**: deep multi-level descend + free hier_slots on jump-to-top /
  clear_schematic / new-file (currently only go_back + teardown free them →
  potential leak on direct currsch reset); leak check `xschemtest -d 3`.
- **Step 11**: GUI eyeball with `src/xschem --script src/cadence_style_rc`.

## Known gaps / watch-items
- Direct `currsch` resets (jump to top, clear_schematic, load new top file) do
  NOT yet free intermediate hier_slots → leak until teardown. Fix in Step 10.
- Overlay does a disk read then discards its geometry — wasteful but correct.
