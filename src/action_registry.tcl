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

# --- command palette ---------------------------------------------------------
# Fuzzy-searchable launcher over the action table. Reuses fuzzy_subseq_score
# (the file-chooser matcher in xschem.tcl). Bound to Ctrl+Shift+P in
# set_bindings; runs entirely in the UI layer (does not go through the C
# keysym dispatcher).

# Rebuild the result list to match the current query. Guarded so that arrow/
# Return key releases (which also fire <KeyRelease>) don't rebuild and reset
# the selection while the user is navigating.
proc palette_refilter {} {
  global action_table palette_rows palette_query palette_last_query
  set w .cmd_palette
  if {![winfo exists $w]} return
  if {[info exists palette_last_query] && $palette_last_query eq $palette_query} return
  set palette_last_query $palette_query
  set q $palette_query
  set scored {}
  foreach row $action_table {
    if {[dict get $row type] ne {command}} continue
    if {$q eq {}} {
      lappend scored [list 0 $row]
      continue
    }
    set sc [fuzzy_subseq_score $q [dict get $row label]]
    foreach field {help id} {
      set s [fuzzy_subseq_score $q [dict get $row $field]]
      if {$s > $sc} { set sc $s }
    }
    if {$sc >= 0} { lappend scored [list $sc $row] }
  }
  if {$q ne {}} { set scored [lsort -decreasing -integer -index 0 $scored] }
  set palette_rows {}
  $w.l delete 0 end
  set n 0
  foreach pair $scored {
    if {$n >= 200} break
    set row [lindex $pair 1]
    lappend palette_rows $row
    set label [dict get $row label]
    set accel [dict get $row accel]
    if {$accel ne {}} {
      $w.l insert end [format "%-46s %s" $label "\[$accel\]"]
    } else {
      $w.l insert end $label
    }
    incr n
  }
  if {[llength $palette_rows] > 0} {
    $w.l selection clear 0 end
    $w.l selection set 0
    $w.l activate 0
  }
}

# Move the listbox selection by $dir (+1/-1), clamped.
proc palette_move {dir} {
  set w .cmd_palette
  if {![winfo exists $w]} return
  set last [expr {[$w.l index end] - 1}]
  if {$last < 0} return
  set cur [$w.l index active]
  if {$cur eq {}} { set cur 0 }
  set new [expr {$cur + $dir}]
  if {$new < 0} { set new 0 }
  if {$new > $last} { set new $last }
  $w.l selection clear 0 end
  $w.l selection set $new
  $w.l activate $new
  $w.l see $new
}

# Run the highlighted action and close the palette.
proc palette_run {} {
  global palette_rows
  set w .cmd_palette
  if {![winfo exists $w]} return
  set sel [$w.l curselection]
  if {[llength $sel]} {
    set idx [lindex $sel 0]
  } else {
    set idx [$w.l index active]
  }
  if {$idx eq {} || $idx < 0 || $idx >= [llength $palette_rows]} return
  set cmd [dict get [lindex $palette_rows $idx] command]
  destroy $w
  if {$cmd ne {}} {
    if {[catch {uplevel #0 $cmd} err]} { puts stderr "command palette: $err" }
  }
}

# Open (or re-open) the command palette as a small dialog near the top of the
# parent toplevel.
proc command_palette { {parent {}} } {
  global palette_query palette_last_query
  if {$parent eq {} || ![winfo exists $parent]} { set parent . }
  set parent [winfo toplevel $parent]
  set w .cmd_palette
  if {[winfo exists $w]} { destroy $w }
  toplevel $w
  wm title $w {Command palette}
  catch {wm transient $w $parent}
  set palette_query {}
  catch {unset palette_last_query}
  entry $w.q -textvariable palette_query
  listbox $w.l -height 14 -width 72 -activestyle dotbox -exportselection 0
  pack $w.q -side top -fill x -padx 2 -pady 2
  pack $w.l -side top -fill both -expand 1 -padx 2 -pady 2
  bind $w.q <KeyRelease> palette_refilter
  bind $w.q <Down>   {palette_move 1 ; break}
  bind $w.q <Up>     {palette_move -1 ; break}
  bind $w.q <Next>   {palette_move 10 ; break}
  bind $w.q <Prior>  {palette_move -10 ; break}
  bind $w.q <Return> {palette_run ; break}
  bind $w.q <Escape> {destroy .cmd_palette ; break}
  bind $w.l <Double-Button-1> palette_run
  bind $w.l <Return> palette_run
  bind $w <Escape> {destroy .cmd_palette}
  palette_refilter
  # center horizontally near the top of the parent window
  catch {
    update idletasks
    set x [expr {[winfo rootx $parent] + ([winfo width $parent] - [winfo reqwidth $w]) / 2}]
    set y [expr {[winfo rooty $parent] + 80}]
    if {$x < 0} { set x 0 }
    wm geometry $w +$x+$y
  }
  focus $w.q
}
