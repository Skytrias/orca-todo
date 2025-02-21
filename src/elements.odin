package src

import "core:fmt"
import "core:log"
import "core:math"
import oc "core:sys/orca"
import "hsluv"
import "qwe"

Panel_Flag :: enum {
	Rounded,
	Background,
	Clip_Outer,
	Border_Left,
	Border_Right,
	Border_Top,
	Border_Bottom,
	Shadow,
}
Panel_Flags :: bit_set[Panel_Flag]

@(private)
clip_push_bounds :: proc(bounds: qwe.Rect) {
	x, y, w, h := qwe.rect_flat(bounds)
	oc.clip_push(x, y, w, h)
}

panel_begin :: proc(
	ctx: ^qwe.Context,
	name: string,
	flags: Panel_Flags,
	element_flags: qwe.Element_Flags = {},
) -> ^qwe.Element {
	element := qwe.element_begin(ctx, name, element_flags)

	rounded := .Rounded in flags
	if .Shadow in flags {
		oc.set_color(oc.color_srgba(0, 0, 0, 0.5))
		x, y, w, h := qwe.rect_flat(qwe.rect_margin(element.bounds, -5))
		oc.rounded_rectangle_fill(x, y, w, h, 10)
	}

	if .Background in flags {
		// color := ed.theme.border_highlight
		// color.z = color.z * element.hover_children
		// color.a = color.a * element.hover_children
		element_background(element.bounds, ed.theme.panel1, rounded)
	}

	if .Border_Left in flags {
		color_set(ed.theme.border)
		oc.set_width(ed.theme.border_width * 2)
		oc.move_to(f32(element.bounds.l), f32(element.bounds.t))
		oc.line_to(f32(element.bounds.l), f32(element.bounds.b))
		oc.stroke()
	} else if .Border_Right in flags {
		color_set(ed.theme.border)
		oc.set_width(ed.theme.border_width * 2)
		oc.move_to(f32(element.bounds.r), f32(element.bounds.t))
		oc.line_to(f32(element.bounds.r), f32(element.bounds.b))
		oc.stroke()
	} else if .Border_Top in flags {
		color_set(ed.theme.border)
		oc.set_width(ed.theme.border_width * 2)
		oc.move_to(f32(element.bounds.l), f32(element.bounds.t))
		oc.line_to(f32(element.bounds.r), f32(element.bounds.t))
		oc.stroke()
	} else if .Border_Bottom in flags {
		color_set(ed.theme.border)
		oc.set_width(ed.theme.border_width * 2)
		oc.move_to(f32(element.bounds.l), f32(element.bounds.b))
		oc.line_to(f32(element.bounds.r), f32(element.bounds.b))
		oc.stroke()
	}

	if .Clip_Outer in flags {
		clip_push_bounds(element.bounds)
	} else {
		clip_push_bounds(element.clipped)
	}

	// element_border(element.bounds, color, ed.theme.border_highlight_width, rounded)
	return element
}

panel_end :: proc(ctx: ^qwe.Context) {
	qwe.element_end(ctx)
	oc.clip_pop()
}

panel_overlay_begin :: proc(
	ctx: ^qwe.Context,
	name: string,
	hover: f32,
	flags: qwe.Element_Flags = {},
) -> ^qwe.Element {
	element := qwe.element_begin(ctx, name, flags)

	rounded := true
	oc.set_color(oc.color_srgba(0, 0, 0, 0.5 * hover))
	x, y, w, h := qwe.rect_flat(qwe.rect_margin(element.bounds, -5))
	oc.rounded_rectangle_fill(x, y, w, h, 10)

	panel_range := ed.theme.panel2
	panel_range.a *= hover
	element_background(element.bounds, panel_range, rounded)

	clip_push_bounds(element.bounds)

	// element_border(element.bounds, color, ed.theme.border_highlight_width, rounded)
	return element
}

