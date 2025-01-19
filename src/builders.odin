package src

import "core:log"
import "core:strings"
import "core:unicode/utf8"
import oc "core:sys/orca"

Style :: struct {
	using style: oc.ui_style,
	mask:        oc.ui_style_mask,
	box:         oc.ui_flags,
}

style_fullsize :: proc(xrelax: f32 = 1, yrelax: f32 = 1) -> (res: Style) {
	res.size = {
		{ .PARENT, 1, xrelax, 0 }, 
		{ .PARENT, 1, yrelax, 0 }
	}
	res.mask += oc.SIZE
        return
}

style_childrensize :: proc(minx: f32 = 0, miny: f32 = 0) -> (res: Style) {
	res.size = {
		{ kind = .CHILDREN, minSize = minx }, 
		{ kind = .CHILDREN, minSize = miny },
	}
	res.mask += oc.SIZE
        return
}

style_font :: proc(style: ^Style, font: oc.font) {
	style.font = font
        style.mask += {.FONT}
}

style_font_size :: proc(style: ^Style, size: f32) {
	style.fontSize = size
        style.mask += {.FONT_SIZE}
}

style_sizex_full :: proc(style: ^Style, value: f32 = 1, relax: f32 = 0) {
	style.size.x = {
		kind  = .PARENT,
		value = value,
		relax = relax,
	}
	style.mask += {.SIZE_WIDTH}
}

style_sizex :: proc(style: ^Style, value: f32, relax: f32 = 0) {
	style.size.x = {
		kind  = .PIXELS,
		value = value,
		relax = relax,
	}
	style.mask += {.SIZE_WIDTH}
}

style_sizemx :: proc(style: ^Style, value: f32, relax: f32 = 0) {
	style.size.x = {
		kind  = .PARENT_MINUS_PIXELS,
		value = value,
		relax = relax,
	}
	style.mask += {.SIZE_WIDTH}
}

style_sizey_full :: proc(style: ^Style, value: f32 = 1, relax: f32 = 0) {
	style.size.y = {
		kind  = .PARENT,
		value = value,
		relax = relax,
	}
	style.mask += {.SIZE_HEIGHT}
}

style_sizey :: proc(style: ^Style, value: f32, relax: f32 = 0) {
	style.size.y = {
		kind  = .PIXELS,
		value = value,
		relax = relax,
	}
	style.mask += {.SIZE_HEIGHT}
}

style_sizemy :: proc(style: ^Style, value: f32, relax: f32 = 0) {
	style.size.y = {
		kind  = .PARENT_MINUS_PIXELS,
		value = value,
		relax = relax,
	}
	style.mask += {.SIZE_HEIGHT}
}

style_layout :: proc(
                     style: ^Style,
                     axis: oc.ui_axis,
                     margin: [2]f32 = {},
                     spacing: f32 = 0,
                     ) {
	style.layout.axis = axis
        style.mask += {.LAYOUT_AXIS}
    
	if margin.x != 0 {
		style.layout.margin.x = margin.x
            style.mask += {.LAYOUT_MARGIN_X}
	}
    
	if margin.y != 0 {
		style.layout.margin.y = margin.y
            style.mask += {.LAYOUT_MARGIN_Y}
	}
    
	if spacing != 0 {
		style.layout.spacing = spacing
            style.mask += {.LAYOUT_SPACING}
	}
}

style_margin :: proc(
                     style: ^Style,
                     marginx: f32,
                     marginy: f32,
                     ) {
	style.layout.margin = { marginx, marginy }
	style.mask += oc.LAYOUT_MARGINS
}

style_align :: proc(style: ^Style, x, y: oc.ui_align) {
	style.layout.align = {x, y}
	style.mask += {.LAYOUT_ALIGN_X, .LAYOUT_ALIGN_Y}
}

style_alignx :: proc(style: ^Style, value: oc.ui_align) {
	style.layout.align.x = value
        style.mask += {.LAYOUT_ALIGN_X}
}

style_aligny :: proc(style: ^Style, value: oc.ui_align) {
	style.layout.align.y = value
        style.mask += {.LAYOUT_ALIGN_Y}
}

