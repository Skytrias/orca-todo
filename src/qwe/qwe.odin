package qwe

import "core:hash"
import "core:log"
import "core:mem"
import "core:strings"

// TODO scale

Id :: u32
MAX_DRAG_BYTES :: 1028 * 4
MAX_DROP_BYTES :: 1028 * 4
MAX_DROP_COUNT :: 256
MAX_HOVER :: 256

Mouse :: enum {
	Left,
	Right,
	Middle,
}

Mouse_Buttons :: bit_set[Mouse]

Context :: struct {
	// element storage
	elements:               [dynamic]Element,
	persistance:            map[Id]Element_Persistent,

	// stacks
	window:                 ^Element,
	parent_stack:           [dynamic]^Element,
	spawn_index:            int,

	// mouse butons
	mouse_down:             Mouse_Buttons,
	mouse_pressed:          Mouse_Buttons,
	mouse_released:         Mouse_Buttons,

	// mouse
	mouse_position:         [2]int,
	mouse_last_position:    [2]int,
	scroll_delta:           [2]int,
	mouse_pressed_position: [2]int,
	mouse_delta:            [2]int,
	window_size:            [2]int,

	// frame tracking
	frame_count:            int,

	// next element
	next:                   Element,

	// interaction
	hover_id:               Id, // latest hover
	hover_stack:            [MAX_HOVER]^Element, // hover stack
	hover_index:            int,
	focus_id:               Id,
	focus_lost_id:          Id,

	// dragndrop
	dragndrop:              Drag_Drop_State,
}

Element_Flag :: enum {
	Is_Parent,
	Ignore_Self,
	Ignore_Self_And_Descendants,
	Scroll_Ignore,
}

Element_Flags :: bit_set[Element_Flag]

Element :: struct {
	id:                 Id, // as you sometimes still need to use it without the map
	text_hash:          string, // right part of the string
	text_label:         string, // left part of the string
	text_align:         [2]Text_Align,
	flags:              Element_Flags,
	parent:             ^Element,

	// rectangles
	bounds:             Rect,
	clipped:            Rect, // TODO
	layout_start:       Rect,
	layout:             Rect, // temp bounds rect used for layouting
	inf:                Rect,

	// cut info
	cut_direction:      Cut_Direction,
	cut_percentage:     int,
	cut_amount:         int,
	cut_gap:            int,
	cut_margin:         int,

	// temp
	hover_children_ran: bool,
	highlight_state:    bool,

	// persistent state fetched
	persistent:         ^Element_Persistent,
}

// could just store this on the element but had issues when element hashes would collide
Element_Persistent :: struct {
	// frame info
	frame_active:   int,

	// animation
	hover_children: f32,
	hover:          f32,
	focus:          f32,

	// animation manual
	highlight:      f32,

	// scroll
	scroll:         [2]int,
}

Text_Align :: enum {
	Start,
	Center,
	End,
}

Drag_Drop_State :: struct {
	// overlapping drop registers (name + data allocated)
	stack:       [MAX_DROP_COUNT]Drop_Data,
	stack_index: int,

	// single callback handling (drag + drop type based)
	call:        Drag_Drop_Call, // universal way to handle drag&drop
	call_data:   rawptr,

	// drop stored data
	drop_arena:  mem.Arena,
	drop_bytes:  []byte,

	// drag stored data
	drag_type:   string, // starting drag data
	drag_bytes:  []byte,
}

Drop_Data :: struct {
	type:      string,
	data:      rawptr,
	data_size: int,
}

// when this returns true, the drag&drop chain stops
Drag_Drop_Call :: proc(state: ^Drag_Drop_State, drop: Drop_Data) -> bool

init :: proc(ctx: ^Context) {
	ctx.elements = make([dynamic]Element, 0, 10)
	ctx.persistance = make(map[Id]Element_Persistent, 10)
	ctx.parent_stack = make([dynamic]^Element, 0, 256)
	ctx.dragndrop.drag_bytes = make([]byte, MAX_DRAG_BYTES)
	ctx.dragndrop.drop_bytes = make([]byte, MAX_DROP_BYTES)
	mem.arena_init(&ctx.dragndrop.drop_arena, ctx.dragndrop.drop_bytes)
}

