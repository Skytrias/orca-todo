package src

import "base:intrinsics"
import "base:runtime"
import "core:encoding/csv"
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
TASK_EMPTY :: "(empty)"

Task_Hovered :: struct {
	text:      string,
	direction: f32,
	current:   f32,
}

Camera :: struct {
	zoom:       f32,
	offset:     [2]f32,
	dragging:   bool,
	drag_start: [2]f32,
}

Write_Mode :: enum {
	Task,
	State,
	Tag,
}

Header_Drag :: struct {
	running:    bool,
	finished:   bool,
	is_tag:     bool,
	index_from: int,
	index_to:   int,
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
	input:               oc.input_state,

	// interactions
	write:               strings.Builder,
	write_time:          f32,
	write_hover:         [2]uuid.Guid,
	write_mode:          Write_Mode,
	camera:              Camera,
	header_drag:         Header_Drag,

	// task states
	tasks:               [dynamic]Task,
	states:              [dynamic]Header,
	tags:                [dynamic]Header,

	// log state
	logger:              log.Logger,
	ui:                  ^qwe.Context,
	theme:               Theme,
	theme_white:         bool,

	// task hovering
	task_hovered:        uuid.Guid, // sticks around unless deleted
	task_hovering:       bool,
	task_hover_unit:     f32,
	task_panning:        f32,
	task_hover_position: [2]f32,

	// random state
	rng:                 rand.Default_Random_State,
}

Header :: struct {
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
	border:                 [4]f32,
	border_highlight:       [4]f32,
	panel1:                 [4]f32,
	panel2:                 [4]f32,
	button:                 [4]f32,
	base:                   [4]f32,

	// scrollbar
	scrollbar_base:         [4]f32,
	scrollbar_thumb:        [4]f32,

	// styling
	border_radius:          f32,
	border_width:           f32,
	border_highlight_width: f32,
	text_margin:            [2]f32,
}

Task_Drop :: struct {
	state: uuid.Guid,
	tag:   uuid.Guid,
}

editor_init :: proc(editor: ^Editor) {
	editor.renderer = oc.canvas_renderer_create()
	editor.surface = oc.canvas_surface_create(editor.renderer)
	editor.canvas = oc.canvas_context_create()
	editor.camera.zoom = 1

	editor.window_size = {1200, 800}
	oc.window_set_title("todo grid")
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
	editor.tags = make([dynamic]Header, 0, 32)
	editor.states = make([dynamic]Header, 0, 32)

	editor.logger = oc.create_odin_logger()
	context.logger = editor.logger

	editor.rng = rand.create(0)
	context.random_generator = runtime.default_random_generator(&editor.rng)

	log.info("Startup done")
	theme_set(editor, false)

	editor.ui = new(qwe.Context)
	qwe.init(editor.ui)
	editor.ui.dragndrop.call = dragndrop_task
	editor.ui.dragndrop.call_data = editor

	editor_state_insert(editor, "Backlog")
	editor_tag_insert(editor, "Start")
}

theme_set :: proc(editor: ^Editor, white: bool) {
	editor.theme_white = white
	if white {
		editor.theme = {
			text1                  = {0, 0, 0.1, 1},
			text2                  = {0, 0, 0.7, 1},
			border                 = {0, 0, 0.95, 1},
			border_highlight       = {125, 0.9, 0.60, 1},
			panel1                 = {0, 0, 1.0, 1},
			panel2                 = {0, 0, 1.0, 1},
			button                 = {0, 0, 0.8, 1},
			base                   = {0, 0, 0.7, 1},
			border_radius          = 5,
			border_width           = 2,
			border_highlight_width = 5,
			text_margin            = {5, 5},
		}
	} else {
		editor.theme = {
			text1                  = {0, 0, 0.95, 1},
			text2                  = {0, 0, 0.6, 1},
			border                 = {0, 0, 0.25, 1},
			border_highlight       = {125, 0.9, 0.75, 1},
			panel1                 = {0, 0, 0.05, 1},
			panel2                 = {0, 0, 0.15, 1},
			button                 = {0, 0, 0.2, 1},
			base                   = {0, 0, 0.3, 1},
			scrollbar_base         = {0, 0, 0.2, 1},
			scrollbar_thumb        = {0, 0, 0.4, 1},
			border_radius          = 5,
			border_width           = 2,
			border_highlight_width = 5,
			text_margin            = {5, 5},
		}
	}
}

editor_destroy :: proc(editor: ^Editor) {
	delete(editor.tasks)
	delete(editor.states)
	delete(editor.tags)
}

editor_font_size_reset :: proc(editor: ^Editor) {
	editor.font_size = 20
	oc.set_font_size(editor.font_size)
}

