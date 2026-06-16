# library_defs.tcl — library registry (Cadence cds.lib analog).
#
# Phase 1 of the library-manager work (see code_analysis/library_manager_design.md).
# Read-only model only: it answers "what libraries exist and where do they live",
# and changes NOTHING about reference resolution (that is Phase 2). A library is a
# NAME -> directory mapping drawn from two sources:
#
#   1. library.defs files listed in $XSCHEM_LIBRARY_DEFS (colon-separated on Unix,
#      semicolon on Windows). Each file holds lines:
#          DEFINE <name> <path>
#      with '#' comments and blank lines ignored. <path> is subject to ${VAR}
#      environment-variable expansion and a leading '~' (HOME) expansion.
#
#   2. auto-discovery: any directory on the cleaned search list ($pathlist) that
#      contains a "library.tag" file is itself a library. Its name comes from the
#      tag's "NAME <name>" line, or the directory basename if absent. This bridges
#      the legacy "just add the dir to XSCHEM_LIBRARY_PATH" workflow.
#
# Precedence: an explicit DEFINE wins over an auto-discovered tag of the same
# name; among defs files (and repeated DEFINEs) the last one read wins.

# Expand ${VAR} and a leading ~ in a defs path. Unknown ${VAR} is left verbatim.
proc library_defs_expand_path {path} {
  global env
  regsub {^~$}  $path $env(HOME)   path
  regsub {^~/} $path "$env(HOME)/" path
  while {[regexp {\$\{([A-Za-z_][A-Za-z0-9_]*)\}} $path -> var]} {
    if {[info exists env($var)]} {
      regsub -all "\\\$\\{$var\\}" $path $env($var) path
    } else {
      break
    }
  }
  return $path
}

# Parse one library.defs file, appending name->path into the dict in `defsvar`.
# A relative DEFINE path is resolved against the directory of the defs file (the
# cds.lib convention), so a committed library.defs is location-independent.
proc library_defs_parse_file {fname defsvar} {
  upvar 1 $defsvar defs
  if {[catch {open $fname r} fp]} { return }
  set base [file dirname [file normalize $fname]]
  while {[gets $fp line] >= 0} {
    set line [string trim $line]
    if {$line eq {} || [string index $line 0] eq "#"} { continue }
    if {[regexp {^DEFINE\s+(\S+)\s+(.+)$} $line -> name path]} {
      set p [library_defs_expand_path [string trim $path]]
      if {[file pathtype $p] ne "absolute"} { set p [file normalize [file join $base $p]] }
      dict set defs $name $p
    }
  }
  close $fp
}

# Read the name for a tagged directory: the "NAME <name>" line in library.tag,
# else the directory basename.
proc library_tag_name {dir} {
  set tag [file join $dir library.tag]
  if {![catch {open $tag r} fp]} {
    while {[gets $fp line] >= 0} {
      set line [string trim $line]
      if {[regexp {^NAME\s+(\S+)} $line -> name]} { close $fp; return $name }
    }
    close $fp
  }
  return [file tail $dir]
}

# The library registry as an ordered dict {name -> abs path}. Auto-discovered
# tags first, then defs files (so an explicit DEFINE overrides a tag).
proc library_registry {} {
  global XSCHEM_LIBRARY_DEFS pathlist OS
  set defs [dict create]

  # sources on the search list (lower precedence than the defs files below):
  #  - a dir carrying a library.tag is a library with the tag's NAME
  #  - any other search-path dir is ALSO a library, named by its basename, so the
  #    Library Manager shows the user's existing (flat) libraries out of the box.
  #    First occurrence wins (mirrors the search order).
  if {[info exists pathlist]} {
    foreach dir $pathlist {
      if {[file exists [file join $dir library.tag]]} {
        dict set defs [library_tag_name $dir] $dir
      } else {
        set bn [file tail [file normalize $dir]]
        if {$bn ne {} && ![dict exists $defs $bn]} { dict set defs $bn $dir }
      }
    }
  }

  # source 1 (higher precedence): the defs files
  if {[info exists XSCHEM_LIBRARY_DEFS] && $XSCHEM_LIBRARY_DEFS ne {}} {
    set sep [expr {$OS eq "Windows" ? {;} : {:}}]
    foreach f [split $XSCHEM_LIBRARY_DEFS $sep] {
      if {$f ne {} && [file exists $f]} { library_defs_parse_file $f defs }
    }
  }
  return $defs
}