spacer :: proc(ctx: ^qwe.Context, name: string, amount: int, direction: qwe.Cut_Direction) {
	qwe.element_cut(ctx, direction, amount)
	element := qwe.element_make(ctx, name, {})
}

color_display :: proc(ctx: ^qwe.Context, name: string, range: [4]f32) {
	element := qwe.element_make(ctx, name, {})
	element_background_and_border(element.bounds, range, ed.theme.border, true)
}

label_simple :: proc(ctx: ^qwe.Context, text: string, flags: qwe.Element_Flags = {}) {
	element := qwe.element_make(ctx, text, flags)

	// render
	element_text(element.text_align, element.bounds, element.text_label, ed.theme.text1)
}

label_alpha :: proc(
	ctx: ^qwe.Context,
	text: string,
	alpha: f32,
	panning: f32,
	flags: qwe.Element_Flags = {},
) {
	element := qwe.element_make(ctx, text, flags)

	// render
	range := ed.theme.text1
	range.a = min(range.a * alpha, 1)

	text_metrics := oc.font_text_metrics(ed.font_regular, ed.font_size, element.text_label)

	// in size
	width := f32(element.bounds.r - element.bounds.l)
	x: f32
	y := text_positiony(element.text_align.y, element.bounds, text_metrics)
	if text_metrics.ink.w < width {
		x = text_positionx(element.text_align.y, element.bounds, text_metrics)
	} else {
		unit := math.sin(panning)
		step := abs(unit) * (text_metrics.ink.w - width + 40)
		// log.info("DRAW SPAN", panning, step)
		x = f32(element.bounds.l) - step + 20
	}

	color_set(range)
	oc.text_fill(x, y, element.text_label)
}

label_hover :: proc(
	ctx: ^qwe.Context,
	text: string,
	flags: qwe.Element_Flags = {},
) -> ^qwe.Element {
	element := qwe.element_make(ctx, text, flags)

	range := ed.theme.button
	range.a *= element.hover
	element_background(element.bounds, range, false)

	// render
	element_text(element.text_align, element.bounds, element.text_label, ed.theme.text1)
	return element
}

label_highlight :: proc(
	ctx: ^qwe.Context,
	text: string,
	state: bool,
	flags: qwe.Element_Flags = {},
) -> ^qwe.Element {
	log.info("LABEL HIGHLIGHT")
	defer log.info("LABEL HIGHLIGHT END")

	element := qwe.element_make(ctx, text, flags)
	element.highlight_state = state

	// render
	text_metrics := oc.font_text_metrics(ed.font_regular, ed.font_size, element.text_label)
	x, y := text_position(element.text_align, element.bounds, text_metrics)
	text_color := color_blend(
		color_get(ed.theme.text1),
		color_get(ed.theme.border_highlight),
		element.highlight,
	)
	oc.set_color(text_color)
	oc.text_fill(x, y, element.text_label)

	return element
}

label_underlined :: proc(
	ctx: ^qwe.Context,
	text: string,
	alignx: qwe.Text_Align,
	underline_alpha: f32,
	flags: qwe.Element_Flags = {},
) {
	qwe.element_text_xalign(ctx, alignx)
	element := qwe.element_make(ctx, text, flags)

	text_metrics := oc.font_text_metrics(ed.font_regular, ed.font_size, element.text_label)
	x, y := text_position(element.text_align, element.bounds, text_metrics)
	text_color := ed.theme.text1
	text_color.a = underline_alpha * 0.5 + 0.5
	color_set(text_color)
	oc.text_fill(x, y, element.text_label)

	oc.set_width(2)
	color_set(text_color)
	xoff := x + text_metrics.logical.x
	yoff := y + text_metrics.logical.y + text_metrics.logical.h
	oc.move_to(xoff, yoff)
	oc.line_to(xoff + text_metrics.logical.w, yoff)
	oc.stroke()
}

