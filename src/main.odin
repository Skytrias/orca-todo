package src

import "base:runtime"
import "core:hash"
import "core:log"
import "core:strings"
import oc "core:sys/orca"
import "qwe"

// Bugs
// scroll v/h the offsets

// Orca related bugs that are crappy
// keeps crashing on file reload
// tile overload on renderer can crash the application

ed: Editor

Testing :: struct {
	temp: map[qwe.Id]qwe.Element,
}

main :: proc() {
	editor_init(&ed)
	editor_load(&ed)
	editor_example(&ed)

	context.logger = oc.create_odin_logger()

	// // other := Testing{}
	// other := new(Testing)
	// other.temp = make(map[qwe.Id]qwe.Element, 17)

	// // for i in 0 ..< 50 {
	// // 	temp[qwe.Id(i)] = {}
	// // }

	// b: [1]u8
	// for i in 0 ..< 10 {
	// 	b[0] = u8(i)
	// 	h := hash.fnv32(b[:])
	// 	log.info("INS", h, len(other.temp), cap(other.temp))

	// 	if h not_in other.temp {
	// 		other.temp[h] = {}
	// 	}

	// 	ptr := &other.temp[h]
	// 	ptr.text_label = "Hello"
	// }
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

	free_all(context.temp_allocator)

	oc.canvas_context_select(editor.canvas)
	oc.set_color_rgba(1, 1, 1, 1)
	oc.clear()

	editor_update_start(editor)
	editor_render(editor, scratch)
	editor_update_end(editor)

	oc.canvas_render(editor.renderer, editor.canvas, editor.surface)
	oc.canvas_present(editor.renderer, editor.surface)
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