editor_update_start :: proc(editor: ^Editor) {
	editor_font_size_reset(editor)
	qwe.animate_unit(&editor.task_hover_unit, 0.02, editor.task_hovering)

	if editor.camera.dragging {
		diff := editor.input.mouse.pos - editor.camera.drag_start
		editor.camera.offset += diff
		editor.camera.drag_start = editor.input.mouse.pos
	}
}

editor_update_end :: proc(editor: ^Editor) {
	dt := f32(0.01)
	editor.write_time += dt

	hovered := tasks_find_match_id(editor.tasks[:], editor.task_hovered)
	if hovered == nil {
		editor.task_hovered = {}
	}

	if editor.header_drag.finished {
		log.info("FIN", editor.header_drag.index_from, editor.header_drag.index_to)
		editor.header_drag = {}
	}

	if editor.task_panning <= math.PI {
		editor.task_panning += dt / 4
	} else {
		editor.task_panning = 0
	}
}

editor_save_builder :: proc(editor: ^Editor, builder: ^strings.Builder) {
	stream := strings.to_writer(builder)
	w: csv.Writer
	csv.writer_init(&w, stream)
	csv.write(&w, {"Tag", "State", "Task"})

	task_matches := make([dynamic]^Task, 0, 128, context.temp_allocator)
	for tag in editor.tags {
		for state in editor.states {
			tag := header_find_id(editor.tags[:], tag.id)
			state := header_find_id(editor.states[:], state.id)

			tasks_find_match_ids(&task_matches, editor.tasks[:], state.id, tag.id)
			for task in task_matches {
				csv.write(&w, {tag.description, state.description, task.content})
			}

			if len(task_matches) == 0 {
				csv.write(&w, {tag.description, state.description, TASK_EMPTY})
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

	file_path := "test.csv"
	file := oc.file_open(file_path, {.WRITE}, {.TRUNCATE, .CREATE})

	builder := strings.builder_make(0, mem.Kilobyte, context.temp_allocator)
	editor_save_builder(editor, &builder)

	oc.file_write_slice(file, builder.buf[:])
	oc.file_close(file)
}

editor_clear_clones :: proc(editor: ^Editor) {
	for task in editor.tasks {
		delete(task.content)
	}
	for tag in editor.tags {
		delete(tag.description)
	}
	for state in editor.states {
		delete(state.description)
	}
	clear(&editor.tasks)
	clear(&editor.tags)
	clear(&editor.states)
}

editor_load_from_string :: proc(editor: ^Editor, content: string) {
	editor_clear_clones(editor)
	context.random_generator = runtime.default_random_generator(&editor.rng)

	task_allocator := context.allocator

	r: csv.Reader
	r.lazy_quotes = true
	r.reuse_record = true
	r.reuse_record_buffer = true
	csv.reader_init_with_string(&r, content)
	defer csv.reader_destroy(&r)

	for records, i, err in csv.iterator_next(&r) {
		if err != nil || i == 0 {
			continue
		}

		tag_description := records[0]
		state_description := records[1]
		task := records[2]

		tag := header_find_description(editor.tags[:], tag_description)
		state := header_find_description(editor.states[:], state_description)

		tag_id: uuid.Guid
		if tag == nil {
			tag_id = editor_tag_insert(editor, tag_description)
		} else {
			tag_id = tag.id
		}

		state_id: uuid.Guid
		if state == nil {
			state_id = editor_state_insert(editor, state_description)
		} else {
			state_id = state.id
		}

		if task == TASK_EMPTY {
			continue
		}

		context.allocator = task_allocator
		append(&editor.tasks, task_make(task, state_id, tag_id))
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

	cmp := oc_open_cmp("test.csv", {.READ}, {})
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

header_find_id :: proc(headers: []Header, id: uuid.Guid) -> ^Header {
	for &header in headers {
		if header.id == id {
			return &header
		}
	}

	return nil
}

header_find_description :: proc(headers: []Header, description: string) -> ^Header {
	for &header in headers {
		if header.description == description {
			return &header
		}
	}

	return nil
}

editor_state_insert :: proc(editor: ^Editor, description: string) -> (id: uuid.Guid) {
	id = uuid.gen()
	append(&editor.states, Header{id = id, description = strings.clone(description)})
	return
}

editor_tag_insert :: proc(editor: ^Editor, description: string) -> (id: uuid.Guid) {
	id = uuid.gen()
	append(&editor.tags, Header{id = id, description = strings.clone(description)})
	return
}

task_make :: proc(content: string, state, tag: uuid.Guid, allocator := context.allocator) -> Task {
	return {content = strings.clone(content, allocator), state = state, tag = tag, id = uuid.gen()}
}

editor_example :: proc(editor: ^Editor) {
	editor_clear_clones(editor)
	context.random_generator = runtime.default_random_generator(&editor.rng)

	backlog := editor_state_insert(editor, "Backlog")
	editor_state_insert(editor, "WIP")
	editor_state_insert(editor, "Done")
	editor_state_insert(editor, "Dropped")

	plan1 := editor_tag_insert(editor, "Plan1")
	editor_tag_insert(editor, "Plan2")
	editor_tag_insert(editor, "Plan3")
	editor_tag_insert(editor, "Plan4")

	append(&editor.tasks, task_make("Test1", backlog, plan1))
	append(&editor.tasks, task_make("Test2", backlog, plan1))
	append(&editor.tasks, task_make("Test3", backlog, plan1))
	append(&editor.tasks, task_make("Test4", backlog, plan1))
	append(&editor.tasks, task_make("Test5", backlog, plan1))
	append(&editor.tasks, task_make("Test6", backlog, plan1))
	append(
		&editor.tasks,
		task_make("Testing this really long text out just to see if it works", backlog, plan1),
	)
	append(&editor.tasks, task_make("Test7", backlog, plan1))
	append(&editor.tasks, task_make("Test7", backlog, plan1))
	append(&editor.tasks, task_make("Test7", backlog, plan1))
	append(&editor.tasks, task_make("Test7", backlog, plan1))
	append(&editor.tasks, task_make("Test7", backlog, plan1))
	append(&editor.tasks, task_make("Test7", backlog, plan1))
	append(&editor.tasks, task_make("Test7", backlog, plan1))
	append(&editor.tasks, task_make("Test7", backlog, plan1))
	append(&editor.tasks, task_make("Test7", backlog, plan1))
	append(&editor.tasks, task_make("Test7", backlog, plan1))
	append(&editor.tasks, task_make("Test7", backlog, plan1))
	append(&editor.tasks, task_make("Test7", backlog, plan1))
	append(&editor.tasks, task_make("Test7", backlog, plan1))
	append(&editor.tasks, task_make("Test7", backlog, plan1))
	append(&editor.tasks, task_make("Test7", backlog, plan1))
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

hash_hue :: proc(text: string) -> f32 {
	seed := hash.fnv64a(transmute([]byte)text)
	rand.reset(u64(seed))
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

editor_write_reset :: proc(editor: ^Editor) {
	strings.builder_reset(&editor.write)
}

editor_write_time_unit :: proc(editor: ^Editor) -> f32 {
	return abs(math.cos(editor.write_time))
}

editor_insert_task :: proc(editor: ^Editor) {
	content := strings.trim_space(strings.to_string(editor.write))
	if len(content) == 0 {
		return
	}

	context.random_generator = runtime.default_random_generator(&editor.rng)
	switch editor.write_mode {
	case .State:
		editor_state_insert(editor, content)
		editor_write_reset(editor)

	case .Tag:
		editor_tag_insert(editor, content)
		editor_write_reset(editor)

	case .Task:
		if len(editor.states) == 0 || len(editor.tags) == 0 {
			return
		}

		if editor.write_hover == {} {
			return
		}

		state := header_find_id(editor.states[:], editor.write_hover.x)
		tag := header_find_id(editor.tags[:], editor.write_hover.y)

		if state != nil && tag != nil {
			state_id := editor.write_hover.x
			tag_id := editor.write_hover.y
			append(&editor.tasks, task_make(content, state_id, tag_id))
			editor_write_reset(editor)
		}
	}
}

camera_zoom_at :: proc(editor: ^Editor, cam: ^Camera, zoom_factor: f32) {
	mouse := editor.input.mouse.pos

	mouse_world := [2]f32{(mouse.x - cam.offset.x) / cam.zoom, (mouse.y - cam.offset.y) / cam.zoom}

	// Apply the zoom change
	cam.zoom = max(cam.zoom - zoom_factor, 0.1)

	// Recalculate offset to keep the zoom centered at the mouse position
	cam.offset.x = mouse.x - mouse_world.x * cam.zoom
	cam.offset.y = mouse.y - mouse_world.y * cam.zoom
}

dragndrop_task :: proc(state: ^qwe.Drag_Drop_State, drop: qwe.Drop_Data) -> bool {
	editor := cast(^Editor)state.call_data
	root := &state.drag_bytes[0]

	switch state.drag_type {
	case "Task":
		if drop.type == "Cell" {
			task := cast(^Task)root
			task_drop := cast(^Task_Drop)drop.data
			// task_make(strings.clone(task.content))
			// task.id = 
			task.state = task_drop.state
			task.tag = task_drop.tag
			append(&editor.tasks, task^)
			return true // accept this early
		}
	}

	return false
}
