package src

import "base:runtime"
import oc "core:sys/orca"
import "core:log"

// Orca questions
// dont know how to properly color a button different
// miss tab jumping
// is there a way to overwrite text box events? make enter not leave active state
// not really clear where name collisions are in ui boxes
// ui debugging tooling would be nice
// Mouse cursor change?
// Dear IMGui style hashing like TestButton##1 and TestButton##2

// NOTE
// tags are different to keys

// TODO
// sort tasks in mem based on state if you want
// drag tasks could be fun but not useful
// blur could be cool
// OpenGLES Support
// remember save location
// theme window
// refuse to close if unsaved changes

// TODO stylsheet
// should style colors reload based on theme changes?
// add inheritance
// size kind based on window would be good for floatys
// how to pick fonts?
// EM or REM sizes?

ed: Editor

main :: proc() {
  editor_init(&ed)
  editor_load(&ed)
  editor_example(&ed)
  }

  @(fini)
  destroy_all :: proc() {
  editor := &ed
  editor_destroy(editor)
  }

  @(export)
  oc_on_resize :: proc "c" (width, height: u32) {
  ed.window_size = {f32(width), f32(height)}
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

  editor_update(editor)
  editor_render(editor, scratch)
  oc.ui_draw()

  oc.canvas_render(editor.renderer, editor.canvas, editor.surface)
  oc.canvas_present(editor.renderer, editor.surface)
  }

  oc_deselect_textbox :: proc(frame: ^oc.ui_box, text: ^oc.ui_box) {
  oc.ui_box_deactivate(frame)
  oc.ui_box_deactivate(text)
  }

  oc_select_textbox :: proc(ui: ^oc.ui_context, frame: ^oc.ui_box, textBox: ^oc.ui_box) {
  if !oc.ui_box_active(frame)
  {
  oc.ui_box_activate(frame)
  oc.ui_box_activate(textBox)

  //NOTE: focus
  ui.focus = frame
  ui.editFirstDisplayedChar = 0
  ui.editCursor = 0
  ui.editMark = 0
  }

  ui.editCursorBlinkStart = ui.frameTime
  }

  oc_open_cmp :: proc(path: string, rights: oc.file_access, flags: oc.file_open_flags) -> (cmp: oc.io_cmp) {
  req := oc.io_req {
  op = .OPEN_AT,
  open = {
  rights,
  flags,
  },
  buffer = raw_data(path),
  size = u64(len(path))
  }

  return oc.io_wait_single_req(&req)
  }

  @(export)
  oc_on_key_down :: proc "c" (scancode: oc.scan_code, key: oc.key_code) {
  context = runtime.default_context()
  context.logger = ed.logger
  editor := &ed
  mods := editor.ui_context.input.keyboard.mods

  #partial switch key {

  }

  for call in editor.shortcuts {
  if call.mods == mods && call.key == key {
  call.call(editor)
  return
  }
  }
  }

  @(export)
  oc_on_mouse_move :: proc "c" (x, y, dx, dy: f32) {
  ed.mouse_position = { x, y }
  }

  @(export)
  oc_on_raw_event :: proc "c" (event: ^oc.event) {
  scratch := oc.scratch_begin()
  defer oc.scratch_end(scratch)

  // ui := &core.ui_context
  // oc.input_process_event(&ui.frameArena, &ui.input, event)

  oc.ui_process_event(event)

  // core.last_input = core.input
  // oc.input_process_event(scratch.arena, &core.input, event)

  // keyboard_state := &core.input.keyboard
  // last_keyboard_state := &core.last_input.keyboard
  // keys := keyboard_state.keys

  // if key_pressed(keyboard_state, last_keyboard_state, .ENTER) {
  // 	context = runtime.default_context()
  // 	grid_init(core.game.grid)
  // }

  // core.game.spawn_speedup =
}