destroy :: proc(ctx: ^Context) {
	delete(ctx.elements)
	delete(ctx.parent_stack)
	delete(ctx.dragndrop.drag_bytes)
	delete(ctx.dragndrop.drop_bytes)
}

begin :: proc(ctx: ^Context) {
	log.info("BEGIN BEGIN")
	defer log.info("BEGIN END")

	ctx.frame_count += 1
	ctx.spawn_index += 1
	clear(&ctx.parent_stack)
	clear(&ctx.elements)

	ctx.mouse_delta = ctx.mouse_position - ctx.mouse_last_position

	// clear hover info
	ctx.hover_index = 0
	ctx.hover_stack[0] = nil

	// clear dragndrop
	ctx.dragndrop.stack_index = 0
	free_all(mem.arena_allocator(&ctx.dragndrop.drop_arena))

	element_set_bounds(ctx, {0, ctx.window_size.x, 0, ctx.window_size.y})
	ctx.window = element_begin(ctx, "!root!", {})
}

drop_clear :: proc(ctx: ^Context) {
	ctx.dragndrop.drag_type = ""
	free_all(mem.arena_allocator(&ctx.dragndrop.drop_arena))
}

animate_unit :: proc(value: ^f32, dt: f32, increase: bool) {
	add := increase ? dt : -dt
	value^ = clamp(value^ + add, 0, 1)
}

end :: proc(ctx: ^Context, dt: f32) {
	log.info("END BEGIN")
	defer log.info("END END")

	element_end(ctx)

	for &element in &ctx.elements {
		element.hover_children_ran = false
	}

	// update animations in elements themselves
	for &element in &ctx.elements {
		animate_unit(&element.persistent.hover, dt, element.id == ctx.hover_id)
		animate_unit(&element.persistent.focus, dt, element.id == ctx.focus_id)
		animate_unit(&element.persistent.highlight, dt, element.highlight_state)

		if element.id == ctx.focus_id {
			element.parent.hover_children_ran = true
		}
	}

	// find all hovered parents
	for i in 0 ..< ctx.hover_index {
		hovered := ctx.hover_stack[i]
		hovered.hover_children_ran = true
	}

	// udpate hover_children
	for &element in &ctx.elements {
		animate_unit(&element.persistent.hover_children, dt, element.hover_children_ran)
	}

	// handle drag&drop requests
	if ctx.dragndrop.call != nil && .Left in ctx.mouse_released {
		for i := ctx.dragndrop.stack_index - 1; i >= 0; i -= 1 {
			drop := ctx.dragndrop.stack[i]

			if ctx.dragndrop.call(&ctx.dragndrop, drop) {
				break
			}
		}

		drop_clear(ctx)
	}

	ctx.mouse_pressed = {}
	ctx.mouse_released = {}
	ctx.scroll_delta = {}
	ctx.mouse_last_position = ctx.mouse_position

	if ctx.focus_lost_id != 0 {
		ctx.focus_lost_id = 0
	}

	// discard old elements

	ctx.next = {}
}

/////////////////////////////////////////////////////////////////////
// Element Creation
/////////////////////////////////////////////////////////////////////

// get an id by input bytes, seeded by the parent panel id 
@(private)
id_get_bytes :: proc(ctx: ^Context, bytes: []byte) -> Id {
	tail := len(ctx.parent_stack)
	parent_id := tail > 0 ? ctx.parent_stack[tail - 1].id : 0
	return hash.fnv32a(bytes, parent_id)
}