button :: proc(ctx: ^qwe.Context, text: string, flags: qwe.Element_Flags = {}) -> bool {
	qwe.element_text_align(ctx, .Center, .Center)
	element := qwe.element_make(ctx, text, flags)

	// render with my customized render calls
	color := ed.theme.button
	color.z = min(color.z + element.hover * 0.1, 1)
	element_background_and_border(element.bounds, color, ed.theme.border, true)
	element_text(element.text_align, element.bounds, element.text_label, ed.theme.text1)

	// interaction
	return qwe.button_interaction(ctx, element)
}

slider :: proc(
	ctx: ^qwe.Context,
	value: ^f32,
	low, high, step: f32,
	text: string,
	format := "%f",
) {
	qwe.element_text_align(ctx, .Center, .Center)
	element := qwe.element_make(ctx, text, {})

	// interaction
	qwe.slider_interaction(ctx, element, value, low, high, step)

	// render
	color := ed.theme.base
	color.z = min(color.z + element.hover * 0.1, 1)
	element_background_and_border(element.bounds, color, ed.theme.border, true)
	text := fmt.tprintf(format, value^)
	element_text(element.text_align, element.bounds, text, ed.theme.text1)

	w := 20 // styling?
	x := int((value^ - low) * f32((element.bounds.r - element.bounds.l) - w) / (high - low))
	thumb := qwe.Rect {
		element.bounds.l + x,
		element.bounds.l + x + w,
		element.bounds.t,
		element.bounds.b,
	}
	thumb = qwe.rect_margin(thumb, 5)

	color = ed.theme.button
	color.z = min(color.z + element.hover * 0.1, 1)
	element_background_and_border(thumb, color, ed.theme.border, true)
}

hsva_slider :: proc(ctx: ^qwe.Context, range: ^[4]f32, name: string) {
	qwe.element_cut(ctx, .Top, 50)
	qwe.element_gap(ctx, 0)
	qwe.element_margin(ctx, 0)

	panel_name := fmt.tprintf("panel%s", name)
	inner := panel_begin(ctx, panel_name, {})
	defer panel_end(ctx)

	qwe.element_cut(ctx, .Left, 150)
	qwe.element_text_align(ctx, .End, .Center)
	label_simple(ctx, name)

	qwe.element_cut(ctx, .Right, 40)
	color_display(ctx, "color", range^)

	width := inner.layout.r - inner.layout.l
	qwe.element_cut(ctx, .Left, int(f32(width) / 3))
	slider(ctx, &range.x, 0, 360, 1, "hue", "hue: %.0f")
	slider(ctx, &range.y, 0, 1, 0.01, "sat", "sat: %.2f")
	slider(ctx, &range.z, 0, 1, 0.01, "lum", "lum: %.2f")
	// slider(ctx, &range.w, 0, 1, 0.01, "alpha", "alpha: %.2f")
}

vscrollbar :: proc(ctx: ^qwe.Context, name: string) {
	parent := ctx.parent_stack[len(ctx.parent_stack) - 1]
	temp := parent.bounds
	to := qwe.rect_cut_right(&temp, 30)

	// NOTE very hacky way to turn of clip, push custom clip to see scrollbar
	// turn off the temp clip again to the parent clip
	oc.clip_pop()
	clip_push_bounds(to)
	defer {
		oc.clip_pop()
		clip_push_bounds(parent.clipped)
	}

	qwe.element_set_bounds(ctx, to)
	element := qwe.element_make(ctx, name, {.Scroll_Ignore})

	full := parent.inf.b - parent.inf.t
	diff := qwe.scrollbar_maximum_page_diff(parent)

	if diff > 0 {
		x, y, w, h := qwe.rect_flat(element.bounds)
		base := ed.theme.scrollbar_base
		alpha := 0.75 * parent.hover_children
		base.a = alpha
		// base.z = min(base.z + parent.hover_children * 0.1, 1)
		color_set(base)
		oc.rectangle_fill(x, y, w, h)
	}

	qwe.scrollbar_interaction(ctx, parent, element)
}

