proc place_libmgr_selection {} {
  set sel [libmgr::selection]
  if {[llength $sel] < 2} { ciw_echo "select at least a cell in the Library Manager" error; return }
  lassign $sel lib cell view
  if {$view eq ""} { set view symbol }      ;# default to the symbol view
  set f [xschem cellview_path "$lib/$cell" $view]
  if {$f eq "" || ![string match *.sym $f]} { ciw_echo "no symbol view for $lib/$cell" error; return }
  ciform::set_fields [list $lib $cell $view]  ;# remember it for the Create Instance form
  xschem place_symbol $f                      ;# cursor preview; click to drop
}

proc locate_selected_in_libmgr {} {
  if {[catch {xschem get_inst_lcv} lcv]} {
    ciw_echo "select exactly one instance first ($lcv)" error
    return
  }
  xschem library_manager $lcv
}