element_get :: proc(ctx: ^Context, text: string, flags: Element_Flags) -> ^Element {
	log.info("ELEMENT GET START")
	left, match, right := strings.partition(text, "##")
	// get the id
	if right == "" {
		right = left
	}
	id := id_get_bytes(ctx, transmute([]byte)right)
	log.info("CHECK ID", id)

	// create the element if it doesnt exist
	if id not_in ctx.persistance {
		log.info("INS", id, len(ctx.elements), cap(ctx.elements))
		ctx.persistance[id] = {}
		log.info("INS DONE")
	}
	persistent := &ctx.persistance[id]

	// set defaults
	append(
		&ctx.elements,
		Element {
			id = id,
			text_label = left,
			text_hash = right,
			cut_direction = ctx.next.cut_direction,
			cut_amount = ctx.next.cut_amount,
			cut_percentage = ctx.next.cut_percentage,
			cut_gap = ctx.next.cut_gap,
			cut_margin = ctx.next.cut_margin,
			text_align = ctx.next.text_align,
			flags = flags,
			bounds = ctx.next.bounds,
			clipped = ctx.next.bounds,
			inf = RECT_INF,
			parent = nil,
		},
	)
	res := &ctx.elements[len(ctx.elements) - 1]
	persistent.frame_active = ctx.frame_count
	// if res.persistent.frame_active == ctx.frame_count {
	// log.info("ID was already activated this time-----------------------------------", id, text)
	// }

	// get last parent
	if len(ctx.parent_stack) > 0 {
		parent := ctx.parent_stack[len(ctx.parent_stack) - 1]
		if res == parent {
			log.info("THSI SISSSS BAD--------------------------++++++++++++++++")
		}
		res.parent = parent

		if .Scroll_Ignore not_in flags {
			res.bounds.t -= parent.persistent.scroll.y
			res.bounds.b -= parent.persistent.scroll.y
			res.bounds.l -= parent.persistent.scroll.x
			res.bounds.r -= parent.persistent.scroll.x
		}
	}

	log.info("MODIFY DONE")

	ctx.spawn_index += 1
	return res
}

element_make :: proc(ctx: ^Context, text: string, flags: Element_Flags) -> ^Element {
	log.info("ELM MAKE")
	element := element_get(ctx, text, flags)
	log.info("ELM CUT")
	element_cut_typed(ctx, element)
	log.info("ELM UPDATE")
	element_update_control(ctx, element)
	log.info("ELM UPDATE DONE")
	return element
}

element_begin :: proc(ctx: ^Context, text: string, flags: Element_Flags) -> ^Element {
	element := element_get(ctx, text, flags + {.Is_Parent})
	element_cut_typed(ctx, element)
	// element_update_control(ctx, element)
	append(&ctx.parent_stack, element)
	return element
}

element_end :: proc(ctx: ^Context) {
	pop(&ctx.parent_stack)
}

////////////////////////////////////////////////////////////////////////////////
// CONTROL
////////////////////////////////////////////////////////////////////////////////

// true when the ctx mouse position is inside the given rectangle and the parent panel clip region
mouse_over :: proc(ctx: ^Context, bounds: Rect) -> bool {
	over := true
	if len(ctx.parent_stack) > 0 {
		parent := ctx.parent_stack[len(ctx.parent_stack) - 1]
		over = rect_contains(parent.bounds, ctx.mouse_position.x, ctx.mouse_position.y)
	}

	return rect_contains(bounds, ctx.mouse_position.x, ctx.mouse_position.y) && over
}

// true when the ctx mouse released bit_set is not empty
@(private)
mouse_released :: #force_inline proc(ctx: ^Context) -> bool {
	return ctx.mouse_released != {}
}

// true when the ctx mouse pressed bit_set is not empty
@(private)
mouse_pressed :: #force_inline proc(ctx: ^Context) -> bool {
	return ctx.mouse_pressed != {}
}

// true when the ctx mouse down/released bit_sets are empty
@(private)
mouse_up :: #force_inline proc(ctx: ^Context) -> bool {
	return ctx.mouse_down == {} && ctx.mouse_released == {}
}