color_blend :: proc(a, b: oc.color, unit: f32) -> (res: oc.color) {
	res.colorSpace = a.colorSpace
	for i in 0 ..< 4 {
		res.c[i] = math.lerp(a.c[i], b.c[i], unit)
	}
	return res
}

task_panel_begin :: proc(ctx: ^qwe.Context, text_hash: string) -> ^qwe.Element {
	element := qwe.element_begin(ctx, text_hash, {})
	clip_push_bounds(element.clipped)
	return element
}

border_width_animate :: proc(element: ^qwe.Element) -> f32 {
	return max(
		ed.theme.border_width * (1 - element.hover_children),
		ed.theme.border_highlight_width * (element.hover_children),
	)
}

task_panel_end :: proc(ctx: ^qwe.Context, text_display: string) {
	element := ctx.parent_stack[len(ctx.parent_stack) - 1]
	range := ed.theme.border_highlight
	range.a = 0.75
	range.a *= element.hover_children
	border_width := border_width_animate(element)
	element_border(element.bounds, range, border_width, false)

	render := text_display
	text_metrics := oc.font_text_metrics(ed.font_regular, ed.font_size, render)
	x, y := text_position(element.text_align, element.bounds, text_metrics)
	color_set(ed.theme.panel1)
	oc.rounded_rectangle_fill(
		x - ed.theme.text_margin.x,
		y - text_metrics.ink.h - ed.theme.text_margin.y,
		text_metrics.ink.w + ed.theme.text_margin.x * 2,
		text_metrics.ink.h + ed.theme.text_margin.y * 2,
		ed.theme.border_radius * 2,
	)
	text_color := color_blend(
		color_get(ed.theme.text2),
		color_get(ed.theme.border_highlight),
		element.hover_children,
	)
	oc.set_color(text_color)
	oc.text_fill(x, y, render)

	panel_end(ctx)
}

task_small :: proc(ctx: ^qwe.Context, task: ^Task) -> ^qwe.Element {
	log.info("TASK SMALL MAKE")
	defer log.info("TASK SMALL RET")
	element := qwe.element_make(ctx, string(task.id[:]), {})
	defer log.info("TASK SMALL DONE")

	// bounds := qwe.rect_margin(element.bounds, 1)
	// hue := hash_hue(element.text_label)
	// element_background(bounds, {hue, 0.65, 0.75, 1}, false)
	// if ed.task_drag == task.id {
	// 	element_border(bounds, ed.theme.border_highlight, ed.theme.border_width * 2, false)
	// }
	return element
}

task_small_drag :: proc(ctx: ^qwe.Context, task_label: string, text: string) -> ^qwe.Element {
	element := qwe.element_make(ctx, text, {.Ignore_Self})
	hue := hash_hue(task_label)
	element_background(qwe.rect_margin(element.bounds, 1), {hue, 0.65, 0.75, 0.75}, false)
	return element
}

rect_fill_hovered :: proc(bounds: qwe.Rect, hover: f32) {
	x, y, w, h := qwe.rect_flat(bounds)
	x -= hover
	y -= hover
	w += hover * 2
	h += hover * 2
	oc.rectangle_fill(x, y, w, h)
}

hover_button :: proc(ctx: ^qwe.Context, text: string, flags: qwe.Element_Flags = {}) -> bool {
	qwe.element_text_align(ctx, .Center, .Center)
	element := qwe.element_make(ctx, text, flags)

	// render with my customized render calls
	color := ed.theme.panel2
	color.z = min(color.z + element.hover * 0.1, 1)
	color.a *= element.hover
	element_background(element.bounds, color, false)
	text_color := ed.theme.text1
	text_color.a *= element.hover
	element_text(element.text_align, element.bounds, element.text_label, text_color)

	// interaction
	return qwe.button_interaction(ctx, element)
}