style_color :: proc(style: ^Style, color: oc.color) {
	style._color = color
        style.mask += {.COLOR}
}

style_bg_color :: proc(style: ^Style, color: oc.color) {
	style.bgColor = color
        style.mask += {.BG_COLOR}
	style.box += {.DRAW_BACKGROUND}
}

// both axis sizing for text
style_text :: proc(style: ^Style) {
	style.size = {
		{ kind = .TEXT },
		{ kind = .TEXT },
	}
	style.box += { .DRAW_TEXT, .CLIP }
	style.mask += { .SIZE_WIDTH, .SIZE_HEIGHT }
}

// single axis sizing for text
style_textx :: proc(style: ^Style) {
	style.size.x = { kind = .TEXT }
	style.box += { .DRAW_TEXT, .CLIP }
	style.mask += { .SIZE_WIDTH, .SIZE_HEIGHT }
}

// single axis sizing for text
style_texty :: proc(style: ^Style) {
	style.size.y = { kind = .TEXT }
	style.box += { .DRAW_TEXT, .CLIP }
	style.mask += { .SIZE_WIDTH, .SIZE_HEIGHT }
}

style_size_texty :: proc(style: ^Style) {
	style.size.y = { kind = .TEXT }
	style.box += { .CLIP }
	style.mask += { .SIZE_HEIGHT }
}

style_size_textx :: proc(style: ^Style) {
	style.size.x = { kind = .TEXT }
	style.box += { .CLIP }
	style.mask += { .SIZE_WIDTH }
}

// time should be above 0!
style_animate :: proc(style: ^Style, time: f32, mask: oc.ui_style_mask) {
	style.animationTime = time
        style.animationMask = mask
        style.mask += {.ANIMATION_TIME, .ANIMATION_MASK}
	style.box += {.HOT_ANIMATION, .ACTIVE_ANIMATION}
}

style_border :: proc(style: ^Style, size: f32, color: Maybe(oc.color) = nil) {
	style.borderSize = size
        style.mask += {.BORDER_SIZE}
    
	if c, ok := color.?; ok {
		style.borderColor = c
            style.mask += {.BORDER_COLOR}
	}
    
	style.box += {.DRAW_BORDER}
}

style_roundness :: proc(style: ^Style, roundness: f32) {
	style.roundness = roundness
        style.mask += {.ROUNDNESS}
}

style_float :: proc(style: ^Style, x, y: f32) {
	style.floatTarget = {x, y}
	style.floating = {true, true}
	style.mask += oc.FLOAT
}

style_next :: proc(style: Style) {
	oc.ui_style_next(style, style.mask)
}

style_before_on_hover :: proc(arena: ^oc.arena, style: Style) {
	pattern: oc.ui_pattern
        oc.ui_pattern_push(
                           arena,
                           &pattern,
                           {kind = .STATUS, status = {.HOVER}},
                           )
        oc.ui_style_match_before(pattern, style, style.mask)
}

style_before_on_hover_active :: proc(arena: ^oc.arena, style: Style) {
	pattern: oc.ui_pattern
        oc.ui_pattern_push(
                           arena,
                           &pattern,
                           {kind = .STATUS, status = {.ACTIVE}},
                           )
        oc.ui_pattern_push(
                           arena,
                           &pattern,
                           {op = .AND, kind = .STATUS, status = {.HOVER}},
                           )
        oc.ui_style_match_before(pattern, style, style.mask)
}

style_after :: proc(style: Style) {
	oc.ui_style_match_after(oc.ui_pattern_owner(), style, style.mask)
}

style_key_before :: proc(ui: ^oc.ui_context, key: string, style: Style) {
	pattern: oc.ui_pattern
        oc.ui_pattern_push(
                           &ui.frameArena,
                           &pattern,
                           {kind = .KEY, key = oc.ui_key_make_str8(key)},
                           )
        oc.ui_style_match_before(pattern, style, style.mask)
}

style_tag_before :: proc(ui: ^oc.ui_context, tag: oc.ui_tag, style: Style) {
	pattern: oc.ui_pattern
        oc.ui_pattern_push(&ui.frameArena, &pattern, {kind = .TAG, tag = tag})
        oc.ui_style_match_before(pattern, style, style.mask)
}

