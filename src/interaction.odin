package src

import "core:fmt"
import "core:strings"
import "core:log"
import oc "core:sys/orca"

TASK_MIN_SIZE :: 150
TASK_GAP :: 2
TASK_TEXT_SIZE :: 22

editor_ui :: proc(editor: ^Editor, scratch: oc.arena_scope) {
    style: Style
        
        style_font(&style, editor.font_regular)
        oc.ui_frame(editor.window_size, style, style.mask)
        
        editor_ui_menus(editor, scratch)
        editor_ui_all(editor, scratch)
        editor_task_menu(editor, scratch)
}

editor_ui_menus :: proc(editor: ^Editor, scratch: oc.arena_scope) {
	oc.ui_menu_bar("menubar")
        
        last_call: string
        for call in editor.shortcuts {
		if call.group == "Commands" {
			continue
		}
        
		if call.group != last_call {
			if last_call != "" {
				oc.ui_menu_end()
			}
            
			group_name := strings.clone_to_cstring(call.group, context.temp_allocator)
                oc.ui_menu_begin(group_name)
		}
        
		if custom_menu_button(&editor.ui_context, call.key_display, call.key, call.mods, call.name).pressed {
			call.call(editor)
		}
        
		last_call = call.group
	}
    
	if last_call != "" {
		oc.ui_menu_end()
	}
}

editor_task_context_menu :: proc(editor: ^Editor) {
	task := editor.show_task_context
        editor.show_task_context_options.menu_width = 100
        editor.show_task_context_options.window_size = editor.window_size
        editor.show_task_context_options.open = task != nil
        outside_clicked := context_menu_begin(&editor.ui_context, editor.show_task_context_options)
        defer context_menu_end()
        
        hide: bool
        if context_menu_button("Edit") {
		editor_task_modify(editor, task)
            hide = true
	}
	if context_menu_button("Clone") {
		editor_task_clone(editor, task)
            hide = true
	}
	context_menu_spacer("Spacer")
        if context_menu_button("Remove") {
		editor_task_remove(editor, task)
            hide = true
	}
    
	if outside_clicked || hide {
		editor.show_task_context = nil
	}
}

editor_ui_all :: proc(editor: ^Editor, scratch: oc.arena_scope) {
	style: Style
        style_sizex_full(&style, 1, 1)
        style_sizey_full(&style, 1, 1)
        style_inner: Style
        style_layout(&style_inner, .X, {}, 0)
        custom_panel_begin("main", style, style_inner, PANEL_FLAGS)
        defer custom_panel_end()
        
	{
		style = {}
		style_sizex(&style, 200)
            style_sizey_full(&style)
            style_bg_color(&style, editor.ui_context.theme.bg0)
            style_border(&style, 2, editor.ui_context.theme.border)
            style_inner = {}
		style_layout(&style_inner, .Y, 10, 5)
            custom_panel_begin("sidebar", style, style_inner, PANEL_FLAGS)
            defer custom_panel_end()
            
            editor_fetch_states(editor)
            editor_fetch_tags(editor)
            
            editor_ui_filters(&editor.ui_context, &editor.stylesheet, "States", &editor.filters_state, editor.all_states)
            editor_ui_filters(&editor.ui_context, &editor.stylesheet, "Tags", &editor.filters_tag, editor.all_tags)
            
            if editor.show_task_context != nil {
			task := editor.show_task_context
                
                style = {}
			style_sizey_full(&style, 1, 1)
                style_next(style)
                oc.ui_box_make_str8("spacer", style.box)
                
                style = {}
			style_sizex_full(&style)
                style_after(style)
                if oc.ui_button("DEL").pressed {
				editor_task_remove(editor, task)
                    editor.show_task_context = nil
			}
		}
	}
    
	style = {}
	style_sizex_full(&style, 1, 1)
        style_sizey_full(&style, 1, 1)
        style_inner = {}
	custom_panel_begin("task_main", style, style_inner, PANEL_FLAGS)
        defer custom_panel_end()
        
        editor_task_text_display(editor)
        
        style = {}
	style_sizex_full(&style, 1, 1)
        style_sizey_full(&style, 1, 1)
        style_inner = {}
	style_layout(&style_inner, .Y, {40, 0}, TASK_GAP)
        style_bg_color(&style_inner, editor.ui_context.theme.bg0)
        panel, contents := custom_panel_begin("tasks", style, style_inner, PANEL_VERTICAL_FLAGS + { .CLICKABLE })
        defer custom_panel_end()
        
        task_iter_count, task_size := get_task_iter_count(TASK_MIN_SIZE, panel.rect.w, contents.style.layout.margin.x, contents.style.layout.spacing)
        mods := oc.key_mods(&editor.ui_context.input)
        
        sig := oc.ui_box_sig(panel)
        if sig.doubleClicked {
		editor_toggle_menu(editor, nil)
	}
	
	editor_ui_tasks(editor, panel.scroll, task_size, task_iter_count)
        
        // editor_task_context_menu(editor)
}