label_hover_range :: proc(ctx: ^qwe.Context, text: string) -> ^qwe.Element {
	element := qwe.element_make(ctx, text, {})
	range := ed.theme.border_highlight
	range.a = 0.75
	range.a *= element.hover_children
	border_width := border_width_animate(element)
	element_border(element.bounds, range, border_width, false)
	element_text(element.text_align, element.bounds, element.text_label, ed.theme.text2)
	return element
}

/////////////////////////////////////////////////////////////////////
// Helpers
/////////////////////////////////////////////////////////////////////

color_hsluv :: proc(range: [4]f32) -> [4]f32 {
	r, g, b := hsluv.hsluv_to_rgb(f64(range.x), f64(range.y) * 100, f64(range.z) * 100)
	return {f32(r), f32(g), f32(b), f32(range.a)}
}

color_get :: proc(range: [4]f32) -> oc.color {
	color := color_hsluv(range)
	return oc.color_srgba(color.r, color.g, color.b, color.a)
}

color_set :: proc(range: [4]f32) {
	color := color_hsluv(range)
	oc.set_color_srgba(color.r, color.g, color.b, color.a)
}

@(private)
element_background :: proc(bounds: qwe.Rect, background: [4]f32, rounded: bool) {
	theme := &ed.theme
	x, y, w, h := qwe.rect_flat(bounds)
	color_set(background)

	if ed.theme.border_radius != 0 && rounded {
		oc.rounded_rectangle_fill(x, y, w, h, ed.theme.border_radius * 2)
	} else {
		oc.rectangle_fill(x, y, w, h)
	}
}

@(private)
element_border :: proc(bounds: qwe.Rect, border: [4]f32, border_width: f32, rounded: bool) {
	x, y, w, h := qwe.rect_flat(bounds)
	x += border_width / 2
	y += border_width / 2
	w -= border_width
	h -= border_width
	color_set(border)
	oc.set_width(border_width)

	if ed.theme.border_radius != 0 && rounded {
		oc.rounded_rectangle_stroke(x, y, w, h, ed.theme.border_radius)
	} else {
		oc.rectangle_stroke(x, y, w, h)
	}
}

@(private)
element_background_and_border :: proc(
	bounds: qwe.Rect,
	background, border: [4]f32,
	rounded: bool,
) {
	element_background(bounds, background, rounded)
	element_border(bounds, border, ed.theme.border_width, rounded)
}

text_positionx :: proc(
	align: qwe.Text_Align,
	bounds: qwe.Rect,
	text_metrics: oc.text_metrics,
) -> f32 {
	switch align {
	case .Start:
		return f32(bounds.l) + ed.theme.text_margin.x
	case .Center:
		return f32(bounds.l) - text_metrics.ink.w / 2 + f32(bounds.r - bounds.l) / 2
	case .End:
		return f32(bounds.r) - text_metrics.ink.w - ed.theme.text_margin.x
	}
	return 0
}

text_positiony :: proc(
	align: qwe.Text_Align,
	bounds: qwe.Rect,
	text_metrics: oc.text_metrics,
) -> f32 {
	switch align {
	case .Start:
		return f32(bounds.t) + text_metrics.ink.h + ed.theme.text_margin.y
	case .Center:
		return f32(bounds.t) + text_metrics.ink.h / 2 + f32(bounds.b - bounds.t) / 2
	case .End:
		return f32(bounds.b) - ed.theme.text_margin.y
	}
	return 0
}

@(private)
text_position :: proc(
	align: [2]qwe.Text_Align,
	bounds: qwe.Rect,
	text_metrics: oc.text_metrics,
) -> (
	x, y: f32,
) {
	x = text_positionx(align.x, bounds, text_metrics)
	y = text_positiony(align.y, bounds, text_metrics)
	return
}

@(private)
element_text :: proc(align: [2]qwe.Text_Align, bounds: qwe.Rect, render: string, color: [4]f32) {
	text_metrics := oc.font_text_metrics(ed.font_regular, ed.font_size, render)
	x, y := text_position(align, bounds, text_metrics)
	color_set(color)
	oc.text_fill(x, y, render)
}