style_key_after :: proc(ui: ^oc.ui_context, key: string, style: Style) {
	pattern: oc.ui_pattern
        oc.ui_pattern_push(
                           &ui.frameArena,
                           &pattern,
                           {kind = .KEY, key = oc.ui_key_make_str8(key)},
                           )
        oc.ui_style_match_after(pattern, style, style.mask)
}

style_text_after :: proc(ui: ^oc.ui_context, name: string, style: Style) {
	pattern: oc.ui_pattern
        oc.ui_pattern_push(&ui.frameArena, &pattern, { kind = .OWNER })
        oc.ui_pattern_push(&ui.frameArena, &pattern, { kind = .TEXT, text = name })
        oc.ui_style_match_after(pattern, style, style.mask)
}

menu_label :: proc(ui: ^oc.ui_context, text: string) {
	style: Style
        style_sizey_full(&style)
        style_aligny(&style, .CENTER)
        style_key_after(ui, text, style)
        oc.ui_label_str8(text)
}

PANEL_FLAGS :: oc.ui_flags { .CLIP, .BLOCK_MOUSE, .OVERFLOW_ALLOW_X, .OVERFLOW_ALLOW_Y, .SCROLL_WHEEL_X, .SCROLL_WHEEL_Y }
PANEL_VERTICAL_FLAGS :: oc.ui_flags { .CLIP, .BLOCK_MOUSE, .OVERFLOW_ALLOW_Y, .OVERFLOW_ALLOW_X, .SCROLL_WHEEL_Y }
PANEL_HORIZONTAL_FLAGS :: oc.ui_flags { .CLIP, .BLOCK_MOUSE, .OVERFLOW_ALLOW_Y, .OVERFLOW_ALLOW_X, .SCROLL_WHEEL_X, }

custom_panel_begin :: proc(str: string, style_outer: Style, style_inner: Style, outer_flags := PANEL_FLAGS) -> (panel, contents: ^oc.ui_box) {
	{
		style := style_outer
            style.box += outer_flags
            oc.ui_style_next(style, style.mask)
            panel = oc.ui_box_begin_str8(str, style.box)
	}
    
	{
		style := style_inner
            style_sizex_full(&style, 1, 1)
            style_sizey_full(&style, 1, 1)
            oc.ui_style_next(style, style.mask)
            contents = oc.ui_box_begin_str8("contents", style.box)
	}
    
	return
}

custom_panel_end :: proc() {
	oc.ui_box_end() // contents
    
        panel := oc.ui_box_top()
        sig := oc.ui_box_sig(panel)
        
        contentsW := max(panel.childrenSum[0], panel.rect.w)
        contentsH := max(panel.childrenSum[1], panel.rect.h)
        
        contentsW = max(contentsW, 1)
        contentsH = max(contentsH, 1)
        
        scrollBarX: ^oc.ui_box
        scrollBarY: ^oc.ui_box
        
        needsScrollX := contentsW > panel.rect.w && .SCROLL_WHEEL_X in panel.flags
        needsScrollY := contentsH > panel.rect.h && .SCROLL_WHEEL_Y in panel.flags
        activated := false
        scrollerSize: f32 = 20
        
        if needsScrollX {
		thumbRatioX := panel.rect.w / contentsW
            scrollValueX := panel.scroll.x / (contentsW - panel.rect.w)
            
            oc.ui_style_next({ 
                                 size = {
                                     { .PARENT, 1, 0, 0 },
                                     { .PIXELS, scrollerSize, 0, 0 },
                                 },
                                 floating = true,
                                 floatTarget = { 0, panel.rect.h - scrollerSize },
                             }, oc.SIZE + oc.FLOAT)
            scrollBarX = oc.ui_scrollbar("scrollerX", thumbRatioX, &scrollValueX)
            
            panel.scroll.x = scrollValueX * (contentsW - panel.rect.w)
            if sig.hovering && !activated {
			oc.ui_box_activate(scrollBarX)
                activated = true
		}
	}
    
	if needsScrollY {
		thumbRatioY := panel.rect.h / contentsH
            scrollValueY := panel.scroll.y / (contentsH - panel.rect.h)
            spacerSize: f32 = needsScrollX ? scrollerSize : 0 // offset if x is also scrolling
        
            style := oc.ui_style {
			size = {
				{ .PIXELS, scrollerSize, 0, 0 },
				{ .PARENT_MINUS_PIXELS, spacerSize, 0, 0 },
			},
			floating = true,
			floatTarget = { panel.rect.w - scrollerSize, 0 },
		}
		oc.ui_style_next(style, oc.SIZE + oc.FLOAT)
            
            scrollBarY = oc.ui_scrollbar("scrollerY", thumbRatioY, &scrollValueY)
            panel.scroll.y = scrollValueY * (contentsH - panel.rect.h)
            
            if sig.hovering && !activated {
			oc.ui_box_activate(scrollBarY)
                activated = true
		}
	}
    
	panel.scroll.x = clamp(panel.scroll.x, 0, contentsW - panel.rect.w)
        panel.scroll.y = clamp(panel.scroll.y, 0, contentsH - panel.rect.h)
        
        oc.ui_box_end() // panel
}

