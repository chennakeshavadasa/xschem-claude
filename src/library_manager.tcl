# library_manager.tcl — a Cadence-style Library Manager (library-manager Phase 7).
#
# A ttk::treeview browser over the Library -> Cell -> View model, built entirely
# on the read-only query commands:
#   xschem libraries            -> {name path} pairs
#   xschem lib_cells <lib>      -> cells in a library
#   xschem cell_views <lib> <c> -> views of a cell
# and the resolver `xschem cellview_path <lib/cell> <view>`. The tree is lazily
# populated (cells/views are filled in when a node is expanded), so it scales to
# large libraries. Double-clicking a view opens the schematic or starts placing
# the symbol; the same is available via the buttons.
#
# Open it with:  library_manager        (or Tools -> Library Manager)

namespace eval libmgr {
  variable kind     ;# item -> lib|cell|view
  variable lib      ;# item -> library name
  variable cell     ;# item -> cell name
  variable view     ;# item -> view name
  variable loaded   ;# item -> 1 once its children are populated
  array set kind {}; array set lib {}; array set cell {}; array set view {}
  array set loaded {}
}

proc libmgr::open {} {
  set w .libmgr
  if {[winfo exists $w]} { raise $w; libmgr::refresh; return }
  toplevel $w
  wm title $w "Library Manager"
  wm geometry $w 460x520

  ttk::frame $w.top
  ttk::label $w.top.l -text "Libraries"
  ttk::button $w.top.r -text "Refresh" -command libmgr::refresh
  pack $w.top.l -side left -padx 6 -pady 4
  pack $w.top.r -side right -padx 6 -pady 4
  pack $w.top -side top -fill x

  ttk::frame $w.f
  ttk::treeview $w.f.t -show tree -selectmode browse -yscrollcommand "$w.f.sb set"
  ttk::scrollbar $w.f.sb -orient vertical -command "$w.f.t yview"
  pack $w.f.sb -side right -fill y
  pack $w.f.t -side left -fill both -expand 1
  pack $w.f -side top -fill both -expand 1

  ttk::label $w.status -anchor w -relief sunken -text "select a cell or view"
  pack $w.status -side bottom -fill x

  ttk::frame $w.b
  ttk::button $w.b.open  -text "Open schematic" -command libmgr::open_schematic
  ttk::button $w.b.place -text "Place symbol"   -command libmgr::place_symbol
  ttk::button $w.b.close -text "Close"          -command "destroy $w"
  pack $w.b.open $w.b.place -side left -padx 4 -pady 4
  pack $w.b.close -side right -padx 4 -pady 4
  pack $w.b -side bottom -fill x

  set t $w.f.t
  bind $t <<TreeviewOpen>>   {libmgr::on_open  [%W focus]}
  bind $t <<TreeviewSelect>> {libmgr::on_select %W}
  bind $t <Double-1>         {libmgr::activate %W}

  libmgr::populate_libs
}

# (re)build the top level from the registry
proc libmgr::populate_libs {} {
  variable kind; variable lib; variable cell; variable view; variable loaded
  set t .libmgr.f.t
  $t delete [$t children {}]
  array unset kind;  array set kind {}
  array unset lib;   array set lib {}
  array unset cell;  array set cell {}
  array unset view;  array set view {}
  array unset loaded; array set loaded {}
  foreach pair [xschem libraries] {
    set name [lindex $pair 0]
    set id [$t insert {} end -text $name -open 0]
    set kind($id) lib
    set lib($id)  $name
    set loaded($id) 0
    $t insert $id end -text "" -tags dummy   ;# placeholder so the [+] shows
  }
}

proc libmgr::refresh {} {
  if {[winfo exists .libmgr]} { libmgr::populate_libs }
}

# lazily fill a node's children the first time it is expanded
proc libmgr::on_open {id} {
  variable kind; variable lib; variable cell; variable view; variable loaded
  set t .libmgr.f.t
  if {$id eq {} || $loaded($id)} return
  $t delete [$t children $id]      ;# drop the placeholder
  set loaded($id) 1
  if {$kind($id) eq "lib"} {
    foreach c [xschem lib_cells $lib($id)] {
      set cid [$t insert $id end -text $c -open 0]
      set kind($cid) cell
      set lib($cid)  $lib($id)
      set cell($cid) $c
      set loaded($cid) 0
      $t insert $cid end -text "" -tags dummy
    }
  } elseif {$kind($id) eq "cell"} {
    foreach v [xschem cell_views $lib($id) $cell($id)] {
      set vid [$t insert $id end -text $v]
      set kind($vid) view
      set lib($vid)  $lib($id)
      set cell($vid) $cell($id)
      set view($vid) $v
    }
  }
}

proc libmgr::on_select {t} {
  variable kind; variable lib; variable cell; variable view
  set id [$t focus]
  if {$id eq {} || ![info exists kind($id)]} return
  switch $kind($id) {
    lib  { .libmgr.status configure -text "library: $lib($id)" }
    cell { .libmgr.status configure -text "$lib($id) / $cell($id)" }
    view { .libmgr.status configure -text "$lib($id) / $cell($id) / $view($id)" }
  }
}

# resolve the currently selected node to {lib cell} (cell or view level), or {}
proc libmgr::current_cell {} {
  variable kind; variable lib; variable cell
  set t .libmgr.f.t
  set id [$t focus]
  if {$id eq {} || ![info exists kind($id)]} { return {} }
  if {$kind($id) eq "lib"} { return {} }
  return [list $lib($id) $cell($id)]
}

proc libmgr::open_schematic {} {
  set lc [libmgr::current_cell]
  if {$lc eq {}} return
  set ref "[lindex $lc 0]/[lindex $lc 1]"
  set f [xschem cellview_path $ref schematic]
  if {$f ne {}} { xschem load $f } else { .libmgr.status configure -text "no schematic view for $ref" }
}

proc libmgr::place_symbol {} {
  set lc [libmgr::current_cell]
  if {$lc eq {}} return
  set ref "[lindex $lc 0]/[lindex $lc 1]"
  if {[xschem cellview_path $ref symbol] ne {}} {
    xschem place_symbol $ref
  } else { .libmgr.status configure -text "no symbol view for $ref" }
}

# double-click: a view opens/places per its kind; a cell opens its schematic
proc libmgr::activate {t} {
  variable kind; variable view
  set id [$t focus]
  if {$id eq {} || ![info exists kind($id)]} return
  if {$kind($id) eq "view"} {
    if {$view($id) eq "schematic"} { libmgr::open_schematic } \
    elseif {$view($id) eq "symbol"} { libmgr::place_symbol }
  } elseif {$kind($id) eq "cell"} {
    libmgr::open_schematic
  }
}

# convenience global alias
proc library_manager {} { libmgr::open }
