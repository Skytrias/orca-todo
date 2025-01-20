package src

import "core:log"
import "core:strings"
import "core:strconv"
import "core:unicode/utf8"
import oc "core:sys/orca"

Stylesheet :: struct {
    src: string,
    styles: map[string]Style, // class to built style
    theme_colors: map[string]^oc.color, // theme color name to color
    palette_colors: map[string]^oc.color, // palette color name to color
}

stylesheet_read_size_kind :: proc(style: ^Style, class_name: string, index: int, text: string) {
    kind: oc.ui_size_kind
        size: f32
        find_index: int
        
        // read pixel size kind
        find_index = strings.index(text, "px")
        if find_index != -1 {
        left := text[:find_index]
            size = f32(strconv.atof(left))
            kind = .PIXELS 
    }
    
    // read text size kind
    find_index = strings.index(text, "tx")
        if find_index != -1 {
        left := text[:find_index]
            size = f32(strconv.atof(left))
            kind = .TEXT
            style.box += { .DRAW_TEXT, .CLIP }
    }
    
    // read parent size
    find_index = strings.index(text, "parent")
        set_parent := false
        if find_index != -1 {
        left := text[:find_index]
            size = f32(strconv.atof(left))
            kind = .PARENT
            set_parent = true
    }
    
    if size != 0 {
        style.size[index].kind = kind
            style.size[index].value = size
    }
    
    if index == 0 {
        style.mask += { .SIZE_WIDTH }
    } else {
        style.mask += { .SIZE_HEIGHT }
    }
    
    if set_parent {
        log.info("FINAL STYLE", class_name, style)
    }
}

stylesheet_read_align :: proc(style: ^Style, index: int, text: string) {
    switch text {
        case "center", "CENTER": style.layout.align[index] = .CENTER
            case "start", "START": style.layout.align[index] = .START
            case "end", "END": style.layout.align[index] = .END
    }
	style.mask += { index == 0 ? .LAYOUT_ALIGN_X : .LAYOUT_ALIGN_Y }
}

stylesheet_read_relax :: proc(style: ^Style, index: int, text: string) {
    if relax, ok := strconv.parse_f32(text); ok {
        style.size[index].relax = relax
            log.info("RELAX", style)
    }
}

stylesheet_read_layout_axis :: proc(style: ^Style, text: string) {
    switch text {
        case "x", "X": 
            style.layout.axis = .X
            case "y", "Y": 
            style.layout.axis = .Y
    }
    
    style.mask += { .LAYOUT_AXIS }
}

stylesheet_read_margin :: proc(style: ^Style, index: int, text: string) {
    value, ok := strconv.parse_f32(text)
        
        if ok {
        style.layout.margin[index] = value
            style.mask += { index == 0 ? .LAYOUT_MARGIN_X : .LAYOUT_MARGIN_Y }
    }
}

stylesheet_init :: proc(stylesheet: ^Stylesheet, src: string, theme: ^oc.ui_theme) {
    stylesheet.src = src
        stylesheet_colors_init(stylesheet, theme)
        
        iter := src
        class_name: string
        class_style: Style
        for line in strings.split_lines_iterator(&iter) {
        if len(line) == 0 {
            continue
        }
        
        first := line[0]
            if first == '#' {
            if class_name != "" && class_style != {} {
                stylesheet.styles[class_name] = class_style
            }
            
            class_style = {}
            class_name = strings.trim_space(line[1:])
        } else {
            head, mid, tail := strings.partition(line, "=")
                head = strings.trim_space(head)
                tail = strings.trim_space(tail)
                
                switch head {
                case "color": 
                    style_color(&class_style, stylesheet_read_color(stylesheet, tail))
                    
                    case "bgColor", "background": 
                    style_bg_color(&class_style, stylesheet_read_color(stylesheet, tail))
                    
                    case "borderColor", "border": 
                    class_style.borderColor = stylesheet_read_color(stylesheet, tail)
                    class_style.mask += { .BORDER_COLOR }
                
                case "borderSize":
                    if size, ok := strconv.parse_f32(tail); ok {
                    style_border(&class_style, size)
                }
                
                // TODO fonts by name?
                // case "font": class_style._color = {}
                
                case "fontSize": 
                    if size, ok := strconv.parse_f32(tail); ok {
                    style_font_size(&class_style, size)
                }
                
                case "spacing":
                    if size, ok := strconv.parse_f32(tail); ok {
                    class_style.layout.spacing = size
                        class_style.mask += { .LAYOUT_SPACING }
                }
                
                case "layout":
                    stylesheet_read_layout_axis(&class_style, tail)
                    
                    case "sizex":
                    stylesheet_read_size_kind(&class_style, class_name, 0, tail)
                    
                    case "sizey":
                    stylesheet_read_size_kind(&class_style, class_name, 1, tail)
                    
                    case "relaxx":
                    stylesheet_read_relax(&class_style, 0, tail)
                    
                    case "relaxy":
                    log.info("READ Y", tail)
                    stylesheet_read_relax(&class_style, 1, tail)
                    
                    case "alignx":
                    stylesheet_read_align(&class_style, 0, tail)
                    
                    case "aligny":
                    stylesheet_read_align(&class_style, 1, tail)
                    
                    case "marginx":
                    stylesheet_read_margin(&class_style, 0, tail)
                    
                    case "marginy":
                    stylesheet_read_margin(&class_style, 1, tail)
                    
                    case "animation":
                    if animationTime, ok := strconv.parse_f32(tail); ok {
                    style_animate(&class_style, animationTime, class_style.mask)
                }
            }
        }
    }
    
    if class_name != "" && class_style != {} {
        stylesheet.styles[class_name] = class_style
    }
}

