package src

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:hash"
import "core:log"
import "core:math"
import "core:math/rand"
import "core:mem"
import "core:slice"
import "core:sort"
import "core:strings"
import oc "core:sys/orca"
import "hsluv"
import "qwe"
import "uuid"

MATERIAL_ICONS :: oc.unicode_range{0xE000, 3000}

Task_Hovered :: struct {
	text:      string,
	direction: f32,
	current:   f32,
}

Editor :: struct {
	surface:         oc.surface,
	renderer:        oc.canvas_renderer,
	canvas:          oc.canvas_context,
	font_regular:    oc.font, // font global
	font_icons:      oc.font,
	window_size:     oc.vec2,
	mouse_position:  oc.vec2,
	font_size:       f32,
	file_filters:    oc.str8_list,
	file_arena:      oc.arena,
	input:           oc.input_state,

	// interactions
	task_modify:     ^Task,
	hovered:         Task_Hovered,
	task_rest_space: f32,
	show_theme:      bool,

	// shortcuts
	shortcuts:       [dynamic]Editor_Shortcut,

	// task states
	tasks:           [dynamic]Task,
	tasks_filtered:  [dynamic]^Task,

	// filtering
	filters_state:   map[string]bool,
	filters_tag:     map[string]bool,
	filter_single:   ^Task,
	all_states:      map[string]int,
	all_tags:        map[string]int,

	// log state
	logger:          log.Logger,
	ui:              ^qwe.Context,
	theme:           Theme,

	// random state
	rng:             rand.Default_Random_State,

	// textbox custom
	write_task:      Task,
	write:           [3]strings.Builder,
	write_time:      f32,
	write_cycle:     int,
}

// TODO actually manage memory
Task :: struct {
	content: string,
	state:   string,
	tag:     string,
	id:      uuid.Guid,
}

Editor_Shortcut :: struct {
	group:       string,
	name:        string,
	hide:        bool,
	key_display: string,
	key:         oc.key_code,
	mods:        oc.keymod_flags,
	call:        proc(_: ^Editor),
}

Theme :: struct {
	text1:                  [4]f32,
	text2:                  [4]f32,
	text_edit:              [4]f32,
	border:                 [4]f32,
	border_highlight:       [4]f32,
	panel:                  [4]f32,
	overlay:                [4]f32,
	button:                 [4]f32,
	base:                   [4]f32,
	scroll_base:            [4]f32,
	scroll_thumb:           [4]f32,

	// filter
	bstate:                 [2][4]f32,

	// styling
	border_radius:          f32,
	border_width:           f32,
	border_highlight_width: f32,
	text_margin:            [2]f32,
}