builder_text_box :: proc(editor: ^Editor, box: ^Task_Box, scratch: oc.arena_scope, name: string, box_name: cstring) -> bool {
	theme := editor.ui_context.theme
        box_content := strings.to_string(box.builder)
        invalid := oc.color_rgba(1, 0, 0, 1)
        
        style: Style
        style_border(&style, 2, len(box_content) == 0 ? invalid : theme.elevatedBorder)
        style_animate(&style, 0.5, style.mask)
        style_after(style)
        
        box.key_frame = oc.ui_key_make_str8(string(box_name))
        path: oc.str8_list
        oc.str8_list_push(scratch.arena, &path, string(box_name))
        oc.str8_list_push(scratch.arena, &path, "text")
        box.key_text = oc.ui_key_make_path(path)
        
        style = {}
	style_sizex_full(&style, 1)
        style_sizey(&style, 30)
        style_next(style)
        
        res := oc.ui_text_box(box_name, scratch.arena, box_content)
        if res.changed {
		strings.builder_reset(&box.builder)
            strings.write_string(&box.builder, res.text)
	}
    
	// floaty
	{
		textbox := oc.ui_box_lookup_key(box.key_frame)
            style: Style
            active_or_filled := textbox.active || len(box_content) > 0
            style_color(&style, len(box_content) == 0 && !textbox.active ? invalid : theme.text0)
            xgoal := active_or_filled ? textbox.rect.x : textbox.rect.x + 14
            ygoal := active_or_filled ? textbox.rect.y - 20 : textbox.rect.y + 6
            style_float(&style, xgoal, ygoal)
            style_animate(&style, 0.25, style.mask)
            style_text(&style)
            style_next(style)
            oc.ui_box_make_str8(name, style.box)
	}
    
	return res.accepted
}

task_line_begin :: proc(ui: ^oc.ui_context, stylesheet: ^Stylesheet, index: int) {
    style := stylesheet_fetch(stylesheet, "task_line")
        test := fmt.tprintf("padded %d", index)
        style_next(style)
        oc.ui_box_begin_str8(test, style.box)
}

editor_ui_filters :: proc(ui: ^oc.ui_context, stylesheet: ^Stylesheet, filter_name: string, filters: ^map[string]bool, unique: map[string]int) {
	style: Style
        style_sizex_full(&style)
        style_after(style)
        oc.ui_label_str8(filter_name)
        
        for key, value in unique {
		selected := filters[key]
            
            style := stylesheet_fetch(stylesheet, selected ? "button_filter1" : "button_filter0")
            box := style_box_make(ui, key, style, {}, {}, { .CLICKABLE, .DRAW_TEXT })
            sig := button_behaviour(box)
            
            if sig.pressed {
			filters[key] = !selected
		}
        
		if sig.rightPressed {
			editor_select_or_solo_filter(filters, key)
		}
	}
}

task_draw :: proc "c" (box: ^oc.ui_box, data: rawptr) {
	task := cast(^Task) data
        
        // oc.set_color(box.style.bgColor)
        oc.set_gradient(
                        .LINEAR, 
                        box.style._color, box.style.bgColor, 
                        box.style._color, box.style.bgColor,
                        )
        oc.rounded_rectangle_fill(box.rect.x, box.rect.y, box.rect.w, box.rect.h, box.style.roundness)
}

// calculate how many tasks can be displayed in a single row
get_task_iter_count :: proc(
                            task_size, panel_width, marginx, spacingx: f32
                            ) -> (iter_count: int, final_task_size: f32) {
	full_width := panel_width - marginx*2
        suggested_count := full_width / task_size
        spacing_size := spacingx * (suggested_count - 1)
        
        iter_count_float := max((full_width - spacing_size) / task_size, 1)
        iter_count = int(iter_count_float)
        task_space := iter_count_float * task_size
        final_task_size = task_space / f32(iter_count)
        return
}