Context_Menu_Options :: struct {
	menu_width: f32, // THIS IS TEMPORARY AS .CHILDREN size does not respect min sizes
	window_size: oc.vec2,
	follow: ^oc.rect, // which element to stick to
	mouse_offset: oc.vec2, // offset to the follow rect
	open: bool,
}

context_menu_begin :: proc(
                           ui: ^oc.ui_context, 
                           options: Context_Menu_Options,
                           ) -> (outside_clicked: bool) {
	is_closed := !options.open
        
        // total window box that blocks mouse or allows click to escape
        style: Style
        style_sizex(&style, options.window_size.x)
        style_sizey(&style, options.window_size.y)
        style_float(&style, 0, 0)
        style.box += { .BLOCK_MOUSE, .CLICKABLE }
	style_next(style)
        total := oc.ui_box_make_str8("contextmenu", style.box)
        oc.ui_box_set_closed(total, is_closed)
        
        sig := oc.ui_box_sig(total)
        if sig.clicked {
		outside_clicked = true
	}
    
	theme := ui.theme
        style = {}
	style.size = {
		{ kind = .PIXELS, value = options.menu_width }, 
		{ kind = .CHILDREN },
	}
	style.mask += oc.SIZE
        position := oc.vec2 { options.follow.x, options.follow.y }
	style_float(&style, position.x, position.y)
        style_layout(&style, .Y, { 4, 4 }, 2)
        style_bg_color(&style, theme.bg1)
        style_border(&style, 1, theme.elevatedBorder)
        style_roundness(&style, 4)
        style.box += { .BLOCK_MOUSE, .OVERLAY }
	style_next(style)
        
        menu := oc.ui_box_make_str8("panel", style.box)
        oc.ui_box_set_closed(menu, is_closed)
        oc.ui_box_push(menu)
        
        return
}

context_menu_end :: proc() {
	oc.ui_box_pop()
}

context_menu_spacer :: proc(name: string, height: f32 = 1) {
	style: Style
        style_sizex_full(&style, 1, 1)
        style_sizey(&style, height)
        style_bg_color(&style, oc.color_rgba(1, 1, 1, 0.2)) // TODO only works on dark theme
        style_roundness(&style, 1)
        style_next(style)
        oc.ui_box_make_str8(name, style.box)
}

context_menu_button :: proc(label: string) -> bool {
	ui := oc.ui_get_context()
        theme := ui.theme
        
        style: Style
        style_sizex_full(&style, 1, 1)
        style_texty(&style)
        style_color(&style, theme.text0)
        style_animate(&style, 0.1, style.mask)
        style_bg_color(&style, theme.bg1)
        style.box += { .CLICKABLE, .BLOCK_MOUSE }
	style_next(style)
        
        hover_style: Style
        style_color(&hover_style, theme.bg0)
        style_bg_color(&hover_style, oc.color_rgba(0.2, 0.5, 0.8, 1))
        style_before_on_hover(&ui.frameArena, hover_style)
        
        box := oc.ui_box_make_str8(label, style.box)
        sig := oc.ui_box_sig(box)
        return sig.clicked
}