editor_init :: proc(editor: ^Editor) {
	editor.renderer = oc.canvas_renderer_create()
	editor.surface = oc.canvas_surface_create(editor.renderer)
	editor.canvas = oc.canvas_context_create()

	editor.window_size = {1200, 800}
	oc.window_set_title("orca todo")
	oc.window_set_size(editor.window_size)

	editor.font_size = 20

	// NOTE: This is temporary and will change soon
	// Describe wanted unicode ranges to usable for rendering
	ranges_regular := [?]oc.unicode_range {
		oc.UNICODE_BASIC_LATIN,
		oc.UNICODE_C1_CONTROLS_AND_LATIN_1_SUPPLEMENT,
		oc.UNICODE_LATIN_EXTENDED_A,
		oc.UNICODE_LATIN_EXTENDED_B,
		oc.UNICODE_SPECIALS,
	}
	ranges_material := [?]oc.unicode_range{MATERIAL_ICONS}

	// create the font from an ttf asset that needs to be provided
	editor.font_regular = oc.font_create_from_path(
		"Lato-Regular.ttf",
		u32(len(ranges_regular)),
		&ranges_regular[0],
	)
	editor.font_icons = oc.font_create_from_path(
		"MaterialSymbolsOutlined-Regular.ttf",
		u32(len(ranges_material)),
		&ranges_material[0],
	)
	// editor.font_icons = oc.font_create_from_path("icofont.ttf", u32(len(ranges_material)), &ranges_material[0])

	editor.tasks = make([dynamic]Task, 0, 128)
	editor.tasks_filtered = make([dynamic]^Task, 0, 128)

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

	editor.theme = {
		text1                  = {0, 0, 0.1, 1},
		text2                  = {0, 0, 0.9, 1},
		text_edit              = {10, 1, 0.5, 1},
		border                 = {0, 0, 0.95, 1},
		border_highlight       = {0, 0.9, 0.50, 1},
		overlay                = {0, 0, 0.1, 0.95},
		panel                  = {0, 0, 1.0, 1},
		button                 = {0, 0, 0.8, 1},
		base                   = {0, 0, 0.7, 1},
		scroll_base            = {0, 0, 0.3, 1},
		scroll_thumb           = {0, 0, 0.5, 1},
		bstate                 = {{0, 0.5, 0.5, 1}, {40, 0.5, 0.5, 1}},
		border_radius          = 5,
		border_width           = 2,
		border_highlight_width = 4,
		text_margin            = {10, 5},
	}

	// editor.theme = {
	// 	text                   = {0, 0, 0.0, 1},
	// 	border                 = {0, 0, 0.20, 1},
	// 	border_highlight       = {0, 0.9, 0.50, 1},
	// 	panel                  = {0, 0, 0.15, 1},
	// 	button                 = {0, 0, 0.5, 1},
	// 	base                   = {0, 0, 0.3, 1},
	// 	scroll_base            = {0, 0, 0.3, 1},
	// 	scroll_thumb           = {0, 0, 0.5, 1},
	// 	bstate                 = {{0, 0.5, 0.5, 1}, {40, 0.5, 0.5, 1}},
	// 	border_radius          = 5,
	// 	border_width           = 2,
	// 	border_highlight_width = 4,
	// 	text_margin            = {10, 5},
	// }

	editor.ui = new(qwe.Context)
	qwe.init(editor.ui)

	for i in 0 ..< len(editor.write) {
		strings.builder_init(&editor.write[i], 0, 128)
	}
}

editor_destroy :: proc(editor: ^Editor) {
	for i in 0 ..< len(editor.write) {
		delete(editor.write[i].buf)
	}
	editor_shortcuts_destroy(editor)
	delete(editor.tasks)
	delete(editor.filters_state)
	delete(editor.filters_tag)
	delete(editor.all_states)
	delete(editor.all_tags)
}

editor_update_start :: proc(editor: ^Editor) {
	for task in editor.tasks {
		if task.state not_in editor.filters_state {
			editor.filters_state[task.state] = false
		}

		if task.tag not_in editor.filters_tag {
			editor.filters_tag[task.tag] = false
		}
	}
}

editor_update_end :: proc(editor: ^Editor) {
	dt := f32(0.01)
	editor.hovered.current = clamp(editor.hovered.current + editor.hovered.direction * dt, 0, 1)
	editor.write_time += dt
}

Task_Inner_Group :: struct {
	content:       [255]string,
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
			for i in 0 ..< state_value.content_index {
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
		kind    = .SAVE,
		flags   = {.FILES},
		title   = "Save File",
		okLabel = "Oki Doki",
	}
	// filters = editor.file_filters,
	result := oc.file_open_with_dialog(scratch.arena, {.WRITE}, {.TRUNCATE, .CREATE}, &description)

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
	file := oc.file_open(file_path, {.WRITE}, {.TRUNCATE, .CREATE})

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
		kind    = .OPEN,
		flags   = {.FILES},
		title   = "Load File",
		okLabel = "Oki Doki",
	}

	result := oc.file_open_with_dialog(scratch.arena, {.READ}, {}, &description)

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

	cmp := oc_open_cmp("test.md", {.READ}, {})
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
				editor.all_states[task.state] = 1
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
				editor.all_tags[task.tag] = 1
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

editor_modify_set :: proc(editor: ^Editor, to: ^Task) {
	editor.task_modify = to
	for i in 0 ..< len(editor.write) {
		strings.builder_reset(&editor.write[i])
	}
	strings.write_string(&editor.write[0], to.content)
	strings.write_string(&editor.write[1], to.state)
	strings.write_string(&editor.write[2], to.tag)
}

