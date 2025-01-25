package src

import "base:intrinsics"
import "base:runtime"
import "core:mem"
import "core:log"
import "core:slice"
import "core:sort"
import "core:fmt"
import "core:strings"
import "core:hash"
import "core:math/rand"
import "uuid"
import "hsluv"
import oc "core:sys/orca"

MATERIAL_ICONS :: oc.unicode_range {
  0xE000,
  3000,
  }

  Editor :: struct {
  surface: oc.surface,
  renderer: oc.canvas_renderer,
  canvas: oc.canvas_context,
  font_regular: oc.font, // font global
  font_icons: oc.font,
  ui_context: oc.ui_context,
  stylesheet: Stylesheet,

  window_size: oc.vec2,
  mouse_position: oc.vec2,
  font_size: f32,
  file_filters: oc.str8_list,
  file_arena: oc.arena,

  // interactions
  show_task_menu: bool,
  show_task_modify: ^Task,
  show_task_context: ^Task,
  show_task_context_options: Context_Menu_Options,
  hovered_task_text: string,
  task_rest_space: f32,
  show_theme: bool,

  // shortcuts
  shortcuts: [dynamic]Editor_Shortcut,

  // task states
  tasks: [dynamic]Task,
  tasks_filtered: [dynamic]^Task,

  // input
  temp_content: Task_Box,
  temp_state: Task_Box,
  temp_tag: Task_Box,

  // filtering
  filters_state: map[string]bool,
  filters_tag: map[string]bool,
  filter_single: ^Task,
  all_states: map[string]int,
  all_tags: map[string]int,

  // log state
  logger: log.Logger,

  // random state
  rng: rand.Default_Random_State,
  }

  Task_Box :: struct {
  builder: strings.Builder,
  key_frame: oc.ui_key,
  key_text: oc.ui_key,
  }

  // TODO actually manage memory
  Task :: struct {
  content: string,
  state: string,
  tag: string,
  id: uuid.Guid,
  }

  Editor_Shortcut :: struct {
  group: string,
  name: string,
  hide: bool,
  key_display: string,
  key: oc.key_code,
  mods: oc.keymod_flags,
  call: proc(^Editor),
  }

  stylesheet_source := #load("../data/style.md")

  editor_init :: proc(editor: ^Editor) {
  editor.renderer = oc.canvas_renderer_create()
  editor.surface = oc.canvas_surface_create(editor.renderer)
  editor.canvas = oc.canvas_context_create()

  editor.window_size = { 1200, 800 }
  oc.window_set_title("orca todo")
  oc.window_set_size(editor.window_size)

  editor.font_size = 28

  // NOTE: This is temporary and will change soon
  // Describe wanted unicode ranges to usable for rendering
  ranges_regular := [?]oc.unicode_range {
  oc.UNICODE_BASIC_LATIN,
  oc.UNICODE_C1_CONTROLS_AND_LATIN_1_SUPPLEMENT,
  oc.UNICODE_LATIN_EXTENDED_A,
  oc.UNICODE_LATIN_EXTENDED_B,
  oc.UNICODE_SPECIALS,
  }
  ranges_material := [?]oc.unicode_range {
  MATERIAL_ICONS,
  }

  // create the font from an ttf asset that needs to be provided
  editor.font_regular = oc.font_create_from_path("Lato-Regular.ttf", u32(len(ranges_regular)), &ranges_regular[0])
  editor.font_icons = oc.font_create_from_path("MaterialSymbolsOutlined-Regular.ttf", u32(len(ranges_material)), &ranges_material[0])
  // editor.font_icons = oc.font_create_from_path("icofont.ttf", u32(len(ranges_material)), &ranges_material[0])

  editor.tasks = make([dynamic]Task, 0, 128)
  editor.tasks_filtered = make([dynamic]^Task, 0, 128)

  oc.ui_init(&editor.ui_context)

  strings.builder_init(&editor.temp_content.builder, 0, 128)
  strings.builder_init(&editor.temp_state.builder, 0, 128)
  strings.builder_init(&editor.temp_tag.builder, 0, 128)

  editor.filters_state = make(map[string]bool, 32)
  editor.filters_tag = make(map[string]bool, 32)

  editor.all_states = make(map[string]int, 32)
  editor.all_tags = make(map[string]int, 32)

  editor.logger = oc.create_odin_logger()
  context.logger = editor.logger

  editor.rng = rand.create(0)
  context.random_generator = runtime.default_random_generator(&editor.rng)

  log.info("Startup done")
  oc.arena_init(&editor.file_arena)
  oc.str8_list_push(&editor.file_arena, &editor.file_filters, "md")

  editor_shortcuts_init(editor)
  stylesheet_init(&editor.stylesheet, string(stylesheet_source), editor.ui_context.theme)
  }

  editor_destroy :: proc(editor: ^Editor) {
  editor_shortcuts_destroy(editor)
  delete(editor.tasks)
  delete(editor.temp_content.builder.buf)
  delete(editor.temp_state.builder.buf)
  delete(editor.temp_tag.builder.buf)
  delete(editor.filters_state)
  delete(editor.filters_tag)
  delete(editor.all_states)
  delete(editor.all_tags)
  }

  editor_update :: proc(editor: ^Editor) {
  for task in editor.tasks {
  if task.state not_in editor.filters_state {
  editor.filters_state[task.state] = false
  }

  if task.tag not_in editor.filters_tag {
  editor.filters_tag[task.tag] = false
  }
  }
  }

  editor_render :: proc(editor: ^Editor, scratch: oc.arena_scope) {
  editor_ui(editor, scratch)
  }

  Task_Inner_Group :: struct {
  content: [255]string,
  content_index: int,
  }

  editor_save_builder :: proc(editor: ^Editor, builder: ^strings.Builder) {
  full := make(map[string]map[string]Task_Inner_Group, 32)
  for task in editor.tasks {
  if task.tag not_in full {
  full[task.tag] = make(map[string]Task_Inner_Group, 32)
  }

  mapping := &full[task.tag]
  if task.state not_in mapping {
  mapping[task.state] = {}
  }

  group := &mapping[task.state]
  group.content[group.content_index] = task.content
  group.content_index += 1
  }

  tag_count: int

  for tag_key, tag_value in full {
  if tag_count > 0 {
  strings.write_byte(builder, '\n')
  }
  tag_count += 1
  strings.write_string(builder, "# ")
  strings.write_string(builder, tag_key)
  strings.write_byte(builder, '\n')

  for state_key, state_value in tag_value {
  for i in 0..<state_value.content_index {
  strings.write_byte(builder, '-')
  strings.write_byte(builder, ' ')
  strings.write_string(builder, "***")
  strings.write_string(builder, state_key)
  strings.write_string(builder, "***")
  strings.write_byte(builder, ' ')
  strings.write_string(builder, state_value.content[i])
  strings.write_byte(builder, '\n')
  }
  }
  }
  }

  editor_save_to :: proc(editor: ^Editor) {
  log.info("Editor Saving To...")
  defer log.info("Editor Save To Done")

  scratch := oc.scratch_begin()
  defer oc.scratch_end(scratch)

  description := oc.file_dialog_desc {
  kind = .SAVE,
  flags = { .FILES },
  title = "Save File",
  okLabel = "Oki Doki",
  }
  // filters = editor.file_filters,
  result := oc.file_open_with_dialog(scratch.arena, { .READ, .WRITE }, { .TRUNCATE, .CREATE }, &description)

  log.info("RES", result)

  if result.button == .CANCEL {
  return
  }

  builder := strings.builder_make(0, mem.Kilobyte, context.temp_allocator)
  editor_save_builder(editor, &builder)

  oc.file_write_slice(result.file, builder.buf[:])
  oc.file_close(result.file)
  }

  editor_save :: proc(editor: ^Editor) {
  log.info("Editor Saving...")
  defer log.info("Editor Save Done")

  file_path := "test.md"
  file := oc.file_open(file_path, { .READ, .WRITE }, { .TRUNCATE, .CREATE })

  builder := strings.builder_make(0, mem.Kilobyte, context.temp_allocator)
  editor_save_builder(editor, &builder)

  oc.file_write_slice(file, builder.buf[:])
  oc.file_close(file)
  }

  editor_load_from_string :: proc(editor: ^Editor, content: string) {
  clear(&editor.tasks)

  // load the content into maps again
  iter := string(content)
  temp_tag: string
  for line in strings.split_lines_iterator(&iter) {
  if len(line) == 0 {
  continue
  }

  start := line[0]

  if start == '#' {
  temp_tag = line[2:]
  } else if start == '-' {
  head, mid, tail := strings.partition(line[2:], " ")
  head_trimmed := strings.trim(head, "*")
  append(&editor.tasks, task_make(tail, head_trimmed, temp_tag))
  }
  }
  }

  editor_load_from :: proc(editor: ^Editor) {
  log.info("Editor Loading From...")
  defer log.info("Editor Load Done")

  scratch := oc.scratch_begin()
  defer oc.scratch_end(scratch)

  description := oc.file_dialog_desc {
  kind = .OPEN,
  flags = { .FILES },
  title = "Load File",
  okLabel = "Oki Doki",
  }

  result := oc.file_open_with_dialog(scratch.arena, { .READ }, { }, &description)

  log.info("RES", result)
  if result.button == .CANCEL {
  return
  }

  defer oc.file_close(result.file)
  file_size := oc.file_size(result.file)
  log.debug("FILE SIZE", file_size)
  content := make([]u8, file_size, context.temp_allocator)
  oc.file_read_slice(result.file, content)

  editor_load_from_string(editor, string(content))
  }

  editor_load :: proc(editor: ^Editor) {
  log.info("Editor Loading...")
  defer log.info("Editor Load Done")

  cmp := oc_open_cmp("test.md", { .READ }, {})
  if cmp.error != .OK {
  log.error("Load err:", cmp)
  return
  }

  defer oc.file_close(cmp.handle)
  file_size := oc.file_size(cmp.handle)
  log.debug("FILE SIZE", file_size)
  content := make([]u8, file_size, context.temp_allocator)
  oc.file_read_slice(cmp.handle, content)

  editor_load_from_string(editor, string(content))
  }

  editor_fetch_states :: proc(editor: ^Editor) {
  clear(&editor.all_states)
  for task in editor.tasks {
  if task.state != "" {
  if task.state not_in editor.all_states {
  editor.all_states[task.state] = 0
  } else {
  editor.all_states[task.state] += 1
  }
  }
  }
  }

  editor_fetch_tags :: proc(editor: ^Editor) {
  clear(&editor.all_tags)
  for task in editor.tasks {
  if task.tag != "" {
  if task.tag not_in editor.all_tags {
  editor.all_tags[task.tag] = 0
  } else {
  editor.all_tags[task.tag] += 1
  }
  }
  }
  }

  editor_filtered_tasks :: proc(editor: ^Editor) -> []^Task {
  clear(&editor.tasks_filtered)

  if editor.filter_single != nil {
  append(&editor.tasks_filtered, editor.filter_single)
  return editor.tasks_filtered[:]
  }

  for &task in &editor.tasks {
  tag_filtered := editor.filters_tag[task.tag]
  state_filtered := editor.filters_state[task.state]

  if !tag_filtered && !state_filtered {
  append(&editor.tasks_filtered, &task)
  }
  }
  return editor.tasks_filtered[:]
  }

  editor_select_or_solo_filter :: proc(filters: ^map[string]bool, current: string) {
  current_filtered := filters[current]
  if current_filtered {
  for key, value in filters {
  filters[key] = true
  }
  filters[current] = false
  return
  }

  other_selected: bool
  for key, value in filters {
  if key != current && value {
  other_selected = true
  break
  }
  }

  if other_selected {
  for key, value in filters {
  filters[key] = false
  }
  } else {
  for key, value in filters {
  filters[key] = true
  }
  }

  filters[current] = false
  }

  editor_accept_task_changes :: proc(editor: ^Editor) -> bool {
  state := strings.trim_space(strings.to_string(editor.temp_state.builder))
  tag := strings.trim_space(strings.to_string(editor.temp_tag.builder))
  content := strings.trim_space(strings.to_string(editor.temp_content.builder))

  if len(state) == 0 || len(tag) == 0 || len(content) == 0 {
  return false
  }

  if editor.show_task_modify != nil {
  task := editor.show_task_modify
  task.content = strings.clone(content)
  task.state = strings.clone(state)
  task.tag = strings.clone(tag)
  } else {
  append(&editor.tasks, task_make(strings.clone(content), strings.clone(state), strings.clone(tag)))
  }

  return true
  }

  editor_example :: proc(editor: ^Editor) {
  clear(&editor.tasks)
  append(&editor.tasks, task_make("Test1", "Backlog", "Plan1"))
  append(&editor.tasks, task_make("Test2 Test Test", "Backlog", "Plan1"))

  append(&editor.tasks, task_make("Test3", "WIP", "Plan2"))
  append(&editor.tasks, task_make("Test4", "WIP", "Plan2"))
  append(&editor.tasks, task_make("Test5", "Done", "Plan2"))
  append(&editor.tasks, task_make("Test6", "Done", "Plan2"))
  append(&editor.tasks, task_make("Test7", "Done", "Plan2"))

  append(&editor.tasks, task_make("Test8", "Done", "Plan3"))
  append(&editor.tasks, task_make("Test9", "Done", "Plan3"))
  append(&editor.tasks, task_make("Test11", "Done", "Plan3"))
  append(&editor.tasks, task_make("Test11", "Done", "Plan3"))
  append(&editor.tasks, task_make("ui_text_box_result should include *ui_box reference", "Open", "Orca"))
  append(&editor.tasks, task_make("Add UI Styling Helpers or rework masking", "Open", "Orca"))
  append(&editor.tasks, task_make("Add str8 versions of UI module calls", "Open", "Orca"))
  append(&editor.tasks, task_make("Tooltips should not appear while resizing the window", "Open", "Orca"))
  }

  editor_task_modify :: proc(editor: ^Editor, task: ^Task) {
  editor_toggle_menu(editor, task)

  strings.write_string(&editor.temp_content.builder, task.content)
  strings.write_string(&editor.temp_state.builder, task.state)
  strings.write_string(&editor.temp_tag.builder, task.tag)
  }

  editor_toggle_menu :: proc(editor: ^Editor, task: ^Task) {
  editor.show_task_menu = !editor.show_task_menu
  editor.show_task_modify = editor.show_task_menu ? task : nil

  strings.builder_reset(&editor.temp_content.builder)
  strings.builder_reset(&editor.temp_state.builder)
  strings.builder_reset(&editor.temp_tag.builder)
  }

  editor_task_clone :: proc(editor: ^Editor, task: ^Task) {
  temp := task_make(strings.clone(task.content), strings.clone(task.state), strings.clone(task.tag))
  append(&editor.tasks, temp)
  }

  editor_task_remove :: proc(editor: ^Editor, task: ^Task) {
  for &search, search_index in &editor.tasks {
  if search.id == task.id {
  log.info("TASK FOUND", string(search.id[:]), string(task.id[:]))
  ordered_remove(&editor.tasks, search_index)
  return
  }
  }
  }

  hsluv_hash_color :: proc(name: string, offset: u64, saturation, value: f32, alpha: f32) -> oc.color {
  seed := hash.fnv64a(transmute([]byte) name)
  // seed := hash.sdbm(transmute([]byte) name)
  rand.reset(u64(seed) + offset)
  h := rand.float64() * 360
  s := f64(saturation * 100)
  v := f64(value * 100)
  r, g, b := hsluv.hsluv_to_rgb(h, s, v)
  return oc.color_rgba(f32(r), f32(g), f32(b), alpha)
  }

  editor_shortcuts_init :: proc(editor: ^Editor) {
  editor.shortcuts = make([dynamic]Editor_Shortcut, 0, 64)
  append(&editor.shortcuts, Editor_Shortcut {
  group = "File",
  name = "Save",
  key_display = "S",
  key = .S,
  mods = { .CMD },
  call = editor_save,
  })
  append(&editor.shortcuts, Editor_Shortcut {
  group = "File",
  name = "Save To",
  key_display = "S",
  key = .S,
  mods = { .CMD, .SHIFT },
  call = editor_save_to,
  })
  append(&editor.shortcuts, Editor_Shortcut {
  group = "File",
  name = "Load",
  key_display = "O",
  key = .O,
  mods = { .CMD },
  call = editor_load,
  })
  append(&editor.shortcuts, Editor_Shortcut {
  group = "File",
  name = "Load From",
  key_display = "O",
  key = .O,
  mods = { .CMD, .SHIFT },
  call = editor_load_from,
  })
  append(&editor.shortcuts, Editor_Shortcut {
  group = "Commands",
  name = "Escape",
  hide = true,
  key = .ESCAPE,
  mods = {},
  call = editor_escape,
  })
  append(&editor.shortcuts, Editor_Shortcut {
  group = "Commands",
  name = "Tab Forward",
  hide = true,
  key = .TAB,
  mods = { },
  call = editor_tab_unshift,
  })
  append(&editor.shortcuts, Editor_Shortcut {
  group = "Commands",
  name = "Tab Backward",
  hide = true,
  key = .TAB,
  mods = { .SHIFT },
  call = editor_tab_shift,
  })

  // Theme
  append(&editor.shortcuts, Editor_Shortcut {
  group = "Theme",
  name = "Light",
  key_display = "2",
  key = ._2,
  mods = { .CMD },
  call = editor_theme_white,
  })
  append(&editor.shortcuts, Editor_Shortcut {
  group = "Theme",
  name = "Dark",
  key = ._3,
  key_display = "3",
  mods = { .CMD },
  call = editor_theme_black,
  })
  append(&editor.shortcuts, Editor_Shortcut {
  group = "Theme",
  name = "Show",
  key = ._1,
  key_display = "1",
  mods = { .CMD },
  call = editor_theme_toggle,
  })
  }

  editor_theme_white :: proc(editor: ^Editor) {
  oc.ui_set_theme(&oc.UI_LIGHT_THEME)
  }

  editor_theme_black :: proc(editor: ^Editor) {
  oc.ui_set_theme(&oc.UI_DARK_THEME)
  }

  editor_theme_toggle :: proc(editor: ^Editor) {
  editor.show_theme = !editor.show_theme
  }

  editor_shortcuts_destroy :: proc(editor: ^Editor) {
  delete(editor.shortcuts)
  }

  ui_deactivate_all :: proc(box: ^oc.ui_box, changed: ^bool) {
  if box.active {
  box.active = false
  changed^ = true
  }

  elt: ^oc.list_elt
  for next in oc.list_for(&box.children, &elt, oc.ui_box, "listElt") {
  ui_deactivate_all(next, changed)
  }
  }

  editor_escape :: proc(editor: ^Editor) {
  deactivated_any: bool
  ui_deactivate_all(editor.ui_context.root, &deactivated_any)
  if deactivated_any {
  return
  }

  if editor.show_task_context != nil {
  editor.show_task_context = nil
  return
  }
  editor_toggle_menu(editor, nil)
  }

  editor_tab_directional :: proc(editor: ^Editor, shifted: bool) {
  if !editor.show_task_menu {
  return
  }

  b1_frame := oc.ui_box_lookup_key(editor.temp_content.key_frame)
  b1_text := oc.ui_box_lookup_key(editor.temp_content.key_text)
  b2_frame := oc.ui_box_lookup_key(editor.temp_state.key_frame)
  b2_text := oc.ui_box_lookup_key(editor.temp_state.key_text)
  b3_frame := oc.ui_box_lookup_key(editor.temp_tag.key_frame)
  b3_text := oc.ui_box_lookup_key(editor.temp_tag.key_text)

  if b1_frame == nil || b2_frame == nil || b3_frame == nil {
  return
  }

  if shifted {
  b1_frame, b3_frame = b3_frame, b1_frame
  b1_text, b3_text = b3_text, b1_text
  }

  if b1_frame.active {
  oc_deselect_textbox(b1_frame, b1_text)
  oc_select_textbox(&editor.ui_context, b2_frame, b2_text)
  oc_deselect_textbox(b3_frame, b3_text)
  } else if b2_frame.active {
  oc_deselect_textbox(b1_frame, b1_text)
  oc_deselect_textbox(b2_frame, b2_text)
  oc_select_textbox(&editor.ui_context, b3_frame, b3_text)
  } else if b3_frame.active || !b1_frame.active {
  oc_select_textbox(&editor.ui_context, b1_frame, b1_text)
  oc_deselect_textbox(b2_frame, b2_text)
  oc_deselect_textbox(b3_frame, b3_text)
  }
  }

  editor_tab_unshift :: proc(editor: ^Editor) {
  editor_tab_directional(editor, false)
  }

  editor_tab_shift :: proc(editor: ^Editor) {
  editor_tab_directional(editor, true)
  }

  task_make :: proc(content, state, tag: string) -> Task {
  return {
  content = content,
  state = state,
  tag = tag,
  id = uuid.gen(),
  }
  }

  editor_random_pick :: proc(editor: ^Editor) {
  tasks := editor_filtered_tasks(editor)

  if len(tasks) == 0 {
  return
  }

  context.random_generator = runtime.default_random_generator(&editor.rng)
  result := rand.choice(tasks)
  editor.filter_single = result
}