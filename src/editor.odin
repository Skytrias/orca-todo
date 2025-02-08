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
	surface:             oc.surface,
	renderer:            oc.canvas_renderer,
	canvas:              oc.canvas_context,
	font_regular:        oc.font, // font global
	font_icons:          oc.font,
	window_size:         oc.vec2,
	mouse_position:      oc.vec2,
	font_size:           f32,
	file_filters:        oc.str8_list,
	file_arena:          oc.arena,
	input:               oc.input_state,

	// interactions
	write:               strings.Builder,
	write_time:          f32,
	write_hover:         [2]uuid.Guid,

	// task states
	tasks:               [dynamic]Task,
	states:              [dynamic]Task_Header,
	tags:                [dynamic]Task_Header,

	// log state
	logger:              log.Logger,
	ui:                  ^qwe.Context,
	theme:               Theme,

	// task hovering
	task_hovered:        uuid.Guid, // sticks around unless deleted
	task_hovering:       bool,
	task_hover_unit:     f32,
	task_hover_position: [2]f32,

	// task dragging
	task_drag:           uuid.Guid,
	task_dragging:       bool,

	// random state
	rng:                 rand.Default_Random_State,
}

Task_Header :: struct {
	id:          uuid.Guid,
	description: string,
}

Task :: struct {
	id:       uuid.Guid,
	content:  string,
	state:    uuid.Guid,
	tag:      uuid.Guid,

	// animation
	bounds:   qwe.Rect,
	position: [2]f32,
	size:     f32,
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

	editor.logger = oc.create_odin_logger()
	context.logger = editor.logger

	editor.rng = rand.create(0)
	context.random_generator = runtime.default_random_generator(&editor.rng)

	log.info("Startup done")
	oc.arena_init(&editor.file_arena)
	oc.str8_list_push(&editor.file_arena, &editor.file_filters, "md")

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
}

editor_destroy :: proc(editor: ^Editor) {
	delete(editor.tasks)
}

editor_update_start :: proc(editor: ^Editor) {
	qwe.animate_unit(&editor.task_hover_unit, 0.02, editor.task_hovering)
}

editor_update_end :: proc(editor: ^Editor) {
	dt := f32(0.01)
	editor.write_time += dt

	hovered := tasks_find_match_id(editor.tasks[:], editor.task_hovered)
	if hovered == nil {
		editor.task_hovered = {}
	}
}

Task_Inner_Group :: struct {
	content:       [255]string,
	content_index: int,
}