// adjust the ctx.focus_id to the wanted id and keep track of click counting
set_focus :: proc(ctx: ^Context, id: Id) {
	if id == 0 && ctx.focus_id != 0 {
		ctx.focus_lost_id = ctx.focus_id
	}

	ctx.focus_id = id

	if id != 0 {
		// // update click count
		// last := ctx.click_timestamp
		// ctx.click_timestamp = time.now()
		// diff := time.diff(last, ctx.click_timestamp)

		// if ctx.click_last_id == id && diff < ctx.click_repeat_threshold {
		// 	ctx.click_count += 1
		// } else {
		// 	ctx.click_count = 1
		// }

		// ctx.click_last_id = id
	}

	// ctx.updated_focus = true
}

@(private)
element_should_be_ignored :: proc(element: ^Element) -> bool {
	p := element
	LIMIT :: 100
	check_index := 0

	for p != nil {
		if .Ignore_Self_And_Descendants in p.flags {
			return true
		}
		p = p.parent

		if check_index > 50 {
			// log.info("LIMIT", check_index)
		}
		check_index += 1
	}

	return .Ignore_Self in p.flags
}

// TODO tackle keeping hover == focus when held down
// updates the control element wether it should be hovered/focused
element_update_control :: proc(ctx: ^Context, element: ^Element) {
	log.info("UPD START")
	defer log.info("UPD END")

	if element_should_be_ignored(element) {
		return
	}

	mouseover := mouse_over(ctx, element.bounds)

	// // only allow dropdown to be interacted with when set
	// if ctx.dropdown_id != 0 {
	// 	if ctx.dropdown_id != panel.id {
	// 		return
	// 	}
	// }

	// if ctx.focus_id == id {
	// 	ctx.updated_focus = true
	// }
	// if .No_Interact in opt {
	// 	return
	// }

	if mouseover && mouse_up(ctx) {
		// if mouseover {
		ctx.hover_stack[ctx.hover_index] = element
		ctx.hover_index += 1
		ctx.hover_id = element.id
		// ctx.cursor = cursor
	}

	if ctx.focus_id == element.id {
		// ctx.cursor = cursor
		if mouse_released(ctx) && !mouseover {
			set_focus(ctx, 0)
		}
		if mouse_up(ctx) {
			set_focus(ctx, 0)
		}
	}

	if ctx.hover_id == element.id {
		// ctx.cursor = cursor
		if mouse_pressed(ctx) {
			set_focus(ctx, element.id)
		} else if !mouseover {
			ctx.hover_id = 0
		}
	}
}

/////////////////////////////////////////////////////////////////////
// element preparation
/////////////////////////////////////////////////////////////////////

element_margin :: proc(ctx: ^Context, margin: int) {
	ctx.next.cut_margin = margin
}

element_gap :: proc(ctx: ^Context, gap: int) {
	ctx.next.cut_gap = gap
}

element_cut :: proc(ctx: ^Context, direction: Cut_Direction, amount: int) {
	ctx.next.cut_direction = direction
	ctx.next.cut_amount = amount
	ctx.next.cut_percentage = 0
}

element_pct :: proc(ctx: ^Context, direction: Cut_Direction, amount: int) {
	ctx.next.cut_direction = direction
	ctx.next.cut_amount = 0
	ctx.next.cut_percentage = amount
}

element_fill :: proc(ctx: ^Context) {
	ctx.next.cut_direction = .Fill
}

element_text_align :: proc(ctx: ^Context, x, y: Text_Align) {
	ctx.next.text_align = {x, y}
}

element_text_xalign :: proc(ctx: ^Context, align: Text_Align) {
	ctx.next.text_align.x = align
}

element_text_yalign :: proc(ctx: ^Context, align: Text_Align) {
	ctx.next.text_align.y = align
}

element_set_bounds :: proc(ctx: ^Context, to: Rect) {
	ctx.next.bounds = to
	ctx.next.cut_direction = .None
}

