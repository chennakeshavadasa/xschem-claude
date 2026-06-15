# library_manager.tcl — a Cadence-style Library Manager (library-manager Phase 7).
#
# Layout follows the Cadence Library Manager: three always-visible columns,
# left to right, in a resizable paned window:
#
#     +-----------+-----------+-----------+
#     | Library   | Cell      | View      |
#     |  devices  |  res      |  schematic|
#     |  examples |  nmos4    |  symbol   |
#     |  logic    |  ...      |           |
#     +-----------+-----------+-----------+
#
# Selecting a library fills the Cell column; selecting a cell fills the View
# column. Double-click a view (or use the buttons) to open the schematic or
# place the symbol. (A Category column, as in Cadence, can slot between Library
# and Cell once xschem grows a category model; it is intentionally omitted now.)
#
# Built entirely on the read-only query commands:
#   xschem libraries / lib_cells <lib> / cell_views <lib> <cell>
# and the resolver `xschem cellview_path <lib/cell> <view>` (flat- and
# lib/cell/view-aware). Open with:  library_manager   (or Tools -> Library Manager)

namespace eval libmgr {
  variable sel_lib  "" ;# currently selected library name
  variable sel_cell "" ;# currently selected cell name
}

proc libmgr::open {} {
  set w .libmgr
  if {[winfo exists $w]} { raise $w; libmgr::refresh; return }
  toplevel $w
  wm title $w "Library Manager"
  wm geometry $w 760x460

  ttk::panedwindow $w.pw -orient horizontal
  pack $w.pw -side top -fill both -expand 1

  # one column = header label + listbox + scrollbar, in a frame added to the pane
  foreach {col title} {lib Library cell Cell view View} {
    set f [ttk::frame $w.pw.$col]
    ttk::label $f.h -text $title -anchor w -padding {4 2}
    listbox $f.lb -exportselection 0 -activestyle dotbox \
            -yscrollcommand "$f.sb set" -width 18 -height 20
    ttk::scrollbar $f.sb -orient vertical -command "$f.lb yview"
    grid $f.h  -row 0 -column 0 -columnspan 2 -sticky we
    grid $f.lb -row 1 -column 0 -sticky nsew
    grid $f.sb -row 1 -column 1 -sticky ns
    grid rowconfigure $f 1 -weight 1
    grid columnconfigure $f 0 -weight 1
    $w.pw add $f -weight 1
  }

  ttk::label $w.status -anchor w -relief sunken -padding {4 2} -text "select a library"
  pack $w.status -side bottom -fill x

  ttk::frame $w.b
  ttk::button $w.b.open  -text "Open schematic" -command libmgr::open_schematic
  ttk::button $w.b.place -text "Place symbol"   -command libmgr::place_symbol
  ttk::button $w.b.ref   -text "Refresh"        -command libmgr::refresh
  ttk::button $w.b.close -text "Close"          -command "destroy $w"
  pack $w.b.open $w.b.place $w.b.ref -side left -padx 4 -pady 4
  pack $w.b.close -side right -padx 4 -pady 4
  pack $w.b -side bottom -fill x

  bind $w.pw.lib.lb  <<ListboxSelect>> libmgr::on_lib
  bind $w.pw.cell.lb <<ListboxSelect>> libmgr::on_cell
  bind $w.pw.view.lb <<ListboxSelect>> libmgr::on_view
  bind $w.pw.cell.lb <Double-1>        libmgr::open_schematic
  bind $w.pw.view.lb <Double-1>        libmgr::activate

  libmgr::populate_libs
}

# helper: the selected text in a listbox, or "" if none
proc libmgr::cursel {lb} {
  set i [$lb curselection]
  if {$i eq {}} { return "" }
  return [$lb get [lindex $i 0]]
}

proc libmgr::populate_libs {} {
  variable sel_lib; variable sel_cell
  set lb .libmgr.pw.lib.lb
  $lb delete 0 end
  foreach pair [xschem libraries] { $lb insert end [lindex $pair 0] }
  .libmgr.pw.cell.lb delete 0 end
  .libmgr.pw.view.lb delete 0 end
  set sel_lib ""; set sel_cell ""
}

proc libmgr::refresh {} {
  if {[winfo exists .libmgr]} { libmgr::populate_libs }
}

# library selected -> fill the Cell column, clear the View column
proc libmgr::on_lib {args} {
  variable sel_lib; variable sel_cell
  set sel_lib [libmgr::cursel .libmgr.pw.lib.lb]
  set sel_cell ""
  set cl .libmgr.pw.cell.lb
  $cl delete 0 end
  .libmgr.pw.view.lb delete 0 end
  if {$sel_lib ne ""} {
    foreach c [xschem lib_cells $sel_lib] { $cl insert end $c }
  }
  .libmgr.status configure -text "library: $sel_lib"
}

# cell selected -> fill the View column
proc libmgr::on_cell {args} {
  variable sel_lib; variable sel_cell
  set sel_cell [libmgr::cursel .libmgr.pw.cell.lb]
  set vl .libmgr.pw.view.lb
  $vl delete 0 end
  if {$sel_lib ne "" && $sel_cell ne ""} {
    foreach v [xschem cell_views $sel_lib $sel_cell] { $vl insert end $v }
  }
  .libmgr.status configure -text "$sel_lib / $sel_cell"
}

proc libmgr::on_view {args} {
  variable sel_lib; variable sel_cell
  set v [libmgr::cursel .libmgr.pw.view.lb]
  .libmgr.status configure -text "$sel_lib / $sel_cell / $v"
}

# the {lib cell} currently selected, or {} if incomplete
proc libmgr::current_cell {} {
  variable sel_lib; variable sel_cell
  if {$sel_lib eq "" || $sel_cell eq ""} { return {} }
  return [list $sel_lib $sel_cell]
}

proc libmgr::open_schematic {} {
  set lc [libmgr::current_cell]
  if {$lc eq {}} return
  set ref "[lindex $lc 0]/[lindex $lc 1]"
  set f [xschem cellview_path $ref schematic]
  if {$f ne {}} { xschem load $f } \
  else { .libmgr.status configure -text "no schematic view for $ref" }
}

proc libmgr::place_symbol {} {
  set lc [libmgr::current_cell]
  if {$lc eq {}} return
  set ref "[lindex $lc 0]/[lindex $lc 1]"
  if {[xschem cellview_path $ref symbol] ne {}} { xschem place_symbol $ref } \
  else { .libmgr.status configure -text "no symbol view for $ref" }
}

# double-click a view: open it (schematic) or place it (symbol)
proc libmgr::activate {args} {
  set v [libmgr::cursel .libmgr.pw.view.lb]
  if {$v eq "schematic"} { libmgr::open_schematic } \
  elseif {$v eq "symbol"} { libmgr::place_symbol }
}

# convenience global alias
proc library_manager {} { libmgr::open }