# `xschem libraries` backend: sorted list of {name path} pairs.
proc library_list {} {
  set out {}
  set defs [library_registry]
  foreach name [lsort [dict keys $defs]] {
    lappend out [list $name [dict get $defs $name]]
  }
  return $out
}

# `xschem library <name>` backend: the library's path, or "" if undefined.
proc library_resolve {name} {
  set defs [library_registry]
  if {[dict exists $defs $name]} { return [dict get $defs $name] }
  return {}
}

# --- Phase 2: lib/cell/view resolution -------------------------------------
# A registered library 'libname' holds cell 'cell' whose 'view' datafile lives at
# <libpath>/<cell>/<view>/<cell>.<ext>. Returns the absolute path if that file
# exists, else "" (callers fall back to the legacy flat search).
proc cellview_resolve {libname cell view} {
  set lpath [library_resolve $libname]
  if {$lpath eq {}} { return {} }
  set ext [expr {$view eq "schematic" ? ".sch" : ".sym"}]
  # new lib/cell/view layout
  set cand [file join $lpath $cell $view $cell$ext]
  if {[file exists $cand]} { return $cand }
  # legacy flat layout (so the Library Manager can open/place flat cells, and a
  # lib-qualified ref to a flat lib resolves to the same file rule 3 would find)
  set flat [file join $lpath $cell$ext]
  if {[file exists $flat]} { return $flat }
  return {}
}

# `xschem cellview_path <lib/cell> <view>` backend. The reference is "lib/cell"
# (a trailing .sym/.sch extension, if present, is ignored — the view argument
# governs). Returns the abs datafile path or "".
proc cellview_path {ref view} {
  if {![regexp {^([^/]+)/(.+)$} $ref -> libname rest]} { return {} }
  return [cellview_resolve $libname [file rootname $rest] $view]
}

# --- Phase 7a: tree enumeration (Library -> Cell -> View) ------------------
# Cells in a registered library: immediate subdirs that hold at least one view
# directory (a subdir containing a <cell>.<ext> datafile). Sorted, deduped.
proc library_cells {libname} {
  set lpath [library_resolve $libname]
  if {$lpath eq {}} { return {} }
  set cells {}
  # new lib/cell/view layout: subdirs holding a view dir with a <cell>.<ext>
  foreach d [glob -nocomplain -type d [file join $lpath *]] {
    set cell [file tail $d]
    if {[llength [glob -nocomplain [file join $d * $cell.*]]] > 0} { lappend cells $cell }
  }
  # legacy flat layout: <cell>.sym / <cell>.sch directly in the library dir
  foreach f [glob -nocomplain [file join $lpath *.sym] [file join $lpath *.sch]] {
    lappend cells [file rootname [file tail $f]]
  }
  return [lsort -unique $cells]
}

# Views present for a cell: subdirs of <lib>/<cell> that hold a <cell>.<ext>
# datafile (general over schematic/symbol/layout/...). Sorted.
proc cell_views {libname cell} {
  set lpath [library_resolve $libname]
  if {$lpath eq {}} { return {} }
  set views {}
  # new layout: subdirs of <lib>/<cell> holding a <cell>.<ext> datafile
  foreach d [glob -nocomplain -type d [file join $lpath $cell *]] {
    if {[llength [glob -nocomplain [file join $d $cell.*]]] > 0} { lappend views [file tail $d] }
  }
  # legacy flat layout: <cell>.sym -> symbol, <cell>.sch -> schematic
  if {[file isfile [file join $lpath $cell.sym]]} { lappend views symbol }
  if {[file isfile [file join $lpath $cell.sch]]} { lappend views schematic }
  return [lsort -unique $views]
}