editor_ui_tasks :: proc(editor: ^Editor, parent_scroll: oc.vec2, task_size: f32, task_iter_count: int) {
	style: Style
        
        // Tasks Display
        tasks := editor_filtered_tasks(editor)
        
        for task, task_index in tasks {
		if task_index % task_iter_count == 0 {
			if task_index != 0 {
				oc.ui_box_end()
			}
			task_line_begin(&editor.ui_context, &editor.stylesheet, task_index)
		}
        
		state_color1 := hsluv_hash_color(task.state, 10, 0.95, 0.5, 1)
            state_color2 := hsluv_hash_color(task.state, 10, 1, 0.7, 1)
            tag_color1 := hsluv_hash_color(task.tag, 33000, 0.75, 0.4, 1)
            tag_color2 := hsluv_hash_color(task.tag, 33000, 0.95, 0.6, 1)
            
            style = {}
		// style_sizex_full(&style, 1, 1)
		style_layout(&style, .Y, { 0, task_size/4 })
            style_alignx(&style, .CENTER)
            style_bg_color(&style, state_color1)
            style_color(&style, tag_color1)
            style_border(&style, 0, oc.color_rgba(0, 0, 0, 1))
            style_animate(&style, 0.25, style.mask)
            style_sizex(&style, task_size)
            style_sizey(&style, task_size)
            style.box += { .CLICKABLE, .BLOCK_MOUSE, .DRAW_PROC }
		style.box -= { .DRAW_BACKGROUND, .DRAW_FOREGROUND }
		style_next(style)
            
            test_style: Style
            style_bg_color(&test_style, tag_color2)
            style_color(&test_style, state_color2)
            style_border(&test_style, 3, oc.color_rgba(1, 1, 1, 1))
            style_before_on_hover(&editor.ui_context.frameArena, test_style)
            
            // show selection on modify
            if task == editor.show_task_modify || task == editor.show_task_context {
			style_border(&test_style, 3, oc.color_rgba(0, 1, 0, 1))
                tag := oc.ui_tag_make_str8("modifying")
                style_tag_before(&editor.ui_context, tag, test_style)
                oc.ui_tag_next_str8("modifying")
		}
        
		task_id := fmt.tprintf("%s%d", task.content, task_index)
            box := oc.ui_container(task_id, style.box)
            oc.ui_tag_box_str8(box, "task")
            oc.ui_box_set_draw_proc(box, task_draw, task)
            sig := oc.ui_box_sig(box)
            
            if sig.doubleClicked {
			editor_task_modify(editor, task)
		}
		
		if sig.rightPressed {
			editor.show_task_context = task
                editor.show_task_context_options.follow = &box.rect
                editor.show_task_context_options.mouse_offset = sig.mouse
		}
        
		if task.state != "" {
			task_label_colored("state", &task.state)
		}
        
		if task.tag != "" {
			task_label_colored("tag", &task.tag)
		}
	}
    
	if len(tasks) > 0 {
		oc.ui_box_end()
	}
}

editor_task_text_display :: proc(editor: ^Editor) {
	// Text Display
	box := editor.ui_context.hovered
        text: string
        
        if box != nil {
		first := cast(^oc.ui_tag_elt) box.tags.last
            tag := oc.ui_tag_make_str8("task")
            if first.tag.hash == tag.hash {
			task := cast(^Task) box.drawData
                text = task.content
                editor.hovered_task_text = task.content
		}
	}
    
    stylesheet := &editor.stylesheet
        ui := &editor.ui_context
        style := stylesheet_fetch(stylesheet, "text_display_container")
        style.box += { .OVERLAY }
	style_next(style)
        oc.ui_container("text display", style.box) // TODO(Skytrias): container support would be good
    
        style = stylesheet_fetch(stylesheet, "text_display")
        // TODO(Skytrias): could be done with two stylesheets + inheritance
        color := ui.theme.text0
        if editor.hovered_task_text != text {
		color.a = 0
	}
    style_color(&style, color)
        style_after(style)
        oc.ui_label_str8(editor.hovered_task_text)
}

