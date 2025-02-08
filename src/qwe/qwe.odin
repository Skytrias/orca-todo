package qwe

import "core:hash"
import "core:log"
import "core:strings"

// TODO scale

Id :: u32
MAX_HOVER :: 256

Mouse :: enum {
	Left,
	Right,
	Middle,
}

Mouse_Buttons :: bit_set[Mouse]

Context :: struct {
	// element storage
	elements:               map[Id]Element,

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
}

Element_Flag :: enum {
	Is_Parent,
	Ignore_Self,
	// Ignore_Descendents,
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

	// cut info
	cut_direction:      Cut_Direction,
	cut_percentage:     int,
	cut_amount:         int,
	cut_gap:            int,
	cut_margin:         int,

	// frame info
	frame_active:       int,

	// animation
	hover_children:     f32,
	hover_children_ran: bool,
	hover:              f32,
	focus:              f32,

	// scroll
	scroll:             [2]int,
}

Text_Align :: enum {
	Start,
	Center,
	End,
}

init :: proc(ctx: ^Context) {
	ctx.elements = make(map[Id]Element, 512)
	ctx.parent_stack = make([dynamic]^Element, 0, 128)
}

destroy :: proc(ctx: ^Context) {
	delete(ctx.elements)
	delete(ctx.parent_stack)
}

begin :: proc(ctx: ^Context) {
	ctx.frame_count += 1
	ctx.spawn_index += 1
	clear(&ctx.parent_stack)

	ctx.mouse_delta = ctx.mouse_position - ctx.mouse_last_position

	// clear hover info
	ctx.hover_index = 0
	ctx.hover_stack[0] = nil

	element_set_bounds(ctx, {0, ctx.window_size.x, 0, ctx.window_size.y})
	ctx.window = element_begin(ctx, "!root!", {})
}

@(private)
animate_unit :: proc(value: ^f32, dt: f32, increase: bool) {
	add := increase ? dt : -dt
	value^ = clamp(value^ + add, 0, 1)
}

end :: proc(ctx: ^Context, dt: f32) {
	element_end(ctx)

	for id, &element in &ctx.elements {
		element.hover_children_ran = false
	}

	// update animations in elements themselves
	for id, &element in &ctx.elements {
		animate_unit(&element.hover, dt, element.id == ctx.hover_id)
		animate_unit(&element.focus, dt, element.id == ctx.focus_id)

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
	for id, &element in &ctx.elements {
		animate_unit(&element.hover_children, dt, element.hover_children_ran)
	}

	ctx.mouse_pressed = {}
	ctx.mouse_released = {}
	ctx.scroll_delta = {}
	ctx.mouse_last_position = ctx.mouse_position

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
	// get the id
	left, match, right := strings.partition(text, "##")
	if right == "" {
		right = left
	}
	id := id_get_bytes(ctx, transmute([]byte)right)

	// create the element if it doesnt exist
	if id not_in ctx.elements {
		ctx.elements[id] = {
			id = id,
		}
	}

	// set defaults
	res := &ctx.elements[id]
	res.text_label = left
	res.text_hash = right
	res.frame_active = ctx.frame_count
	res.cut_direction = ctx.next.cut_direction
	res.cut_amount = ctx.next.cut_amount
	res.cut_percentage = ctx.next.cut_percentage
	res.cut_gap = ctx.next.cut_gap
	res.cut_margin = ctx.next.cut_margin
	res.text_align = ctx.next.text_align
	res.flags = flags
	res.bounds = ctx.next.bounds
	res.clipped = ctx.next.bounds

	// get last parent
	if len(ctx.parent_stack) > 0 {
		parent := ctx.parent_stack[len(ctx.parent_stack) - 1]
		res.parent = parent
	}

	ctx.spawn_index += 1
	return res
}

element_make :: proc(ctx: ^Context, text: string, flags: Element_Flags) -> ^Element {
	element := element_get(ctx, text, flags)
	element_cut_typed(ctx, element)
	element_update_control(ctx, element)
	return element
}

element_begin :: proc(ctx: ^Context, text: string, flags: Element_Flags) -> ^Element {
	element := element_get(ctx, text, flags + {.Is_Parent})
	element_cut_typed(ctx, element)
	element_update_control(ctx, element)
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
	// if id == 0 && ctx.focus_id != 0 {
	// 	ctx.focus_lost_id = ctx.focus_id
	// }

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
	// for p != nil {
	// 	if .Ignore in p.flags {
	// 		return true
	// 	}
	// 	p = p.parent
	// }
	// return false
	return .Ignore_Self in p.flags
}

// TODO tackle keeping hover == focus when held down
// updates the control element wether it should be hovered/focused
element_update_control :: proc(ctx: ^Context, element: ^Element) {
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

	if .Is_Parent in element.flags {
		element.layout = rect_margin(element.bounds, element.cut_margin)
		element.layout_start = element.layout
		element.clipped = rect_intersection(parent.layout_start, element.layout_start)
		element.layout.t -= element.scroll.y
		element.layout.b -= element.scroll.y
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

/////////////////////////////////////////////////////////////////////
// helpers
/////////////////////////////////////////////////////////////////////

is_hovered :: proc(ctx: ^Context, element: ^Element) -> bool {
	return ctx.hover_id == element.id
}