# abs_sym_path rule 2: resolve a lib-qualified reference "lib/cell[.ext]" under
# the new layout. The view is inferred from the extension (.sch -> schematic,
# else symbol). Returns "" on any miss so abs_sym_path falls through to legacy.
proc lib_qualified_abs {fname} {
  if {![regexp {^([^/]+)/(.+)$} $fname -> libname rest]} { return {} }
  if {[library_resolve $libname] eq {}} { return {} }
  switch -- [file extension $rest] {
    .sch    { set view schematic }
    default { set view symbol }
  }
  return [cellview_resolve $libname [file rootname $rest] $view]
}

# rel_sym_path rule 2: if 'symbol' is an absolute path to a SYMBOL view inside a
# registered library (<libpath>/<cell>/symbol/<cell>.sym) return the portable
# "lib/cell" reference (longest-matching library wins). Else "" and the caller
# uses the legacy prefix stripping. Schematic-view paths are left to legacy here
# (lib-qualified schematic references are handled in Phase 4 / descend).
proc lib_qualified_rel {symbol} {
  set best {}; set bestlen -1
  foreach pair [library_list] {
    set lname [lindex $pair 0]; set lpath [lindex $pair 1]
    regsub {/*$} $lpath {/} lpath
    set pl [string length $lpath]
    if {[string equal -length $pl $lpath $symbol]} {
      set rest [string range $symbol $pl end]
      if {[regexp {^([^/]+)/symbol/([^/]+)$} $rest -> cell file]} {
        if {[file rootname $file] eq $cell && $pl > $bestlen} {
          set best "$lname/$cell"; set bestlen $pl
        }
      }
    }
  }
  return $best
}

# --- Phase 7b: mutation backend (Library Manager right-click context menu) ---
# Filesystem operations behind copy / rename / delete / new on the Library ->
# Cell -> View tree. Model (mirrors the read side above):
#   library = directory; cell = subdir holding view dirs (nested layout) OR
#   <cell>.{sym,sch} files directly in the library dir (legacy flat layout);
#   view   = <cell>/<view>/<cell>.<ext> (nested) or the flat file itself
#            (symbol -> .sym, schematic -> .sch).
# Each proc throws a Tcl error with a human-readable message on failure and
# returns "" on success, so GUI callers can `catch` and show the message.
# DELETES ARE RECOVERABLE: the target moves to <libpath>/.xschem_trash/.

# Classify a cell: "" (no such cell) | "nested" | "flat". Nested wins if both.
proc library_cell_layout {lib cell} {
  set lp [library_resolve $lib]
  if {$lp eq {}} { return {} }
  set cd [file join $lp $cell]
  if {[file isdirectory $cd] &&
      [llength [glob -nocomplain [file join $cd * $cell.*]]] > 0} { return nested }
  if {[file isfile [file join $lp $cell.sym]] ||
      [file isfile [file join $lp $cell.sch]]} { return flat }
  return {}
}

# The library's recoverable-delete directory.
proc library_trash_dir {libpath} { return [file join $libpath .xschem_trash] }

# Move $src (an absolute file or dir inside the library) into the library trash,
# uniquifying the basename so repeated deletes never collide. Returns the dest.
proc library_trash_move {libpath src} {
  set td [library_trash_dir $libpath]
  file mkdir $td
  set dst [file join $td [file tail $src]]
  set n 1
  while {[file exists $dst]} { set dst [file join $td "[file tail $src].$n"]; incr n }
  file rename -- $src $dst
  return $dst
}

# Delete a whole cell (all its views) -> trash.
proc library_delete_cell {lib cell} {
  set lp [library_resolve $lib]
  if {$lp eq {}} { error "no such library: $lib" }
  switch -- [library_cell_layout $lib $cell] {
    nested { library_trash_move $lp [file join $lp $cell] }
    flat {
      foreach ext {sym sch} {
        set f [file join $lp $cell.$ext]
        if {[file isfile $f]} { library_trash_move $lp $f }
      }
    }
    default { error "no such cell: $lib/$cell" }
  }
  return ""
}

# Delete a single view of a cell -> trash. The cell (and its other views) stays.
proc library_delete_view {lib cell view} {
  set lp [library_resolve $lib]
  if {$lp eq {}} { error "no such library: $lib" }
  switch -- [library_cell_layout $lib $cell] {
    nested {
      set vd [file join $lp $cell $view]
      if {![file isdirectory $vd]} { error "no $view view for $lib/$cell" }
      library_trash_move $lp $vd
    }
    flat {
      set f [file join $lp $cell.[expr {$view eq "schematic" ? "sch" : "sym"}]]
      if {![file isfile $f]} { error "no $view view for $lib/$cell" }
      library_trash_move $lp $f
    }
    default { error "no such cell: $lib/$cell" }
  }
  return ""
}

# Copy a cell (optionally into another library). The destination must not exist.
# The source layout is preserved; in the nested case each view's <srccell>.<ext>
# datafile is renamed to <dstcell>.<ext>.
proc library_copy_cell {srclib srccell dstlib dstcell} {
  set slp [library_resolve $srclib]
  set dlp [library_resolve $dstlib]
  if {$slp eq {}} { error "no such library: $srclib" }
  if {$dlp eq {}} { error "no such library: $dstlib" }
  set layout [library_cell_layout $srclib $srccell]
  if {$layout eq {}} { error "no such cell: $srclib/$srccell" }
  if {[library_cell_layout $dstlib $dstcell] ne {}} { error "cell already exists: $dstlib/$dstcell" }
  if {$layout eq "nested"} {
    set sd [file join $slp $srccell]
    set dd [file join $dlp $dstcell]
    file mkdir $dd
    foreach vd [glob -nocomplain -type d [file join $sd *]] {
      set odir [file join $dd [file tail $vd]]
      file mkdir $odir
      foreach f [glob -nocomplain [file join $vd *]] {
        set tail [file tail $f]
        if {[file rootname $tail] eq $srccell} { set tail "$dstcell[file extension $tail]" }
        file copy -- $f [file join $odir $tail]
      }
    }
  } else {
    foreach ext {sym sch} {
      set f [file join $slp $srccell.$ext]
      if {[file isfile $f]} { file copy -- $f [file join $dlp $dstcell.$ext] }
    }
  }
  return ""
}

# Rename a cell. Same library => in-place rename (atomic where possible);
# different library => move (copy into dest, then trash the source). The
# destination must not already exist.
proc library_rename_cell {srclib srccell dstlib dstcell} {
  set slp [library_resolve $srclib]
  if {$slp eq {}} { error "no such library: $srclib" }
  if {[library_cell_layout $srclib $srccell] eq {}} { error "no such cell: $srclib/$srccell" }
  if {$srclib eq $dstlib && $srccell eq $dstcell} { return "" }
  if {[library_cell_layout $dstlib $dstcell] ne {}} { error "cell already exists: $dstlib/$dstcell" }
  if {$srclib ne $dstlib} {
    library_copy_cell $srclib $srccell $dstlib $dstcell
    library_delete_cell $srclib $srccell
    return ""
  }
  switch -- [library_cell_layout $srclib $srccell] {
    nested {
      set dd [file join $slp $dstcell]
      file rename -- [file join $slp $srccell] $dd
      foreach vd [glob -nocomplain -type d [file join $dd *]] {
        foreach f [glob -nocomplain [file join $vd $srccell.*]] {
          file rename -- $f [file join $vd "$dstcell[file extension $f]"]
        }
      }
    }
    flat {
      foreach ext {sym sch} {
        set f [file join $slp $srccell.$ext]
        if {[file isfile $f]} { file rename -- $f [file join $slp $dstcell.$ext] }
      }
    }
  }
  return ""
}

# Minimal but valid empty .sch/.sym body (the 6-record header). file_version is
# kept in step with XSCHEM_FILE_VERSION in xschem.h (informational on load).
proc library_write_empty_cellfile {path} {
  set ver "unknown"
  catch {set ver [xschem get version]}
  set fp [open $path w]
  puts $fp "v {xschem version=$ver file_version=1.3}"
  foreach r {G K V S E} { puts $fp "$r \{\}" }
  close $fp
}

# Create a new, empty cell with one view (schematic by default).
proc library_new_cell {lib cell {view schematic}} {
  set lp [library_resolve $lib]
  if {$lp eq {}} { error "no such library: $lib" }
  if {$cell eq {}} { error "cell name required" }
  if {[library_cell_layout $lib $cell] ne {}} { error "cell already exists: $lib/$cell" }
  set ext [expr {$view eq "schematic" ? "sch" : "sym"}]
  set vd [file join $lp $cell $view]
  file mkdir $vd
  library_write_empty_cellfile [file join $vd "$cell.$ext"]
  return ""
}

# The first library.defs in $XSCHEM_LIBRARY_DEFS we can append to (existing &
# writable, or absent with a writable parent), or "" if none.
proc library_primary_defs_file {} {
  global XSCHEM_LIBRARY_DEFS OS
  if {![info exists XSCHEM_LIBRARY_DEFS] || $XSCHEM_LIBRARY_DEFS eq {}} { return {} }
  set sep [expr {$OS eq "Windows" ? {;} : {:}}]
  foreach f [split $XSCHEM_LIBRARY_DEFS $sep] {
    if {$f eq {}} { continue }
    if {[file isfile $f]} { if {[file writable $f]} { return $f }; continue }
    if {[file isdirectory [file dirname $f]] && [file writable [file dirname $f]]} { return $f }
  }
  return {}
}

# Create and register a new library: make $path (default <defs-dir>/<name>) and
# append "DEFINE <name> <path>" to the primary defs file (relative to the defs
# dir when possible, per the cds.lib convention).
proc library_new {name {path {}}} {
  if {$name eq {}} { error "library name required" }
  if {[library_resolve $name] ne {}} { error "library already exists: $name" }
  set defs [library_primary_defs_file]
  if {$defs eq {}} { error "no writable library.defs (set XSCHEM_LIBRARY_DEFS)" }
  set base [file dirname [file normalize $defs]]
  if {$path eq {}} { set path [file join $base $name] }
  file mkdir $path
  set np [file normalize $path]
  set store $np
  if {[string equal -length [string length "$base/"] "$base/" $np]} {
    set store [string range $np [string length "$base/"] end]
  }
  set fp [open $defs a]; puts $fp "DEFINE $name $store"; close $fp
  return ""
}

# Remove a library's DEFINE line(s) from the defs file(s) (files on disk are
# left untouched). Errors if the library is only auto-discovered (no DEFINE to
# remove — it comes from library.tag or a bare search-path dir).
proc library_unregister {name} {
  global XSCHEM_LIBRARY_DEFS OS
  set removed 0
  if {[info exists XSCHEM_LIBRARY_DEFS] && $XSCHEM_LIBRARY_DEFS ne {}} {
    set sep [expr {$OS eq "Windows" ? {;} : {:}}]
    foreach f [split $XSCHEM_LIBRARY_DEFS $sep] {
      if {$f eq {} || ![file isfile $f]} { continue }
      set fp [open $f r]; set lines [split [read $fp] \n]; close $fp
      set out {}; set hit 0
      foreach line $lines {
        if {[regexp {^\s*DEFINE\s+(\S+)\s} $line -> dn] && $dn eq $name} { set hit 1; continue }
        lappend out $line
      }
      if {$hit} {
        if {![file writable $f]} { error "library.defs not writable: $f" }
        set fp [open $f w]; puts -nonewline $fp [join $out \n]; close $fp
        set removed 1
      }
    }
  }
  if {!$removed} { error "library is auto-discovered (no DEFINE to remove): $name" }
  return ""
}