editor_task_menu :: proc(editor: ^Editor, scratch: oc.arena_scope) {
	if !editor.show_task_menu {
		return
	}
    
    ui := &editor.ui_context
        stylesheet := &editor.stylesheet
        
        // NOTE(Skytrias): cant be converted due to window size
        style: Style
        style_sizex(&style, editor.window_size.x, 0)
        style_sizey(&style, editor.window_size.y, 0)
        style_float(&style, 0, 0)
        color := oc.color_srgba(0, 0, 0, 0.95)
        style_bg_color(&style, color)
        style_after(style)
        
        style_inner := stylesheet_fetch(stylesheet, "task_menu_panel")
        style_text_after(&editor.ui_context, "contents", style_inner)
        oc.ui_panel("hover", style.box)
        
        style = stylesheet_fetch(stylesheet, "task_menu_title")
        style_after(style)
        oc.ui_label_str8(editor.show_task_modify != nil ? "Modifying Task" : "Creating New Task")
        
        submit: bool
        submit |= builder_text_box(editor, &editor.temp_content, scratch, "Content", "box1")
        submit |= builder_text_box(editor, &editor.temp_state, scratch, "State", "box2")
        submit |= builder_text_box(editor, &editor.temp_tag, scratch, "Tag", "box3")
        
        theme := editor.ui_context.theme
        
	{
        style = stylesheet_fetch(stylesheet, "theme_picker")
            style_next(style)
            oc.ui_container("theme", style.box)
            oc.ui_button("Testing BUILTIN")
            custom_button(&editor.ui_context, &editor.stylesheet, "Testing CUSTOM")
            color_sliders(&editor.ui_context, "white", &theme.white)
            color_sliders(&editor.ui_context, "primary", &theme.primary)
            color_sliders(&editor.ui_context, "primaryHover", &theme.primaryHover)
            color_sliders(&editor.ui_context, "primaryActive", &theme.primaryActive)
            color_sliders(&editor.ui_context, "border", &theme.border)
            color_sliders(&editor.ui_context, "fill0", &theme.fill0)
            color_sliders(&editor.ui_context, "fill1", &theme.fill1)
            color_sliders(&editor.ui_context, "fill2", &theme.fill2)
            color_sliders(&editor.ui_context, "bg0", &theme.bg0)
            color_sliders(&editor.ui_context, "bg1", &theme.bg1)
            color_sliders(&editor.ui_context, "bg2", &theme.bg2)
            color_sliders(&editor.ui_context, "bg3", &theme.bg3)
            color_sliders(&editor.ui_context, "bg4", &theme.bg4)
            color_sliders(&editor.ui_context, "text0", &theme.text0)
            color_sliders(&editor.ui_context, "text1", &theme.text1)
            color_sliders(&editor.ui_context, "text2", &theme.text2)
            color_sliders(&editor.ui_context, "text3", &theme.text3)
	}
    
	if submit {
		if editor_accept_task_changes(editor) {
			editor_toggle_menu(editor, nil)
		}
	}
    
    // show buttons to accept shit
	if editor.show_task_modify != nil {
		style = stylesheet_fetch(stylesheet, "vspacer")
            style_box_make(ui, "spacer", style, {}, {})
            
            // horizontal buttons
		{
			style = {}
			style_sizex_full(&style)
                style_layout(&style, .X, {}, 5)
                style_next(style)
                oc.ui_container("button_row", {})
                
                if oc.ui_button("Accept").pressed {
				editor_accept_task_changes(editor)
                    editor_toggle_menu(editor, nil)
			}
            
			style = {}
			style_sizex_full(&style, 1, 1)
                style_next(style)
                oc.ui_box_make_str8("spacer2", style.box)
                
                if oc.ui_button("Cancel").pressed {
				editor_toggle_menu(editor, nil)
			}
		}
	}
}

draw_task_label_colored :: proc "c" (box: ^oc.ui_box, data: rawptr) {
	text := cast(^string) data
        oc.set_color(box.style._color)
        oc.set_font(box.style.font)
        oc.set_font_size(box.style.fontSize)
        oc.set_width(1)
        // oc.rectangle_stroke(box.rect.x, box.rect.y, box.rect.w, box.rect.h)
    
        metrics := oc.font_text_metrics(box.style.font, box.style.fontSize, text^)
        x2 := box.rect.x + box.rect.w/2 - metrics.ink.w/2
        y2 := box.rect.y + metrics.ink.h - metrics.ink.y
        oc.text_fill(x2, y2, text^)
}