element_set_bounds_relative :: proc(ctx: ^Context, to: Rect) {
	parent := ctx.parent_stack[len(ctx.parent_stack) - 1]
	ctx.next.cut_direction = .None
	ctx.next.bounds = parent.layout_start
	ctx.next.bounds.l += to.l
	ctx.next.bounds.r = ctx.next.bounds.l + (to.r - to.l)
	ctx.next.bounds.t += to.t
	ctx.next.bounds.b = ctx.next.bounds.t + (to.b - to.t)
}

@(private)
element_cut_size :: proc(element: ^Element, size: int) -> int {
	return(
		element.cut_percentage > 0 ? int(f32(size) * f32(element.cut_percentage) / 100) : element.cut_amount \
	)
}

// cut from a direction and its amount from the parent rect, apply a gap and return the resultant cut
element_cut_typed :: proc(ctx: ^Context, element: ^Element) {
	if len(ctx.parent_stack) == 0 || element.cut_direction == .None {
		element.layout = rect_margin(element.bounds, element.cut_margin)
		element.layout_start = element.layout

		if len(ctx.parent_stack) > 0 {
			parent := ctx.parent_stack[len(ctx.parent_stack) - 1]
			rect_inf_push(&parent.inf, element.bounds) // push raw rect to inf
		}

		return
	}

	parent := ctx.parent_stack[len(ctx.parent_stack) - 1]

	switch element.cut_direction {
	case .None:
	case .Left:
		amount := element_cut_size(element, parent.layout.r - parent.layout.l)
		element.bounds = rect_cut_left(&parent.layout, amount)
	case .Right:
		amount := element_cut_size(element, parent.layout.r - parent.layout.l)
		element.bounds = rect_cut_right(&parent.layout, amount)
	case .Top:
		amount := element_cut_size(element, parent.layout.b - parent.layout.t)
		element.bounds = rect_cut_top(&parent.layout, amount)
	case .Bottom:
		amount := element_cut_size(element, parent.layout.b - parent.layout.t)
		element.bounds = rect_cut_bottom(&parent.layout, amount)
	case .Fill:
		element.bounds = parent.layout
		parent.layout = {}
	}

	if parent.cut_gap > 0 {
		// TODO make this parent based setting? would need to store it with stack
		#partial switch element.cut_direction {
		case .None:
		case .Left:
			parent.layout.l += parent.cut_gap
		case .Right:
			parent.layout.r -= parent.cut_gap
		case .Top:
			parent.layout.t += parent.cut_gap
		case .Bottom:
			parent.layout.b -= parent.cut_gap
		}
	}

	element.clipped = rect_intersection(parent.layout_start, element.bounds)
	rect_inf_push(&parent.inf, element.bounds) // push raw rect to inf

	if .Is_Parent in element.flags {
		element.layout = rect_margin(element.bounds, element.cut_margin)
		element.layout_start = element.layout
		element.clipped = rect_intersection(parent.layout_start, element.layout_start)
		element.layout.t -= element.persistent.scroll.y
		element.layout.b -= element.persistent.scroll.y
	}

	return
}

/////////////////////////////////////////////////////////////////////
// input events
/////////////////////////////////////////////////////////////////////

// set the current mouse position
input_mouse_move :: proc(ctx: ^Context, x, y: int) {
	ctx.mouse_position = {x, y}
}

input_scroll :: proc(ctx: ^Context, x, y: int) {
	ctx.scroll_delta.x += x
	ctx.scroll_delta.y += y
}

// set the mouse position and set the wanted mouse button to down & pressed
input_mouse_down :: proc(ctx: ^Context, x, y: int, button: Mouse) {
	input_mouse_move(ctx, x, y)
	ctx.mouse_down += {button}
	ctx.mouse_pressed += {button}
}

// set the mouse position and set mouse button to released
input_mouse_up :: proc(ctx: ^Context, x, y: int, button: Mouse) {
	input_mouse_move(ctx, x, y)
	ctx.mouse_down -= {button}
	ctx.mouse_released += {button}
}

// set the current window size
input_window_size :: proc(ctx: ^Context, width, height: int) {
	ctx.window_size = {width, height}
}