editor_save_builder :: proc(editor: ^Editor, builder: ^strings.Builder) {
	// full := make(map[string]map[string]Task_Inner_Group, 32)
	// for task in editor.tasks {
	// 	if task.tag not_in full {
	// 		full[task.tag] = make(map[string]Task_Inner_Group, 32)
	// 	}

	// 	mapping := &full[task.tag]
	// 	if task.state not_in mapping {
	// 		mapping[task.state] = {}
	// 	}

	// 	group := &mapping[task.state]
	// 	group.content[group.content_index] = task.content
	// 	group.content_index += 1
	// }

	// tag_count: int

	// for tag_key, tag_value in full {
	// 	if tag_count > 0 {
	// 		strings.write_byte(builder, '\n')
	// 	}
	// 	tag_count += 1
	// 	strings.write_string(builder, "# ")
	// 	strings.write_string(builder, tag_key)
	// 	strings.write_byte(builder, '\n')

	// 	for state_key, state_value in tag_value {
	// 		for i in 0 ..< state_value.content_index {
	// 			strings.write_byte(builder, '-')
	// 			strings.write_byte(builder, ' ')
	// 			strings.write_string(builder, "***")
	// 			strings.write_string(builder, state_key)
	// 			strings.write_string(builder, "***")
	// 			strings.write_byte(builder, ' ')
	// 			strings.write_string(builder, state_value.content[i])
	// 			strings.write_byte(builder, '\n')
	// 		}
	// 	}
	// }
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
	// clear(&editor.tasks)

	// // load the content into maps again
	// iter := string(content)
	// temp_tag: string
	// for line in strings.split_lines_iterator(&iter) {
	// 	if len(line) == 0 {
	// 		continue
	// 	}

	// 	start := line[0]

	// 	if start == '#' {
	// 		temp_tag = line[2:]
	// 	} else if start == '-' {
	// 		head, mid, tail := strings.partition(line[2:], " ")
	// 		head_trimmed := strings.trim(head, "*")
	// 		append(&editor.tasks, task_make(tail, head_trimmed, temp_tag))
	// 	}
	// }
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

task_header_make :: proc(description: string) -> Task_Header {
	return {description = description, id = uuid.gen()}
}

editor_example :: proc(editor: ^Editor) {
	clear(&editor.tasks)
	context.random_generator = runtime.default_random_generator(&editor.rng)

	append(&editor.states, task_header_make("Backlog"))
	append(&editor.states, task_header_make("WIP"))
	append(&editor.states, task_header_make("Done"))
	append(&editor.states, task_header_make("Dropped"))

	append(&editor.tags, task_header_make("Plan1"))
	append(&editor.tags, task_header_make("Plan2"))
	append(&editor.tags, task_header_make("Plan3"))
	append(&editor.tags, task_header_make("Plan4"))

	backlog := editor.states[0].id
	plan1 := editor.tags[0].id

	append(&editor.tasks, task_make("Test1", backlog, plan1))
	append(&editor.tasks, task_make("Test2", backlog, plan1))
	append(&editor.tasks, task_make("Test3", backlog, plan1))
	append(&editor.tasks, task_make("Test4", backlog, plan1))
	append(&editor.tasks, task_make("Test5", backlog, plan1))
	append(&editor.tasks, task_make("Test6", backlog, plan1))
	append(&editor.tasks, task_make("Test7", backlog, plan1))
	append(&editor.tasks, task_make("Test7", backlog, plan1))
	append(&editor.tasks, task_make("Test7", backlog, plan1))
	append(&editor.tasks, task_make("Test7", backlog, plan1))
	append(&editor.tasks, task_make("Test7", backlog, plan1))
	append(&editor.tasks, task_make("Test7", backlog, plan1))
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

editor_theme_white :: proc(editor: ^Editor) {
	oc.ui_set_theme(&oc.UI_LIGHT_THEME)
}

editor_theme_black :: proc(editor: ^Editor) {
	oc.ui_set_theme(&oc.UI_DARK_THEME)
}

editor_escape :: proc(editor: ^Editor) {
	if len(editor.write.buf) != 0 {
		editor_write_reset(editor)
		return
	}
}

task_make :: proc(content: string, state, tag: uuid.Guid) -> Task {
	return {content = content, state = state, tag = tag, id = uuid.gen()}
}

editor_write_reset :: proc(editor: ^Editor) {
	strings.builder_reset(&editor.write)
}

editor_write_time_unit :: proc(editor: ^Editor) -> f32 {
	return abs(math.cos(editor.write_time))
}

editor_insert_task :: proc(editor: ^Editor) -> bool {
	content := strings.trim_space(strings.to_string(editor.write))
	if len(content) == 0 {
		return false
	}

	if len(editor.states) == 0 || len(editor.tags) == 0 {
		return false
	}

	// default
	state := editor.states[0].id
	tag := editor.tags[0].id

	if editor.write_hover != {} {
		state_header := task_header_find(editor.states[:], editor.write_hover.x)
		tag_header := task_header_find(editor.tags[:], editor.write_hover.y)

		if state_header != nil && tag_header != nil {
			state = state_header.id
			tag = tag_header.id
		}
	}

	context.random_generator = runtime.default_random_generator(&editor.rng)
	append(&editor.tasks, task_make(content, state, tag))
	editor_write_reset(editor)
	return true
}

task_header_find :: proc(headers: []Task_Header, id: uuid.Guid) -> ^Task_Header {
	for &header in headers {
		if header.id == id {
			return &header
		}
	}

	return nil
}