task_label_colored :: proc(name: string, label: ^string) {
	style: Style
        style_color(&style, oc.color_rgba(0.05, 0.05, 0.05, 1))
        style_sizex_full(&style)
        style_sizey(&style, TASK_TEXT_SIZE+10)
        style_font_size(&style, TASK_TEXT_SIZE)
        style.box += { .DRAW_PROC }
	style_next(style)
        box := oc.ui_box_make_str8(name, style.box)
        oc.ui_box_set_draw_proc(box, draw_task_label_colored, label)
}

Slider :: struct {
	value: ^f32,
	text_display: string,
}

draw_slider_sub :: proc "c" (box: ^oc.ui_box, data: rawptr) {
	slider := cast(^Slider) data
        oc.set_color(box.style.bgColor)
        oc.rectangle_fill(box.rect.x, box.rect.y, box.rect.w, box.rect.h)
        
        oc.set_width(box.style.borderSize)
        oc.set_color(box.style.borderColor)
        oc.rectangle_stroke(box.rect.x, box.rect.y, box.rect.w, box.rect.h)
        
        oc.set_color(box.style._color)
        oc.set_width(2)
        xgoal := box.rect.x + slider.value^ * box.rect.w
        oc.move_to(xgoal, box.rect.y)
        oc.line_to(xgoal, box.rect.y+box.rect.h)
        oc.stroke()
        
        metrics := oc.font_text_metrics(box.style.font, box.style.fontSize, slider.text_display)
        
        oc.set_color(box.style._color)
        oc.text_fill(
                     box.rect.x + box.rect.w/2 - metrics.ink.w/2, 
                     box.rect.y - metrics.ink.y + metrics.ink.h/2, 
                     slider.text_display)
}

slider_f32 :: proc(ui: ^oc.ui_context, name: string, value: ^f32) {
	theme := ui.theme
        formatted_text := fmt.tprintf("%d", u8(value^ * 255))
        slider := new(Slider, context.temp_allocator)
        slider^ = Slider {
		value = value,
		text_display = formatted_text,
	}
	
	style: Style
        style_bg_color(&style, theme.bg3)
        style_color(&style, theme.primary)
        style_animate(&style, 0.5, style.mask)
        style_border(&style, 2, theme.border)
        style_sizex_full(&style, 1, 1)
        style_sizey_full(&style, 1)
        style_alignx(&style, .CENTER)
        style.box += { .DRAW_PROC, .CLICKABLE }
	style_next(style)
        
        style_hover: Style
        style_bg_color(&style_hover, theme.bg2)
        style_color(&style_hover, theme.primaryHover)
        style_before_on_hover(&ui.frameArena, style_hover)
        
        style_active: Style
        style_bg_color(&style_active, theme.bg1)
        style_color(&style_active, theme.primaryActive)
        style_before_on_hover_active(&ui.frameArena, style_active)
        
        box := oc.ui_box_make_str8(name, style.box)
        oc.ui_box_set_draw_proc(box, draw_slider_sub, slider)
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
    
	if sig.dragging {
		x := clamp(sig.mouse.x, 0, box.rect.w)
            xunit := x / box.rect.w
            value^ = xunit
	}
}

color_sliders :: proc(ui: ^oc.ui_context, name: string, color: ^oc.color) {
	theme := ui.theme
        
        style: Style
        style_sizex_full(&style)
        style_sizey(&style, 20)
        style_layout(&style, .X, 0, 5)
        style_next(style)
        oc.ui_container(name, style.box)
        
        // draw fixed size label
        style = {}
	style_sizex(&style, 100)
        style_sizey_full(&style)
        style_align(&style, .END, .CENTER)
        style.box += { .DRAW_TEXT, .CLIP }
	style_next(style)
        oc.ui_box_make_str8(name, style.box)
        
        // draw r g b a components
        names := [?]string { "r", "g", "b", "a" }
	for i in 0..<4 {
		color_value := &color.c[i]
            color_name := names[i]
            slider_f32(ui, color_name, color_value)
	}
    
	// draw color
	style = {}
	style_sizex_full(&style, 1, 1)
        style_sizey_full(&style, 1)
        style_bg_color(&style, color^)
        style_next(style)
        oc.ui_box_make_str8("color", style.box)
}