@(private)
base16_to_float :: proc(text: string) -> (value: f32, ok: bool) {
    read_value: uint
        read_value, ok = strconv.parse_uint(text, 16)
        value = f32(read_value) / 255
        return
}

@(private)
rgb_read :: proc(text: string) -> (color: [3]f32, ok: bool) {
    if len(text) != 6 {
        return
    }
    
    color.r = base16_to_float(text[:2]) or_return
        color.g = base16_to_float(text[2:4]) or_return
        color.b = base16_to_float(text[4:6]) or_return
        ok = true
        return
}

@(private)
rgba_read :: proc(text: string) -> (color: [4]f32, ok: bool) {
    if len(text) != 8 {
        return
    }
    
    color.r = base16_to_float(text[:2]) or_return
        color.g = base16_to_float(text[2:4]) or_return
        color.b = base16_to_float(text[4:6]) or_return
        color.a = base16_to_float(text[6:8]) or_return
        ok = true
        return
}

@(private)
stylesheet_read_color :: proc(stylesheet: ^Stylesheet, read: string) -> oc.color {
    // try to find the color by name first
    if result, found := stylesheet.theme_colors[read]; found {
        return result^
    }
    
    // try to read a 16 based color
    if len(read) > 0 {
        first := read[0]
            
            // try to read rgba out
            if first == '#' {
            rgb, ok1 := rgb_read(read[1:])
                if ok1 {
                return { { rgb.r, rgb.g, rgb.b, 1 }, .RGB }
            }
            rgba, ok2 := rgba_read(read[1:]) 
                if ok2 {
                return { { rgba.r, rgba.g, rgba.b, rgba.a }, .RGB }
            }
        }
    }
    
    return {}
}

stylesheet_fetch :: proc(stylesheet: ^Stylesheet, name: string) -> Style {
    output, found := stylesheet.styles[name]
        
        if found {
        return output
    } else {
        log.info("STYLE NOOoOOOT FOUND BY", name)
    }
    
    return {}
}

