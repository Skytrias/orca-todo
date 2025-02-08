package qwe

import "core:math"

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

was_focused :: proc(ctx: ^Context, element: ^Element) -> bool {
	return ctx.focus_lost_id == element.id
}

scrollbar_final :: proc(element: ^Element) -> int {
	final := element.layout.b - element.layout.t
	return final + element.cut_gap
}

scrollbar_interaction :: proc(ctx: ^Context, parent, element: ^Element) {
	final := scrollbar_final(parent)

	if ctx.focus_id == element.id && ctx.mouse_down == {.Left} {
		parent.scroll.y += ctx.mouse_delta.y
	}

	if mouse_over(ctx, parent.bounds) {
		parent.scroll.y += ctx.scroll_delta.y
	}

	parent.scroll.y = clamp(parent.scroll.y, 0, max(-final, 0))
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

// scrollbar_interaction :: proc() {

// }
