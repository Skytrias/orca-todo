package qwe

import "core:log"
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

// scrollbar_interaction :: proc() {

// }