stylesheet_colors_init :: proc(stylesheet: ^Stylesheet, theme: ^oc.ui_theme) {
    stylesheet.theme_colors = make(map[string]^oc.color, 128)
        stylesheet.theme_colors["white"] = &theme.white
        stylesheet.theme_colors["primary"] = &theme.primary
        stylesheet.theme_colors["primaryHover"] = &theme.primaryHover
        stylesheet.theme_colors["primaryActive"] = &theme.primaryActive
        stylesheet.theme_colors["border"] = &theme.border
        stylesheet.theme_colors["fill0"] = &theme.fill0
        stylesheet.theme_colors["fill1"] = &theme.fill1
        stylesheet.theme_colors["fill2"] = &theme.fill2
        stylesheet.theme_colors["bg0"] = &theme.bg0
        stylesheet.theme_colors["bg1"] = &theme.bg1
        stylesheet.theme_colors["bg2"] = &theme.bg2
        stylesheet.theme_colors["bg3"] = &theme.bg3
        stylesheet.theme_colors["bg4"] = &theme.bg4
        stylesheet.theme_colors["text0"] = &theme.text0
        stylesheet.theme_colors["text1"] = &theme.text1
        stylesheet.theme_colors["text2"] = &theme.text2
        stylesheet.theme_colors["text3"] = &theme.text3
        
        stylesheet.palette_colors = make(map[string]^oc.color, 128)
        stylesheet.palette_colors["red1"] = &theme.palette.red1
        stylesheet.palette_colors["red2"] = &theme.palette.red2
        stylesheet.palette_colors["red3"] = &theme.palette.red3
        stylesheet.palette_colors["red4"] = &theme.palette.red4
        stylesheet.palette_colors["red5"] = &theme.palette.red5
        stylesheet.palette_colors["red6"] = &theme.palette.red6
        stylesheet.palette_colors["red7"] = &theme.palette.red7
        stylesheet.palette_colors["red8"] = &theme.palette.red8
        stylesheet.palette_colors["red9"] = &theme.palette.red9
        stylesheet.palette_colors["orange0"] = &theme.palette.orange0
        stylesheet.palette_colors["orange1"] = &theme.palette.orange1
        stylesheet.palette_colors["orange2"] = &theme.palette.orange2
        stylesheet.palette_colors["orange3"] = &theme.palette.orange3
        stylesheet.palette_colors["orange4"] = &theme.palette.orange4
        stylesheet.palette_colors["orange5"] = &theme.palette.orange5
        stylesheet.palette_colors["orange6"] = &theme.palette.orange6
        stylesheet.palette_colors["orange7"] = &theme.palette.orange7
        stylesheet.palette_colors["orange8"] = &theme.palette.orange8
        stylesheet.palette_colors["orange9"] = &theme.palette.orange9
        stylesheet.palette_colors["amber0"] = &theme.palette.amber0
        stylesheet.palette_colors["amber1"] = &theme.palette.amber1
        stylesheet.palette_colors["amber2"] = &theme.palette.amber2
        stylesheet.palette_colors["amber3"] = &theme.palette.amber3
        stylesheet.palette_colors["amber4"] = &theme.palette.amber4
        stylesheet.palette_colors["amber5"] = &theme.palette.amber5
        stylesheet.palette_colors["amber6"] = &theme.palette.amber6
        stylesheet.palette_colors["amber7"] = &theme.palette.amber7
        stylesheet.palette_colors["amber8"] = &theme.palette.amber8
        stylesheet.palette_colors["amber9"] = &theme.palette.amber9
        stylesheet.palette_colors["yellow0"] = &theme.palette.yellow0
        stylesheet.palette_colors["yellow1"] = &theme.palette.yellow1
        stylesheet.palette_colors["yellow2"] = &theme.palette.yellow2
        stylesheet.palette_colors["yellow3"] = &theme.palette.yellow3
        stylesheet.palette_colors["yellow4"] = &theme.palette.yellow4
        stylesheet.palette_colors["yellow5"] = &theme.palette.yellow5
        stylesheet.palette_colors["yellow6"] = &theme.palette.yellow6
        stylesheet.palette_colors["yellow7"] = &theme.palette.yellow7
        stylesheet.palette_colors["yellow8"] = &theme.palette.yellow8
        stylesheet.palette_colors["yellow9"] = &theme.palette.yellow9
        stylesheet.palette_colors["lime0"] = &theme.palette.lime0
        stylesheet.palette_colors["lime1"] = &theme.palette.lime1
        stylesheet.palette_colors["lime2"] = &theme.palette.lime2
        stylesheet.palette_colors["lime3"] = &theme.palette.lime3
        stylesheet.palette_colors["lime4"] = &theme.palette.lime4
        stylesheet.palette_colors["lime5"] = &theme.palette.lime5
        stylesheet.palette_colors["lime6"] = &theme.palette.lime6
        stylesheet.palette_colors["lime7"] = &theme.palette.lime7
        stylesheet.palette_colors["lime8"] = &theme.palette.lime8
        stylesheet.palette_colors["lime9"] = &theme.palette.lime9
        stylesheet.palette_colors["lightGreen0"] = &theme.palette.lightGreen0
        stylesheet.palette_colors["lightGreen1"] = &theme.palette.lightGreen1
        stylesheet.palette_colors["lightGreen2"] = &theme.palette.lightGreen2
        stylesheet.palette_colors["lightGreen3"] = &theme.palette.lightGreen3
        stylesheet.palette_colors["lightGreen4"] = &theme.palette.lightGreen4
        stylesheet.palette_colors["lightGreen5"] = &theme.palette.lightGreen5
        stylesheet.palette_colors["lightGreen6"] = &theme.palette.lightGreen6
        stylesheet.palette_colors["lightGreen7"] = &theme.palette.lightGreen7
        stylesheet.palette_colors["lightGreen8"] = &theme.palette.lightGreen8
        stylesheet.palette_colors["lightGreen9"] = &theme.palette.lightGreen9
        stylesheet.palette_colors["green0"] = &theme.palette.green0
        stylesheet.palette_colors["green1"] = &theme.palette.green1
        stylesheet.palette_colors["green2"] = &theme.palette.green2
        stylesheet.palette_colors["green3"] = &theme.palette.green3
        stylesheet.palette_colors["green4"] = &theme.palette.green4
        stylesheet.palette_colors["green5"] = &theme.palette.green5
        stylesheet.palette_colors["green6"] = &theme.palette.green6
        stylesheet.palette_colors["green7"] = &theme.palette.green7
        stylesheet.palette_colors["green8"] = &theme.palette.green8
        stylesheet.palette_colors["green9"] = &theme.palette.green9
        stylesheet.palette_colors["teal0"] = &theme.palette.teal0
        stylesheet.palette_colors["teal1"] = &theme.palette.teal1
        stylesheet.palette_colors["teal2"] = &theme.palette.teal2
        stylesheet.palette_colors["teal3"] = &theme.palette.teal3
        stylesheet.palette_colors["teal4"] = &theme.palette.teal4
        stylesheet.palette_colors["teal5"] = &theme.palette.teal5
        stylesheet.palette_colors["teal6"] = &theme.palette.teal6
        stylesheet.palette_colors["teal7"] = &theme.palette.teal7
        stylesheet.palette_colors["teal8"] = &theme.palette.teal8
        stylesheet.palette_colors["teal9"] = &theme.palette.teal9
        stylesheet.palette_colors["cyan0"] = &theme.palette.cyan0
        stylesheet.palette_colors["cyan1"] = &theme.palette.cyan1
        stylesheet.palette_colors["cyan2"] = &theme.palette.cyan2
        stylesheet.palette_colors["cyan3"] = &theme.palette.cyan3
        stylesheet.palette_colors["cyan4"] = &theme.palette.cyan4
        stylesheet.palette_colors["cyan5"] = &theme.palette.cyan5
        stylesheet.palette_colors["cyan6"] = &theme.palette.cyan6
        stylesheet.palette_colors["cyan7"] = &theme.palette.cyan7
        stylesheet.palette_colors["cyan8"] = &theme.palette.cyan8
        stylesheet.palette_colors["cyan9"] = &theme.palette.cyan9
        stylesheet.palette_colors["lightBlue0"] = &theme.palette.lightBlue0
        stylesheet.palette_colors["lightBlue1"] = &theme.palette.lightBlue1
        stylesheet.palette_colors["lightBlue2"] = &theme.palette.lightBlue2
        stylesheet.palette_colors["lightBlue3"] = &theme.palette.lightBlue3
        stylesheet.palette_colors["lightBlue4"] = &theme.palette.lightBlue4
        stylesheet.palette_colors["lightBlue5"] = &theme.palette.lightBlue5
        stylesheet.palette_colors["lightBlue6"] = &theme.palette.lightBlue6
        stylesheet.palette_colors["lightBlue7"] = &theme.palette.lightBlue7
        stylesheet.palette_colors["lightBlue8"] = &theme.palette.lightBlue8
        stylesheet.palette_colors["lightBlue9"] = &theme.palette.lightBlue9
        stylesheet.palette_colors["blue0"] = &theme.palette.blue0
        stylesheet.palette_colors["blue1"] = &theme.palette.blue1
        stylesheet.palette_colors["blue2"] = &theme.palette.blue2
        stylesheet.palette_colors["blue3"] = &theme.palette.blue3
        stylesheet.palette_colors["blue4"] = &theme.palette.blue4
        stylesheet.palette_colors["blue5"] = &theme.palette.blue5
        stylesheet.palette_colors["blue6"] = &theme.palette.blue6
        stylesheet.palette_colors["blue7"] = &theme.palette.blue7
        stylesheet.palette_colors["blue8"] = &theme.palette.blue8
        stylesheet.palette_colors["blue9"] = &theme.palette.blue9
        stylesheet.palette_colors["indigo0"] = &theme.palette.indigo0
        stylesheet.palette_colors["indigo1"] = &theme.palette.indigo1
        stylesheet.palette_colors["indigo2"] = &theme.palette.indigo2
        stylesheet.palette_colors["indigo3"] = &theme.palette.indigo3
        stylesheet.palette_colors["indigo4"] = &theme.palette.indigo4
        stylesheet.palette_colors["indigo5"] = &theme.palette.indigo5
        stylesheet.palette_colors["indigo6"] = &theme.palette.indigo6
        stylesheet.palette_colors["indigo7"] = &theme.palette.indigo7
        stylesheet.palette_colors["indigo8"] = &theme.palette.indigo8
        stylesheet.palette_colors["indigo9"] = &theme.palette.indigo9
        stylesheet.palette_colors["violet0"] = &theme.palette.violet0
        stylesheet.palette_colors["violet1"] = &theme.palette.violet1
        stylesheet.palette_colors["violet2"] = &theme.palette.violet2
        stylesheet.palette_colors["violet3"] = &theme.palette.violet3
        stylesheet.palette_colors["violet4"] = &theme.palette.violet4
        stylesheet.palette_colors["violet5"] = &theme.palette.violet5
        stylesheet.palette_colors["violet6"] = &theme.palette.violet6
        stylesheet.palette_colors["violet7"] = &theme.palette.violet7
        stylesheet.palette_colors["violet8"] = &theme.palette.violet8
        stylesheet.palette_colors["violet9"] = &theme.palette.violet9
        stylesheet.palette_colors["purple0"] = &theme.palette.purple0
        stylesheet.palette_colors["purple1"] = &theme.palette.purple1
        stylesheet.palette_colors["purple2"] = &theme.palette.purple2
        stylesheet.palette_colors["purple3"] = &theme.palette.purple3
        stylesheet.palette_colors["purple4"] = &theme.palette.purple4
        stylesheet.palette_colors["purple5"] = &theme.palette.purple5
        stylesheet.palette_colors["purple6"] = &theme.palette.purple6
        stylesheet.palette_colors["purple7"] = &theme.palette.purple7
        stylesheet.palette_colors["purple8"] = &theme.palette.purple8
        stylesheet.palette_colors["purple9"] = &theme.palette.purple9
        stylesheet.palette_colors["pink0"] = &theme.palette.pink0
        stylesheet.palette_colors["pink1"] = &theme.palette.pink1
        stylesheet.palette_colors["pink2"] = &theme.palette.pink2
        stylesheet.palette_colors["pink3"] = &theme.palette.pink3
        stylesheet.palette_colors["pink4"] = &theme.palette.pink4
        stylesheet.palette_colors["pink5"] = &theme.palette.pink5
        stylesheet.palette_colors["pink6"] = &theme.palette.pink6
        stylesheet.palette_colors["pink7"] = &theme.palette.pink7
        stylesheet.palette_colors["pink8"] = &theme.palette.pink8
        stylesheet.palette_colors["pink9"] = &theme.palette.pink9
        stylesheet.palette_colors["grey0"] = &theme.palette.grey0
        stylesheet.palette_colors["grey1"] = &theme.palette.grey1
        stylesheet.palette_colors["grey2"] = &theme.palette.grey2
        stylesheet.palette_colors["grey3"] = &theme.palette.grey3
        stylesheet.palette_colors["grey4"] = &theme.palette.grey4
        stylesheet.palette_colors["grey5"] = &theme.palette.grey5
        stylesheet.palette_colors["grey6"] = &theme.palette.grey6
        stylesheet.palette_colors["grey7"] = &theme.palette.grey7
        stylesheet.palette_colors["grey8"] = &theme.palette.grey8
        stylesheet.palette_colors["grey9"] = &theme.palette.grey9
        stylesheet.palette_colors["black"] = &theme.palette.black
        stylesheet.palette_colors["white"] = &theme.palette.white
}