i2builder :: proc(builder: ^strings.Builder, icon: rune) {
	bytes, size := utf8.encode_rune(icon)
        strings.write_bytes(builder, bytes[:size])
}

i2s :: proc(icon: rune) -> string {
	bytes, size := utf8.encode_rune(icon)
        return strings.clone(string(bytes[:size]), context.temp_allocator)
}

custom_menu_button :: proc(ui: ^oc.ui_context, key_display: string, key: oc.key_code, mods: oc.keymod_flags, label: string) -> oc.ui_sig {
	theme := ui.theme
        
        style: Style
        style_bg_color(&style, {})
        style_animate(&style, 0.5, style.mask)
        style_sizex(&style, 150)
        style_sizey(&style, 20)
        style_layout(&style, .X, { 8, 4 })
        style.box += { .BLOCK_MOUSE, .CLICKABLE }
	style_next(style)
        
        style_hover: Style
        style_bg_color(&style_hover, theme.fill0)
        style_before_on_hover(&ui.frameArena, style_hover)
        box := oc.ui_container(label, style.box)
        
        style = {}
	style_sizex_full(&style, 1, 1)
        style_sizey_full(&style)
        style_aligny(&style, .CENTER)
        style.box += { .DRAW_TEXT }
	style_next(style)
        
        oc.ui_box_make_str8(label, style.box)
        
        builder := strings.builder_make(0, 8, context.temp_allocator)
        
        // NOTE font specific!
        // attach icons to be rendered
        if .SHIFT in mods {
		i2builder(&builder, 0xe5f2)
	}
	if .ALT in mods {
		i2builder(&builder, 0xeae8)
	}
	if .CMD in mods {
		i2builder(&builder, 0xeae7)
	}
	
	// only render icons when needed
	if len(builder.buf) != 0 {
		style = {}
		style_font(&style, ed.font_icons)
            style_size_textx(&style)
            style_sizey_full(&style)
            style_color(&style, theme.text3)
            style_aligny(&style, .CENTER)
            style.box += { .DRAW_TEXT }
		style_next(style)
            oc.ui_box_make_str8(strings.to_string(builder), style.box)
	}
    
	// render the key display
	style = {}
	style_size_textx(&style)
        style_sizey_full(&style)
        style_color(&style, theme.text3)
        style_aligny(&style, .CENTER)
        style.box += { .DRAW_TEXT }
	style_next(style)
        oc.ui_box_make_str8(key_display, style.box)
        
        return button_behaviour(box)
}

button_behaviour :: proc(box: ^oc.ui_box) -> oc.ui_sig {
	sig := oc.ui_box_sig(box)
        
        if sig.hovering {
		oc.ui_box_set_hot(box, true)
            
            if sig.dragging {
			oc.ui_box_activate(box)
		}
	} else {
		oc.ui_box_set_hot(box, false)
	}
    
	if !sig.hovering || !sig.dragging {
		oc.ui_box_deactivate(box)
	}
    
	return sig
}

style_box_make :: proc(ui: ^oc.ui_context, label: string, style, style_hover, style_active: Style, flags: oc.ui_flags = {}) -> ^oc.ui_box {
	style := style
        style.box += flags
        if style_hover != {} || style_active != {} {
		style.box += { .HOT_ANIMATION, .ACTIVE_ANIMATION }
	}
	style_next(style)
        
        if style_hover != {} {
		style_before_on_hover(&ui.frameArena, style_hover)
	}
	
	if style_active != {} {
		style_before_on_hover_active(&ui.frameArena, style_active)
	}
    
	return oc.ui_box_make_str8(label, style.box)
}

custom_button :: proc(ui: ^oc.ui_context, stylesheet: ^Stylesheet, label: string) -> oc.ui_sig {
	style := stylesheet_fetch(stylesheet, "button")
        style_hover := stylesheet_fetch(stylesheet, "button.hover")
        style_active := stylesheet_fetch(stylesheet, "button.active")
        box := style_box_make(ui, label, style, style_hover, style_active, { .CLICKABLE })
        return button_behaviour(box)
}
