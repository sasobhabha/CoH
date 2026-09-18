class_name UI
## Shared look-and-feel helpers so every screen is styled identically.
##
## The whole game uses one typographic system: the engine's default sans,
## tracked out with a FontVariation, plus a small palette.  Building the theme
## in code keeps it in one place instead of scattered across .tscn files.

const TEXT := Color("dfe7ee")
const DIM := Color("8d9daa")
const FAINT := Color("58666f")
const AMBER := Color("ffb45a")
const COLD := Color("7fd4ff")
const BLOOD := Color("ff5b4a")
const GREEN := Color("8fd68a")
const INK := Color("0a0d11")

const SIZE_H1 := 64
const SIZE_H2 := 30
const SIZE_BODY := 17
const SIZE_SMALL := 14


static func font(spacing := 0.0, embolden := 0.0) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.spacing_glyph = int(spacing)
	fv.variation_embolden = embolden
	return fv


static func label(text: String, size := SIZE_BODY, color := TEXT, spacing := 0.0,
		embolden := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(spacing, embolden))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6 if size > 24 else 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func panel(bg := Color(0.03, 0.04, 0.05, 0.72), radius := 3, border := 0.0,
		border_color := Color(1, 1, 1, 0.08)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border > 0.0:
		sb.set_border_width_all(int(border))
		sb.border_color = border_color
	sb.set_content_margin_all(12)
	return sb


static func hrule(width := 260, color := Color(1, 1, 1, 0.22)) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(width, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func button(text: String, size := 20, accent := AMBER) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = false
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", font(2.0))
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", DIM)
	b.add_theme_color_override("font_hover_color", accent)
	b.add_theme_color_override("font_focus_color", accent)
	b.add_theme_color_override("font_pressed_color", accent)
	b.add_theme_color_override("font_disabled_color", FAINT)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(accent.r, accent.g, accent.b, 0.10)
	hover.border_color = Color(accent.r, accent.g, accent.b, 0.5)
	hover.set_border_width_all(1)
	hover.border_width_left = 3
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(accent.r, accent.g, accent.b, 0.22)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", normal)
	return b


static func slider(minv: float, maxv: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(260, 22)
	s.focus_mode = Control.FOCUS_ALL
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.10)
	bg.set_corner_radius_all(2)
	var grab := StyleBoxFlat.new()
	grab.bg_color = AMBER
	grab.set_corner_radius_all(1)
	grab.content_margin_top = 4
	grab.content_margin_bottom = 4
	s.add_theme_stylebox_override("slider", bg)
	s.add_theme_stylebox_override("grabber_area", bg)
	s.add_theme_stylebox_override("grabber_area_highlight", bg)
	s.add_theme_stylebox_override("grabber", grab)
	return s


static func check(text: String, pressed: bool) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = pressed
	c.add_theme_font_override("font", font(1.0))
	c.add_theme_font_size_override("font_size", SIZE_BODY)
	c.add_theme_color_override("font_color", DIM)
	c.add_theme_color_override("font_hover_color", TEXT)
	c.add_theme_color_override("font_pressed_color", AMBER)
	return c


static func option(items: Array, selected := 0) -> OptionButton:
	var o := OptionButton.new()
	o.add_theme_font_override("font", font(1.0))
	o.add_theme_font_size_override("font_size", SIZE_BODY)
	o.add_theme_color_override("font_color", TEXT)
	o.add_theme_color_override("font_hover_color", AMBER)
	o.custom_minimum_size = Vector2(190, 30)
	for i in items.size():
		o.add_item(String(items[i]), i)
	o.selected = clampi(selected, 0, maxi(0, items.size() - 1))
	return o


## Label / control pair used by every options list.
static func row(label_text: String, control: Control, hint := "", width := 250.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	var l := label(label_text, SIZE_BODY, DIM, 0.5)
	l.custom_minimum_size = Vector2(width, 26)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	if hint != "":
		var hh := label(hint, SIZE_SMALL, FAINT)
		hh.custom_minimum_size = Vector2(150, 26)
		hh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(hh)
	return h


static func hsep(h := 10) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func title(text: String, size := SIZE_H1, color := TEXT) -> Label:
	return label(text.to_upper(), size, color, size * 0.16, 0.35)


static func section(text: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.add_child(label(text.to_upper(), SIZE_SMALL, AMBER, 3.0, 0.3))
	v.add_child(hrule(200, Color(AMBER.r, AMBER.g, AMBER.b, 0.35)))
	return v


static func format_time(seconds: float) -> String:
	var s := int(maxf(seconds, 0.0))
	return "%02d:%02d" % [s / 60, s % 60]
