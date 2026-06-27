#!/bin/bash
export DISPLAY=:0
XSCHEM="/home/nithin/AI_Projects/Open_EDA_Tools/xschem-fluid/src/xschem"

run_test() {
    local type=$1
    local test=$2
    local output=""
    if [ "$type" = "PIPE" ]; then
        output=$($XSCHEM --pipe -q --nolog --script $test 2>&1)
    else
        output=$($XSCHEM --pipe -q --logdir $(mktemp -d) --script $test 2>&1)
    fi
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        echo "FAIL_PRINT|$test"
        echo "$output"
        echo "FAIL_END"
    elif echo "$output" | grep -q "RESULT: ALL PASS"; then
        echo "PASS|$test"
    else
        echo "FAIL_PRINT|$test"
        echo "$output"
        echo "FAIL_END"
    fi
}

echo "GROUP A: nhse editor tests"
run_test PIPE tests/headless/test_nh_editor_table.tcl
run_test PIPE tests/headless/test_nh_editor_buttons.tcl
run_test PIPE tests/headless/test_nh_editor_cells.tcl
run_test PIPE tests/headless/test_nh_editor_staged.tcl
run_test PIPE tests/headless/test_nh_editor_rowops.tcl
run_test PIPE tests/headless/test_nh_editor_free.tcl
run_test PIPE tests/headless/test_nh_editor_flush_scroll.tcl
run_test PIPE tests/headless/test_nh_editor_align.tcl
run_test PIPE tests/headless/test_nh_editor_load.tcl
run_test PIPE tests/headless/test_nh_editor_preview.tcl
run_test PIPE tests/headless/test_nh_editor_discover.tcl
run_test PIPE tests/headless/test_nh_editor_persist.tcl
run_test PIPE tests/headless/test_nh_anim_rearm.tcl

echo "GROUP B: CIW tests"
run_test LOGDIR tests/headless/test_ciw.tcl
run_test LOGDIR tests/headless/test_ciw_autocomplete.tcl
run_test LOGDIR tests/headless/test_ciw_puts_capture.tcl

echo "GROUP C: multi-window / binding tests"
run_test PIPE tests/headless/test_multi_window.tcl
run_test PIPE tests/headless/test_clone_canvas_bindings.tcl
run_test PIPE tests/headless/test_window_switch_bogus_enter.tcl
run_test PIPE tests/headless/test_close_window_restores_prev_tab.tcl
run_test PIPE tests/headless/test_accelerators.tcl
run_test PIPE tests/headless/test_binding_precedence.tcl
run_test PIPE tests/headless/test_bindings_file.tcl
run_test PIPE tests/headless/test_mouse_bindings.tcl

echo "GROUP D: library manager tests"
run_test PIPE tests/headless/test_lib_manager_gui.tcl
run_test PIPE tests/headless/test_lib_manager_launch.tcl
run_test PIPE tests/headless/test_lib_manager_bold.tcl
run_test PIPE tests/headless/test_lib_manager_ctx.tcl
run_test PIPE tests/headless/test_lib_manager_locate.tcl
run_test PIPE tests/headless/test_libmgr_refresh_reentrancy.tcl

echo "GROUP E: remaining PIPE_TESTS"
run_test PIPE tests/headless/test_palette.tcl
run_test PIPE tests/headless/test_keybindings_help.tcl
run_test PIPE tests/headless/test_undo_selection.tcl
run_test PIPE tests/headless/test_geometry_sanity.tcl
run_test PIPE tests/headless/test_hover_highlight.tcl
run_test PIPE tests/headless/test_hover_selection_repair.tcl
run_test PIPE tests/headless/test_nolog.tcl
run_test PIPE tests/headless/test_untitled_reuse.tcl
run_test PIPE tests/headless/test_pristine_untitled_basename.tcl
run_test PIPE tests/headless/test_wire_vertex_grab.tcl
run_test PIPE tests/headless/test_wire_complete_with_selection.tcl
run_test PIPE tests/headless/test_context_menu_descend_edit.tcl
run_test PIPE tests/headless/test_descend_views.tcl
run_test PIPE tests/headless/test_cadence_drag.tcl