editor_accept_task_changes :: proc(editor: ^Editor) -> bool {
	content := strings.trim_space(strings.to_string(editor.write[0]))
	state := strings.trim_space(strings.to_string(editor.write[1]))
	tag := strings.trim_space(strings.to_string(editor.write[2]))

	if len(state) == 0 || len(tag) == 0 || len(content) == 0 {
		return false
	}

	if editor.task_modify != nil {
		task := editor.task_modify
		task.content = strings.clone(content)
		task.state = strings.clone(state)
		task.tag = strings.clone(tag)
		editor_write_reset(editor)
		return true
	}

	return false
}

editor_example :: proc(editor: ^Editor) {
	clear(&editor.tasks)
	context.random_generator = runtime.default_random_generator(&editor.rng)
	append(&editor.tasks, task_make("Test1", "Backlog", "Plan1"))
	append(&editor.tasks, task_make("Test2 Test Test", "Backlog", "Plan1"))

	append(&editor.tasks, task_make("Test3", "WIP", "Plan2"))
	append(&editor.tasks, task_make("Test4", "WIP", "Plan3"))
	append(&editor.tasks, task_make("Test5", "Done", "Plan4"))
	append(&editor.tasks, task_make("Test6", "Done", "Plan5"))
	append(&editor.tasks, task_make("Test7", "Done", "Plan6"))

	append(&editor.tasks, task_make("Test8", "Done", "Plan3"))
	append(&editor.tasks, task_make("Test9", "Done", "Plan3"))
	append(&editor.tasks, task_make("Test11", "Done", "Plan3"))
	append(&editor.tasks, task_make("Test11", "Done", "Plan3"))
	append(
		&editor.tasks,
		task_make("ui_text_box_result should include *ui_box reference", "Open", "Orca"),
	)
	append(&editor.tasks, task_make("Add UI Styling Helpers or rework masking", "Open", "Orca"))
	append(&editor.tasks, task_make("Add str8 versions of UI module calls", "Open", "Orca"))
	append(
		&editor.tasks,
		task_make("Tooltips should not appear while resizing the window", "Open", "Orca"),
	)
}

