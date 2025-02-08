package src

import "core:fmt"
import "core:log"
import "core:math"
import "core:strings"
import oc "core:sys/orca"
import "qwe"
import "uuid"

TASK_MIN_SIZE :: 100
TASK_GAP :: 2
TASK_TEXT_SIZE :: 22

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

editor_render :: proc(editor: ^Editor, scratch: oc.arena_scope) {
	oc.set_font(editor.font_regular)
	oc.set_font_size(editor.font_size)

	ui := editor.ui

	qwe.element_margin(ui, 0)
	qwe.begin(ui)
	defer qwe.end(ui, 0.05)

	{
		qwe.element_cut(ui, .Top, 50)
		panel := panel_begin(ui, "top", {.Background, .Border_Bottom})
		defer panel_end(ui)

		qwe.element_fill(ui)
		qwe.element_text_yalign(ui, .Center)
		write := fmt.tprintf("%s##builder", strings.to_string(editor.write))
		write_alpha := editor_write_time_unit(editor)
		label_underlined(ui, write, .Center, write_alpha)
	}

	CELLX_SIZE :: 150
	CELLY_SIZE :: 150
	for y in 0 ..< len(editor.tags) + 1 {
		yy := (y + 1) * CELLY_SIZE
		oc.move_to(CELLX_SIZE, f32(yy))
		oc.line_to(f32(CELLX_SIZE + CELLX_SIZE * len(editor.states)), f32(yy))
		oc.set_width(2)
		oc.set_color(oc.color_rgba(0.5, 0.5, 0.5, 1))
		oc.stroke()
	}
	for x in 0 ..< len(editor.states) + 1 {
		xx := (x + 1) * CELLX_SIZE
		oc.move_to(f32(xx), CELLY_SIZE)
		oc.line_to(f32(xx), f32(CELLY_SIZE + CELLY_SIZE * len(editor.tags)))
		oc.set_width(2)
		oc.set_color(oc.color_rgba(0.5, 0.5, 0.5, 1))
		oc.stroke()
	}

	task_matches := make([dynamic]^Task, 0, 128, context.temp_allocator)
	cell_hovered: bool
	cell_index: int
	editor.task_hovering = false
	drag_end := !editor.task_dragging && editor.task_drag != {}
	// tags
	for tag, y in editor.tags {
		xx := 0
		yy := (y + 1) * CELLY_SIZE
		to := qwe.Rect{xx, xx + CELLX_SIZE, yy, yy + CELLY_SIZE}
		qwe.element_set_bounds_relative(ui, to)
		qwe.element_text_align(ui, .End, .Center)
		label_highlight(ui, tag.description, editor.write_hover.y == tag.id)

		// states
		for state, x in editor.states {
			if y == 0 {
				xx := (x + 1) * CELLX_SIZE
				yy := 0
				to := qwe.Rect{xx, xx + CELLX_SIZE, yy, yy + CELLY_SIZE}
				qwe.element_set_bounds_relative(ui, to)
				qwe.element_text_align(ui, .Center, .End)
				label_highlight(ui, state.description, editor.write_hover.x == state.id)
			}

			tasks_find_match_ids(&task_matches, editor.tasks[:], state.id, tag.id)

			// cell
			xx := (x + 1) * CELLX_SIZE
			yy := (y + 1) * CELLY_SIZE
			to := qwe.Rect{xx, xx + CELLX_SIZE, yy, yy + CELLY_SIZE}
			qwe.element_set_bounds_relative(ui, to)
			text_display := fmt.tprintf("%d", len(task_matches))
			text_hash := fmt.tprintf("%d", cell_index)
			qwe.element_text_align(ui, .Center, .Center)
			sub := task_panel_begin(ui, text_hash)
			defer task_panel_end(ui, text_display)
			if qwe.is_hovered(ui, sub) {
				editor.write_hover = {state.id, tag.id}
				cell_hovered = true

				if drag_end {
					task := tasks_find_match_id(editor.tasks[:], editor.task_hovered)
					if task != nil {
						task.state = state.id
						task.tag = tag.id
					}
				}
			}

			// draw tasks
			task_step_count := 10
			task_size := CELLX_SIZE / task_step_count
			task_x: int
			task_y: int
			for task, task_index in task_matches {
				if task_x >= task_step_count {
					task_x = 0
					task_y += 1
				}

				xx := (task_x) * task_size
				yy := (task_y) * task_size
				to := qwe.Rect{xx, xx + task_size, yy, yy + task_size}
				qwe.element_set_bounds_relative(ui, to)
				task_element := task_small(ui, task)
				if qwe.is_hovered(ui, task_element) {
					editor.task_hovered = task.id
					editor.task_hovering = true
				}
				if qwe.dragging(ui, task_element) {
					editor.task_drag = task.id
					editor.task_dragging = true
				}
				if qwe.was_focused(ui, task_element) {
					editor.task_dragging = false
				}
				task_x += 1
			}

			cell_index += 1
		}
	}

	if drag_end {
		editor.task_drag = {}
	}

	if !cell_hovered {
		editor.write_hover = {}
	}

	if editor.task_hover_unit > 0 {
		width := 300
		height := 50
		yoffset := 10
		to := qwe.Rect {
			ui.mouse_position.x - width / 2,
			ui.mouse_position.x + width / 2,
			ui.mouse_position.y - height - yoffset,
			ui.mouse_position.y - yoffset,
		}
		qwe.element_set_bounds(ui, to)
		panel := panel_overlay_begin(ui, "hoverinfo", editor.task_hover_unit, {})
		defer panel_end(ui)

		task := tasks_find_match_id(editor.tasks[:], editor.task_hovered)
		if task != nil {
			qwe.element_fill(ui)
			qwe.element_text_align(ui, .Center, .Center)
			label_alpha(ui, task.content, editor.task_hover_unit * 2, {})
		}
	}
}

task_header_count :: proc(tasks: []Task, state, tag: uuid.Guid) -> (result: int) {
	for task in tasks {
		if task.state == state && task.tag == tag {
			result += 1
		}
	}

	return
}

tasks_find_match_ids :: proc(fill: ^[dynamic]^Task, tasks: []Task, state, tag: uuid.Guid) {
	clear(fill)

	for &task in tasks {
		if task.state == state && task.tag == tag {
			append(fill, &task)
		}
	}
}

tasks_find_match_id :: proc(tasks: []Task, id: uuid.Guid) -> ^Task {
	for &task in tasks {
		if task.id == id {
			return &task
		}
	}

	return nil
}
