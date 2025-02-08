package qwe

Rect :: struct {
	l, r, t, b: int,
}

Cut_Direction :: enum {
	None, // dont cut this element
	Left,
	Right,
	Top,
	Bottom,
	Fill,
}

rect_cut_left :: proc(rect: ^Rect, amount: int) -> (res: Rect) {
	res = rect^
	res.r = rect.l + amount
	rect.l = res.r
	return
}

// cut the amount of pixels from the right side of the input rect and return the resultant cut
rect_cut_right :: proc(rect: ^Rect, amount: int) -> (res: Rect) {
	res = rect^
	res.l = rect.r - amount
	rect.r = res.l
	return
}

// cut the amount of pixels from the top side of the input rect and return the resultant cut
rect_cut_top :: proc(rect: ^Rect, amount: int) -> (res: Rect) {
	res = rect^
	res.b = rect.t + amount
	rect.t = res.b
	return
}

// cut the amount of pixels from the bottom side of the input rect and return the resultant cut
rect_cut_bottom :: proc(rect: ^Rect, amount: int) -> (res: Rect) {
	res = rect^
	res.t = rect.b - amount
	rect.b = res.t
	return
}

// cut horizontally the amount of % from the left side of the input rect and return the resultant rect
rect_cut_horizontal :: proc(rect: ^Rect, amount: int) -> (res: Rect) {
	a := clamp(f32(amount), 1, 99) / 100
	res = rect^
	res.r = rect.l + int(f32(rect.r - rect.l) * a)
	rect.l = res.r
	return
}

// cut vertically the amount of % from the top side of the input rect and return the resultant rect
rect_cut_vertical :: proc(rect: ^Rect, amount: int) -> (res: Rect) {
	a := clamp(f32(amount), 1, 99) / 100
	res = rect^
	res.b = rect.t + int(f32(rect.b - rect.t) * a)
	rect.t = res.b
	return
}

// true when x and y reside in the rect
rect_contains :: proc(a: Rect, x, y: int) -> bool {
	return a.l <= x && a.r > x && a.t <= y && a.b > y
}

rect_flat :: proc(rect: Rect) -> (x, y, w, h: f32) {
	x = f32(rect.l)
	y = f32(rect.t)
	w = f32(rect.r - rect.l)
	h = f32(rect.b - rect.t)
	return
}

// shrinks when value is positive, expands when negative
rect_margin :: proc(a: Rect, value: int) -> Rect {
	a := a
	a.l += value
	a.t += value
	a.r -= value
	a.b -= value
	return a
}

rect_intersection :: proc(a: Rect, b: Rect) -> Rect {
	return {l = max(a.l, b.l), r = min(a.r, b.r), t = max(a.t, b.t), b = min(a.b, b.b)}
}
