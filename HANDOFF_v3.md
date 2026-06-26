# HANDOFF — xschem-claude PR Project
# Status: PIVOTING — new contribution branch created

## CURRENT SITUATION

### PR #2 (OBSOLETE — Nithin to close manually)
  https://github.com/ananthchellappa/xschem-claude/pull/2
  This PR implements Phase 2 Tcl intercept system.
  Ananth explicitly retired Phase 2 in his feature/action-registry branch
  with commits "Phase 3d.5a/5b — retire the Phase-2 Tk intercept".
  PR #2 must be CLOSED by Nithin. Do not merge it.

### NEW CONTRIBUTION BRANCH
  Branch: feature/ux-additions (in myfork)
  Base:   origin/feature/action-registry (Ananth's Phase 3d architecture)
  Target PR: Nithin will open to Ananth's feature/action-registry branch

### WHAT WE CONTRIBUTE (3 items, all compatible with Phase 3d)

1. Status bar hover help (D3)
   - handle_menu_hover reads help column, shows in .statusbar.1
   - bind_menu_hover_help wires <<MenuSelect>> on all 11 menus
   - No Tk bind() intercept, no C changes

2. Recently used commands in palette (D2)
   - record_recent_action proc (capped list of 8)
   - recent_palette_ids shown first in empty-query palette
   - Compatible with Ananth's command_palette proc

3. 121 additional actions.csv rows
   - Full menu population for Options, Properties, Tools, Symbol,
     Highlight, Simulation, Waves, Help menus
   - Uses Ananth's column format: id,type,menu,label,accel,command,
                                   variable,value,submenu,hook,help,icon
   - Accel field BLANK (his C-level keybindings.csv handles keys)

### ANANTH'S ACTIVE BRANCHES (for context)
  library-manager         — 304 ahead, 10hrs ago (library management feature)
  fluid-editing           — 451 ahead, 13hrs ago (adds nolog column, drag-select)
  feature/autocomplete    — 384 ahead, CI FAILING (TAB autocomplete CIW style)
  feature/action-logging  — 107 ahead (action logging with nolog column)
  feature/action-registry — 68 ahead  ← BASE of our new contribution
  All other branches also build on feature/action-registry.

### ANANTH'S ARCHITECTURE (Phase 3d)
  keybindings.csv → C dispatch table (callback.c) → key events
  mousebindings.csv → C dispatch table → mouse events
  actions.csv → build_menu_from_table → Tk menus
  action_registry.tcl → command_palette, menu building, UI

### RULES
  NEVER open a PR. Nithin does this manually.
  NEVER force push to myfork/main.
  NEVER touch src/*.c src/*.h.
  When the new PR target is feature/action-registry, NOT main.

## MANUAL STEPS FOR NITHIN
  1. Close PR #2 at https://github.com/ananthchellappa/xschem-claude/pull/2
  2. Open new PR from myfork:feature/ux-additions
     targeting ananthchellappa:feature/action-registry
