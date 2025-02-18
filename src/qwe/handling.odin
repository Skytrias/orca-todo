package qwe

import "core:log"
import "core:math"
import "core:mem"

button_interaction :: proc(ctx: ^Context, element: ^Element) -> bool {
	return ctx.mouse_released == {.Left} && ctx.focus_id == element.id
}

left_clicked :: button_interaction
right_clicked :: proc(ctx: ^Context, element: ^Element) -> bool {
	return ctx.mouse_released == {.Right} && ctx.focus_id == element.id
}

dragging :: proc(ctx: ^Context, element: ^Element) -> bool {
	return ctx.mouse_down == {.Left} && ctx.focus_id == element.id
}

drag_set :: proc(ctx: ^Context, type: string, data: $T) {
	// log.info("DRAG SET WITH type:", type, "size:", size_of(T))
	ctx.dragndrop.drag_type = type
	root := cast(^T)&ctx.dragndrop.drag_bytes[0]
	root^ = data
}

drop_set :: proc(ctx: ^Context, type: string, data: $T) {
	// log.info("DROP SET WITH type:", type, "size:", size_of(T))
	root := new(T, mem.arena_allocator(&ctx.dragndrop.drop_arena))
	root^ = data
	ctx.dragndrop.stack[ctx.dragndrop.stack_index] = {
		type      = type,
		data      = cast(rawptr)root,
		data_size = size_of(T),
	}
	ctx.dragndrop.stack_index += 1
}

drag_started :: proc(ctx: ^Context, element: ^Element) -> bool {
	return ctx.mouse_pressed == {.Left} && ctx.focus_id == element.id
}

drag_ended :: proc(ctx: ^Context, element: ^Element) -> bool {
	return(
		ctx.mouse_released == {.Left} &&
		(ctx.focus_id == element.id || ctx.focus_lost_id == element.id) \
	)
}

drag_over :: proc(ctx: ^Context, element: ^Element) -> bool {
	return(
		ctx.focus_id == 0 &&
		ctx.focus_lost_id != 0 &&
		rect_contains(element.clipped, ctx.mouse_position.x, ctx.mouse_position.y) \
	)
}

overlapping :: proc(ctx: ^Context, element: ^Element) -> bool {
	return rect_contains(element.clipped, ctx.mouse_position.x, ctx.mouse_position.y)
}

was_focused :: proc(ctx: ^Context, element: ^Element) -> bool {
	return ctx.focus_lost_id == element.id
}

scrollbar_maximum_page_diff :: proc(element: ^Element) -> int {
	maximum := element.inf.b - element.inf.t
	page := element.bounds.b - element.bounds.t
	return maximum - page
}

scrollbar_interaction :: proc(ctx: ^Context, parent, element: ^Element) {
	if ctx.focus_id == element.id && ctx.mouse_down == {.Left} {
		parent.scroll.y += ctx.mouse_delta.y
	}

	if mouse_over(ctx, parent.bounds) {
		parent.scroll.y += ctx.scroll_delta.y
	}

	diff := scrollbar_maximum_page_diff(parent)
	orig := parent.scroll.y
	parent.scroll.y = clamp(parent.scroll.y, 0, max(diff, 0))
}

slider_interaction :: proc(
	ctx: ^Context,
	element: ^Element,
	value: ^f32,
	low, high, step: f32,
) -> bool {
	v := value^
	previous := v

	if ctx.focus_id == element.id && ctx.mouse_down == {.Left} {
		width := f32(element.bounds.r - element.bounds.l)
		v = low + f32(ctx.mouse_position.x - element.bounds.l) * (high - low) / width
		if step != 0.0 {
			v = math.floor((v + step / 2) / step) * step
		}
	}
	// clamp and store value, update res
	v = clamp(v, low, high)
	value^ = v
	return previous != v
}
