package src

import "core:fmt"
import "core:log"
import "core:math"
import "core:strings"
import oc "core:sys/orca"
import "qwe"
import "uuid"

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

	editor_render_tasks(editor)
}

editor_render_tasks :: proc(editor: ^Editor) {
	ui := editor.ui

	qwe.element_margin(ui, 0)
	qwe.element_fill(ui)
	panel_begin(ui, "tasks all", {.Background})
	defer panel_end(ui)

	offset := editor.camera.offset
	offset.x = f32(int(offset.x))
	offset.y = f32(int(offset.y))
	zoom_small := editor.camera.zoom
	zoom_small = max(zoom_small, 0.1)
	editor.font_size *= zoom_small
	editor.font_size = f32(int(editor.font_size))
	oc.set_font_size(editor.font_size)

	cellx_size := int(150 * zoom_small)
	celly_size := int(150 * zoom_small)
	for y in 0 ..< len(editor.tags) + 1 {
		yy := (y + 1) * celly_size
		oc.move_to(f32(cellx_size) + offset.x, f32(yy) + offset.y)
		oc.line_to(f32(cellx_size + cellx_size * len(editor.states)) + offset.x, f32(yy) + offset.y)
		oc.set_width(2)
		color_set(editor.theme.border)
		oc.stroke()
	}
	for x in 0 ..< len(editor.states) + 1 {
		xx := (x + 1) * cellx_size
		oc.move_to(f32(xx) + offset.x, f32(celly_size) + offset.y)
		oc.line_to(f32(xx) + offset.x, f32(celly_size + celly_size * len(editor.tags)) + offset.y)
		oc.set_width(2)
		color_set(editor.theme.border)
		oc.stroke()
	}

	task_matches := make([dynamic]^Task, 0, 128, context.temp_allocator)
	cell_hovered: bool
	cell_index: int
	editor.task_hovering = false

	task_step_count := 4
	task_size := int(cellx_size / task_step_count)

	// tags
	editor.write_mode = .Task
	task_drag_started: ^Task
	for tag, y in editor.tags {
		tag := header_find_id(editor.tags[:], tag.id)
		xx := int(offset.x)
		yy := int(offset.y) + (y + 1) * celly_size
		to := qwe.Rect{xx, xx + cellx_size, yy, yy + celly_size}
		qwe.element_set_bounds(ui, to)
		qwe.element_text_align(ui, .End, .Center)
		tag_label := label_highlight(ui, tag.description, editor.write_hover.y == tag.id)
		tag.bounds = tag_label.bounds
		if qwe.drag_started(ui, tag_label) {
			qwe.drag_set(ui, "Header_Tag", tag^)
			qwe.set_focus(ui, 0)
		}
		if qwe.overlapping(ui, tag_label) {
			drop := Header_Drop {
				index = y,
			}
			qwe.drop_set(ui, "Header_Tag", drop)
		}

		// states
		for state, x in editor.states {
			state := header_find_id(editor.states[:], state.id)
			if y == 0 {
				xx := int(offset.x) + (x + 1) * cellx_size
				yy := int(offset.y)
				to := qwe.Rect{xx, xx + cellx_size, yy, yy + celly_size}
				qwe.element_set_bounds(ui, to)
				qwe.element_text_align(ui, .Center, .End)
				state_label := label_highlight(ui, state.description, editor.write_hover.x == state.id)
				state.bounds = state_label.bounds

				if qwe.drag_started(ui, state_label) {
					qwe.drag_set(ui, "Header_State", state^)
					qwe.set_focus(ui, 0)
				}
				if qwe.overlapping(ui, state_label) {
					drop := Header_Drop {
						index = x,
					}
					qwe.drop_set(ui, "Header_State", drop)
				}
			}

			tasks_find_match_ids(&task_matches, editor.tasks[:], state.id, tag.id)

			// cell
			xx := int(offset.x) + (x + 1) * cellx_size
			yy := int(offset.y) + (y + 1) * celly_size
			to := qwe.Rect{xx, xx + cellx_size, yy, yy + celly_size}
			qwe.element_set_bounds(ui, to)
			text_display := fmt.tprintf("%d", len(task_matches))
			text_hash := fmt.tprintf("%d", cell_index)
			qwe.element_text_align(ui, .Center, .Center)
			sub := task_panel_begin(ui, text_hash)
			defer task_panel_end(ui, text_display)
			if qwe.is_hovered(ui, sub) {
				editor.write_hover = {state.id, tag.id}
				cell_hovered = true
			}

			if qwe.overlapping(ui, sub) {
				drop := Cell_Drop {
					state = state.id,
					tag   = tag.id,
				}
				qwe.drop_set(ui, "Cell", drop)
			}

			defer {
				vscrollbar(ui, "testscroll")
			}

			// draw tasks
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
				if qwe.drag_started(ui, task_element) {
					qwe.drag_set(ui, "Task", task^)
					task_drag_started = task
					qwe.set_focus(ui, 0)
				}
				task_x += 1
			}

			cell_index += 1
		}
	}

	if task_drag_started != nil {
		editor_task_remove(editor, task_drag_started)
	}

	// tag add section
	{
		xx := int(offset.x)
		width := len(editor.states) * cellx_size
		if len(editor.states) > 0 {
			xx += cellx_size
		} else {
			width += cellx_size
		}
		yy := int(offset.y) + (len(editor.tags) + 1) * celly_size
		to := qwe.Rect{xx, xx + width, yy, yy + celly_size}
		qwe.element_set_bounds(ui, to)
		qwe.element_text_align(ui, .Center, .Center)
		element := label_hover_range(ui, "tag")
		if qwe.is_hovered(ui, element) {
			editor.write_mode = .Tag
		}
	}

	// state add section
	{
		yy := int(offset.y)
		height := len(editor.tags) * celly_size
		if len(editor.tags) > 0 {
			yy += celly_size
		} else {
			height += celly_size
		}
		xx := int(offset.x) + (len(editor.states) + 1) * cellx_size
		to := qwe.Rect{xx, xx + cellx_size, yy, yy + height}
		qwe.element_set_bounds(ui, to)
		qwe.element_text_align(ui, .Center, .Center)
		element := label_hover_range(ui, "state")
		if qwe.is_hovered(ui, element) {
			editor.write_mode = .State
		}
	}

	if !cell_hovered {
		editor.write_hover = {}
	}

	switch ui.dragndrop.drag_type {
	case "Task":
		task := cast(^Task)qwe.drag_root(ui)
		if task != nil {
			to := qwe.Rect {
				ui.mouse_position.x - task_size / 2,
				ui.mouse_position.x + task_size / 2,
				ui.mouse_position.y - task_size / 2,
				ui.mouse_position.y + task_size / 2,
			}
			qwe.element_set_bounds(ui, to)
			task_small_drag(ui, string(task.id[:]), "taskhover")
		}

	case "Header_Tag", "Header_State":
		header := cast(^Header)qwe.drag_root(ui)
		if header != nil {
			x, y, w, h := qwe.rect_flat(header.bounds)
			color_set(editor.theme.border_highlight)
			oc.set_width(editor.theme.border_highlight_width)
			oc.rectangle_stroke(x, y, w, h)
		}
	}

	// hover info the full text
	if editor.task_hover_unit > 0 {
		editor_font_size_reset(editor)
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
			label_alpha(ui, task.content, editor.task_hover_unit * 2, editor.task_panning)
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
