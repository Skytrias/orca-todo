package src

import "base:runtime"
import "core:log"
import "core:strings"
import oc "core:sys/orca"
import "qwe"

ed: Editor

main :: proc() {
	editor_init(&ed)
	editor_load(&ed)
	// editor_example(&ed)
}

@(fini)
destroy_all :: proc() {
	editor := &ed
	editor_destroy(editor)
}

@(export)
oc_on_resize :: proc "c" (width, height: u32) {
	ed.window_size = {f32(width), f32(height)}
	context = runtime.default_context()
	qwe.input_window_size(ed.ui, int(ed.window_size.x), int(ed.window_size.y))
}

@(export)
oc_on_frame_refresh :: proc "c" () {
	editor := &ed
	context = runtime.default_context()
	context.logger = editor.logger

	scratch := oc.scratch_begin()
	defer oc.scratch_end(scratch)

	oc.canvas_context_select(editor.canvas)
	oc.set_color_rgba(1, 1, 1, 1)
	oc.clear()

	editor_update_start(editor)
	editor_render(editor, scratch)
	editor_update_end(editor)

	oc.canvas_render(editor.renderer, editor.canvas, editor.surface)
	oc.canvas_present(editor.renderer, editor.surface)
}

oc_open_cmp :: proc(
	path: string,
	rights: oc.file_access,
	flags: oc.file_open_flags,
) -> (
	cmp: oc.io_cmp,
) {
	req := oc.io_req {
		op     = .OPEN_AT,
		open   = {rights, flags},
		buffer = raw_data(path),
		size   = u64(len(path)),
	}

	return oc.io_wait_single_req(&req)
}

@(export)
oc_on_mouse_move :: proc "c" (x, y, dx, dy: f32) {
	ed.mouse_position = {x, y}
}

@(export)
oc_on_raw_event :: proc "c" (event: ^oc.event) {
	scratch := oc.scratch_begin()
	defer oc.scratch_end(scratch)

	context = runtime.default_context()
	editor := &ed
	context.logger = editor.logger

	// oc.ui_process_event(event)
	oc.input_process_event(scratch.arena, &editor.input, event)
	defer oc.input_next_frame(&editor.input)

	if oc.clipboard_pasted(&editor.input) {
		text := oc.clipboard_pasted_text(&editor.input)

		if text != "" {
			write := &editor.write
			strings.write_string(write, text)
		}
	}

	mods := oc.key_mods(&editor.input)

	#partial switch event.type {
	case .KEYBOARD_KEY:
		// log.info("EV", event.key.keyCode, event.key.mods)
		pressed := event.key.action == .PRESS
		mods := event.key.mods

		#partial switch event.key.keyCode {
		case .ESCAPE:
			if pressed {
				editor_escape(editor)
			}

		case .TAB:
			if pressed {
				theme_set(editor, !editor.theme_white)
			}

		case .BACKSPACE:
			if pressed || event.key.action == .REPEAT {
				editor.write_time = 0
				builder := &editor.write
				if .MAIN_MODIFIER in event.key.mods {
					strings.builder_reset(builder)
				} else {
					strings.pop_rune(builder)
				}
			}

		case .S:
			if pressed {
				if .CMD in mods && .SHIFT in mods {
					editor_save_to(editor)
				} else if .CMD in mods {
					editor_save(editor)
				}
			}

		case .O:
			if pressed {
				if .CMD in mods && .SHIFT in mods {
					editor_load_from(editor)
				} else if .CMD in mods {
					editor_load(editor)
				}
			}

		case .ENTER:
			if pressed {
				editor_insert_task(editor)
			}
		}

	case .KEYBOARD_CHAR:
		builder := &editor.write
		strings.write_rune(builder, rune(event.character.codepoint))
		editor.write_time = 0

	case .MOUSE_MOVE:
		qwe.input_mouse_move(ed.ui, int(event.mouse.x), int(event.mouse.y))

	case .MOUSE_WHEEL:
		if .CMD in mods || .MAIN_MODIFIER in mods {
			camera_zoom_at(editor, &editor.camera, event.mouse.deltaY / 10)
		} else {
			qwe.input_scroll(ed.ui, int(event.mouse.deltaX), int(event.mouse.deltaY))
		}

	case .MOUSE_BUTTON:
		down := event.key.action == .PRESS

		if down {
			if event.key.button == .LEFT {
				qwe.input_mouse_down(ed.ui, ed.ui.mouse_position.x, ed.ui.mouse_position.y, .Left)

				if .CMD in mods || .MAIN_MODIFIER in mods {
					editor.camera.dragging = true
					editor.camera.drag_start = editor.input.mouse.pos
				}
			} else if event.key.button == .RIGHT {
				qwe.input_mouse_down(ed.ui, ed.ui.mouse_position.x, ed.ui.mouse_position.y, .Right)
			}
		} else {
			if event.key.button == .LEFT {
				qwe.input_mouse_up(ed.ui, ed.ui.mouse_position.x, ed.ui.mouse_position.y, .Left)
				editor.camera.dragging = false
			} else if event.key.button == .RIGHT {
				qwe.input_mouse_up(ed.ui, ed.ui.mouse_position.x, ed.ui.mouse_position.y, .Right)
			}
		}
	}

}
