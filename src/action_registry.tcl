#
#  File: action_registry.tcl
#
#  This file is part of XSCHEM.
#
#  A declarative action registry: a single table (loaded from actions.csv) that
#  drives menus and the command palette. Keeping user actions as data — instead
#  of hand-syncing menu items, accelerators and help text — is what makes UI/UX
#  features (palette, customizable shortcuts, toolbars, tooltips) cheap to add.
#
#  Phase 1 scope: generate the File menu from the table, and offer a command
#  palette over it. The C keysym dispatcher (callback.c handle_key_press) is
#  untouched and remains the source of truth for keyboard handling; the 'accel'
#  column here is a display string only.
#
#  This file is GPL like the rest of XSCHEM (see xschem.tcl header).

# --- CSV parsing -------------------------------------------------------------

# Parse one RFC4180-style CSV line into a list of fields. Handles quoted fields
# containing commas and doubled "" escapes. Embedded newlines are not supported
# (the registry keeps every row on a single line).
proc action_parse_csv_line {line} {
  set fields {}
  set field {}
  set inq 0
  set n [string length $line]
  for {set i 0} {$i < $n} {incr i} {
    set c [string index $line $i]
    if {$inq} {
      if {$c eq "\""} {
        if {[string index $line [expr {$i + 1}]] eq "\""} {
          append field "\""
          incr i
        } else {
          set inq 0
        }
      } else {
        append field $c
      }
    } else {
      if {$c eq "\""} {
        set inq 1
      } elseif {$c eq ","} {
        lappend fields $field
        set field {}
      } else {
        append field $c
      }
    }
  }
  lappend fields $field
  return $fields
}

# Load actions.csv from the share dir into the global 'action_table' as an
# ordered list of dicts (one per row). Comment (#) and blank lines are skipped;
# the first non-comment line is the header that names the dict keys.
proc load_action_table {} {
  global XSCHEM_SHAREDIR action_table
  set action_table {}
  set path $XSCHEM_SHAREDIR/actions.csv
  if {![file exists $path]} {
    puts stderr "action registry: $path not found; menus fall back to hand-written items"
    return 0
  }
  set fp [open $path r]
  set data [read $fp]
  close $fp
  set header {}
  foreach line [split $data "\n"] {
    if {$line eq {}} continue
    if {[string index $line 0] eq "#"} continue
    set fields [action_parse_csv_line $line]
    if {$header eq {}} {
      set header $fields
      continue
    }
    set row {}
    foreach col $header val $fields {
      dict set row $col $val
    }
    lappend action_table $row
  }
  return [llength $action_table]
}

# --- menu generation ---------------------------------------------------------

# Build (populate) the menu widget <topwin>.menubar.<menukey> from every table
# row whose 'menu' field equals <menukey>, in table order. Submenus recurse;
# dynamic submenus delegate to their populate hook. The parent menu widget is
# expected to already exist (created in build_widgets like the other menus).
proc build_menu_from_table {topwin menukey} {
  global action_table
  set m $topwin.menubar.$menukey
  foreach row $action_table {
    if {[dict get $row menu] ne $menukey} continue
    set type [dict get $row type]
    set label [dict get $row label]
    set accel [dict get $row accel]
    switch -- $type {
      separator {
        $m add separator
      }
      command {
        set opts [list -label $label -command [dict get $row command]]
        if {$accel ne {}} { lappend opts -accelerator $accel }
        $m add command {*}$opts
      }
      cascade -
      dynamic {
        set sub [dict get $row submenu]
        set subw $topwin.menubar.$sub
        if {![winfo exists $subw]} {
          menu $subw -tearoff 0 -takefocus 0
        }
        $m add cascade -label $label -menu $subw
        if {$type eq {cascade}} {
          build_menu_from_table $topwin $sub
        } else {
          set hook [dict get $row hook]
          if {$hook ne {}} { $hook $topwin }
        }
      }
      default {
        puts stderr "action registry: unknown row type '$type' for [dict get $row id]"
      }
    }
  }
}

# --- actions extracted from inline menu scripts ------------------------------
# These were inline -command {...} bodies in the File menu; promoting them to
# named procs keeps every 'command' field in the table a clean single call.

proc action_component_browser {} {
  global new_file_browser
  if {$new_file_browser} {
    file_chooser
  } else {
    load_file_dialog {Insert symbol} *.sym INITIALINSTDIR 2
  }
}

proc action_reload {} {
  if {[alert_ "Are you sure you want to reload?" {} 0 1] == 1} {
    xschem reload
  }
}
