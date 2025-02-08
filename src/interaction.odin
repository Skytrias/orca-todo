package src

import "core:fmt"
import "core:log"
import "core:math"
import "core:strings"
import oc "core:sys/orca"
import "qwe"

TASK_MIN_SIZE :: 100
TASK_GAP :: 2
TASK_TEXT_SIZE :: 22

// editor_render :: proc(editor: ^Editor, scratch: oc.arena_scope) {
// 	oc.set_font(editor.font_regular)
// 	oc.set_font_size(editor.font_size)

// 	ui := editor.ui

// 	qwe.element_margin(ui, 0)
// 	qwe.begin(ui)
// 	defer qwe.end(ui, 0.05)

// 	{
// 		qwe.element_cut(ui, .Left, 200)
// 		sidebar := panel_begin(ui, "sidebar", {.Background, .Clip_Outer, .Border_Right})
// 		defer panel_end(ui)

// 		// defer vscrollbar(ui, "vscroll")

// 		editor_fetch_states(editor)
// 		editor_fetch_tags(editor)
// 		filter_index: int

// 		{
// 			qwe.element_margin(ui, 10)
// 			qwe.element_pct(ui, .Top, 50)
// 			panel := panel_begin(ui, "sub1", {.Border_Bottom})
// 			defer panel_end(ui)

// 			defer vscrollbar(ui, "vscroll")

// 			qwe.element_cut(ui, .Top, 40)
// 			label_aligned(ui, "States", .Center)
// 			panel.cut_gap = 5
// 			for key, value in editor.all_states {
// 				selected := editor.filters_state[key]
// 				filter_hash := fmt.tprintf("state%d", filter_index)
// 				value_text := fmt.tprintf("%d", value)
// 				element := bstate_button(ui, key, value_text, filter_hash, selected, false)

// 				if qwe.left_clicked(ui, element) {
// 					editor.filters_state[key] = !selected
// 				}

// 				if qwe.right_clicked(ui, element) {
// 					editor_select_or_solo_filter(&editor.filters_state, key)
// 				}

// 				filter_index += 1
// 			}
// 		}

// 		{
// 			qwe.element_margin(ui, 10)
// 			qwe.element_fill(ui)
// 			panel := panel_begin(ui, "sub2", {})
// 			defer panel_end(ui)

// 			defer vscrollbar(ui, "vscroll")

// 			qwe.element_cut(ui, .Top, 40)
// 			label_aligned(ui, "Tags", .Center)
// 			panel.cut_gap = 5
// 			for key, value in editor.all_tags {
// 				selected := editor.filters_tag[key]
// 				filter_hash := fmt.tprintf("state%d", filter_index)
// 				value_text := fmt.tprintf("%d", value)
// 				element := bstate_button(ui, key, value_text, filter_hash, selected, true)

// 				if qwe.left_clicked(ui, element) {
// 					editor.filters_tag[key] = !selected
// 				}

// 				if qwe.right_clicked(ui, element) {
// 					editor_select_or_solo_filter(&editor.filters_tag, key)
// 				}
// 				filter_index += 1
// 			}
// 		}

// 		// qwe.element_cut(ui, .Bottom, 40)
// 		// if button(ui, "RNG") {
// 		// 	if editor.filter_single == nil {
// 		// 		editor_random_pick(editor)
// 		// 	} else {
// 		// 		editor.filter_single = nil
// 		// 	}
// 		// }
// 	}

// 	// Text display
// 	{
// 		qwe.element_cut(ui, .Top, 50)
// 		panel_begin(ui, "text display", {.Background, .Border_Bottom})
// 		defer panel_end(ui)

// 		qwe.element_fill(ui)
// 		label_text := fmt.tprintf("Task: %s##text_display", editor.hovered.text)
// 		task_text_display(ui, label_text, editor.hovered.current)
// 	}

// 	// text writing
// 	{
// 		qwe.element_margin(ui, 5)
// 		qwe.element_cut(ui, .Bottom, 50)
// 		panel_begin(ui, "write", {.Background, .Border_Top})
// 		defer panel_end(ui)

// 		qwe.element_cut(ui, .Left, 100)
// 		label_names := [3]string{"Task", "State", "Tag"}
// 		if button(ui, label_names[editor.write_cycle], {}) {
// 			editor.write_cycle = (editor.write_cycle + 1) % 3
// 		}

// 		qwe.element_fill(ui)
// 		builder := editor_write_cycle_builder(editor)
// 		write := fmt.tprintf("%s##builder", strings.to_string(builder^))
// 		write_alpha := editor_write_time_unit(editor)
// 		label_underlined(ui, write, .Center, write_alpha)
// 	}