editor_task_clone :: proc(editor: ^Editor, task: ^Task) {
	temp := task_make(
		strings.clone(task.content),
		strings.clone(task.state),
		strings.clone(task.tag),
	)
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

hash_hue :: proc(name1, name2: string, offset: u64) -> f32 {
	seed1 := hash.fnv64a(transmute([]byte)name1)
	seed2 := hash.fnv64a(transmute([]byte)name2)
	// seed := hash.sdbm(transmute([]byte) name)
	rand.reset(u64(seed1) + u64(seed2) + offset)
	return f32(rand.float64() * 360)
}

hsluv_hash_color :: proc(
	name: string,
	offset: u64,
	saturation, value: f32,
	alpha: f32,
) -> oc.color {
	seed := hash.fnv64a(transmute([]byte)name)
	// seed := hash.sdbm(transmute([]byte) name)
	rand.reset(u64(seed) + offset)
	h := rand.float64() * 360
	s := f64(saturation * 100)
	v := f64(value * 100)
	r, g, b := hsluv.hsluv_to_rgb(h, s, v)
	return oc.color_srgba(f32(r), f32(g), f32(b), alpha)
}

editor_shortcuts_init :: proc(editor: ^Editor) {
	editor.shortcuts = make([dynamic]Editor_Shortcut, 0, 64)
	append(
		&editor.shortcuts,
		Editor_Shortcut {
			group = "File",
			name = "Save",
			key_display = "S",
			key = .S,
			mods = {.CMD},
			call = editor_save,
		},
	)
	append(
		&editor.shortcuts,
		Editor_Shortcut {
			group = "File",
			name = "Save To",
			key_display = "S",
			key = .S,
			mods = {.CMD, .SHIFT},
			call = editor_save_to,
		},
	)
	append(
		&editor.shortcuts,
		Editor_Shortcut {
			group = "File",
			name = "Load",
			key_display = "O",
			key = .O,
			mods = {.CMD},
			call = editor_load,
		},
	)
	append(
		&editor.shortcuts,
		Editor_Shortcut {
			group = "File",
			name = "Load From",
			key_display = "O",
			key = .O,
			mods = {.CMD, .SHIFT},
			call = editor_load_from,
		},
	)
	append(
		&editor.shortcuts,
		Editor_Shortcut {
			group = "Commands",
			name = "Escape",
			hide = true,
			key = .ESCAPE,
			mods = {},
			call = editor_escape,
		},
	)
	append(
		&editor.shortcuts,
		Editor_Shortcut {
			group = "Commands",
			name = "Tab Forward",
			hide = true,
			key = .TAB,
			mods = {},
			call = editor_tab_unshift,
		},
	)
	append(
		&editor.shortcuts,
		Editor_Shortcut {
			group = "Commands",
			name = "Tab Backward",
			hide = true,
			key = .TAB,
			mods = {.SHIFT},
			call = editor_tab_shift,
		},
	)

	// Theme
	append(
		&editor.shortcuts,
		Editor_Shortcut {
			group = "Theme",
			name = "Light",
			key_display = "2",
			key = ._2,
			mods = {.CMD},
			call = editor_theme_white,
		},
	)
	append(
		&editor.shortcuts,
		Editor_Shortcut {
			group = "Theme",
			name = "Dark",
			key = ._3,
			key_display = "3",
			mods = {.CMD},
			call = editor_theme_black,
		},
	)
	append(
		&editor.shortcuts,
		Editor_Shortcut {
			group = "Theme",
			name = "Show",
			key = ._1,
			key_display = "1",
			mods = {.CMD},
			call = editor_theme_toggle,
		},
	)
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

editor_escape :: proc(editor: ^Editor) {
	if editor.task_modify != nil {
		editor.task_modify = nil
		editor_write_reset(editor)
		return
	}
}

editor_tab_directional :: proc(editor: ^Editor, shifted: bool) {
	editor.write_cycle = (editor.write_cycle + 1) % 3
}

editor_tab_unshift :: proc(editor: ^Editor) {
	editor_tab_directional(editor, false)
}

editor_tab_shift :: proc(editor: ^Editor) {
	editor_tab_directional(editor, true)
}

task_make :: proc(content, state, tag: string) -> Task {
	return {content = content, state = state, tag = tag, id = uuid.gen()}
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

editor_write_cycle_builder :: proc(editor: ^Editor) -> ^strings.Builder {
	return &editor.write[editor.write_cycle]
}

editor_insert_cycle :: proc(editor: ^Editor) -> bool {
	if editor_accept_task_changes(editor) {
		editor.task_modify = nil
		return true
	}

	content := strings.trim_space(strings.to_string(editor.write[0]))
	if len(content) == 0 {
		return false
	}

	tasks := editor_filtered_tasks(editor)

	state := strings.trim_space(strings.to_string(editor.write[1]))
	if len(state) == 0 {
		if len(tasks) > 0 {
			state = tasks[len(tasks) - 1].state
		} else {
			return false
		}
	}

	tag := strings.trim_space(strings.to_string(editor.write[2]))
	if len(tag) == 0 {
		if len(tasks) > 0 {
			tag = tasks[len(tasks) - 1].tag
		} else {
			return false
		}
	}

	editor.write_cycle = 0
	context.random_generator = runtime.default_random_generator(&editor.rng)
	task := task_make(strings.clone(content), strings.clone(state), strings.clone(tag))
	editor_write_reset(editor)
	editor.write_task = {}
	append(&editor.tasks, task)
	return true
}

editor_write_reset :: proc(editor: ^Editor) {
	strings.builder_reset(&editor.write[0])
	strings.builder_reset(&editor.write[1])
	strings.builder_reset(&editor.write[2])
}

editor_write_time_unit :: proc(editor: ^Editor) -> f32 {
	return abs(math.cos(editor.write_time))
}