// 	{
// 		qwe.element_fill(ui)
// 		qwe.element_margin(ui, 10)
// 		panel := panel_begin(ui, "inner", {.Background})
// 		defer panel_end(ui)

// 		// defer vscrollbar(ui, "vscroll")

// 		panel_width := panel.layout_start.r - panel.layout_start.l
// 		task_spacing := 5
// 		task_iter_count, task_size := get_task_iter_count(
// 			TASK_MIN_SIZE,
// 			f32(panel_width),
// 			f32(task_spacing),
// 		)

// 		tasks := editor_filtered_tasks(editor)
// 		x, y: int
// 		editor.hovered.direction = -1
// 		for task in tasks {
// 			if x == task_iter_count {
// 				x = 0
// 				y += 1
// 			}

// 			task_x := x * int(task_size) + x * task_spacing
// 			task_y := y * int(task_size) + y * task_spacing
// 			task_rect := qwe.Rect{task_x, task_x + int(task_size), task_y, task_y + int(task_size)}

// 			qwe.element_margin(ui, 0)
// 			qwe.element_gap(ui, 0)
// 			qwe.element_set_bounds_relative(ui, task_rect)
// 			task_panel := task_panel_begin(ui, task)
// 			defer task_panel_end(ui, task)

// 			if qwe.is_hovered(ui, task_panel) {
// 				editor.hovered.text = task.content
// 				editor.hovered.direction = 1
// 			}

// 			if qwe.right_clicked(ui, task_panel) {
// 				editor_modify_set(editor, task)
// 			}

// 			// qwe.element_cut(ui, .Top, int(task_size) / 2)
// 			// task_sub_label(ui, task.state, false)
// 			// task_sub_label(ui, task.tag, true)

// 			// bl := qwe.Rect{0, int(task_size), int(task_size) - 30, int(task_size)}
// 			// bl.t -= 4
// 			// bl.b -= 4
// 			// bl.l += 4
// 			// bl.r -= 4
// 			// qwe.element_set_bounds_relative(ui, bl)
// 			// if hover_button(ui, "DEL") {
// 			// 	editor_task_remove(editor, task)

// 			// 	if task == editor.task_modify {
// 			// 		editor.task_modify = nil
// 			// 		editor_write_reset(editor)
// 			// 	}
// 			// }

// 			x += 1
// 		}
// 	}

// 	// theme overlay
// 	if editor.show_theme {
// 		bounds := qwe.Rect{0, int(editor.window_size.x), 0, int(editor.window_size.y)}
// 		qwe.element_set_bounds(ui, bounds)
// 		qwe.element_margin(ui, 50)
// 		panel_begin(ui, "theme", {.Overlay, .Clip_Outer})
// 		defer panel_end(ui)

// 		hsva_slider(ui, &editor.theme.panel, "panel")
// 		hsva_slider(ui, &editor.theme.base, "base")
// 		hsva_slider(ui, &editor.theme.button, "button")
// 		hsva_slider(ui, &editor.theme.border, "border")
// 		hsva_slider(ui, &editor.theme.border_highlight, "border_highlight")
// 		hsva_slider(ui, &editor.theme.text1, "text1")
// 		hsva_slider(ui, &editor.theme.text2, "text2")
// 		hsva_slider(ui, &editor.theme.scroll_base, "scroll_base")
// 		hsva_slider(ui, &editor.theme.scroll_thumb, "scroll_thumb")
// 	}
// }

// calculate how many tasks can be displayed in a single row
get_task_iter_count :: proc(
	task_size: f32,
	panel_width: f32,
	spacingx: f32,
) -> (
	iter_count: int,
	final_task_size: f32,
) {
	full_width := panel_width
	suggested_count := full_width / task_size
	spacing_size := spacingx * (suggested_count - 1)
	// spacing_size := f32(0)

	iter_count_float := max((full_width - spacing_size) / task_size, 1)
	iter_count = int(iter_count_float)
	task_space := iter_count_float * task_size
	final_task_size = task_space / f32(iter_count)
	return
}

editor_render :: proc(editor: ^Editor, scratch: oc.arena_scope) {
	oc.set_font(editor.font_regular)
	oc.set_font_size(editor.font_size)

	ui := editor.ui

	qwe.element_margin(ui, 0)
	qwe.begin(ui)
	defer qwe.end(ui, 0.05)

	qwe.element_cut(ui, .Top, 50)
	button(ui, "Hello world", {})
}
