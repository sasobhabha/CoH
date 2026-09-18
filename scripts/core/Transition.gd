extends CanvasLayer
## Global screen furniture: fades, letterboxing and chapter title cards.
##
## Every method that animates is awaitable, so scenes read like a screenplay:
##     await Transition.fade_out(0.8)
##     Transition.show_title("CHAPTER II", "THE TAVERN AT KILOMETER NINE")
##     await Transition.fade_in(1.4)

const BAR := 0.11  # letterbox height as a fraction of the screen

var _fade: ColorRect
var _flash: ColorRect
var _bar_top: ColorRect
var _bar_bottom: ColorRect
var _title_box: VBoxContainer
var _title_header: Label
var _title_rule: ColorRect
var _title_sub: Label

var _bars_on := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

	_flash = ColorRect.new()
	_flash.color = Color(0, 0, 0, 0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	_bar_top = _make_bar(true)
	_bar_bottom = _make_bar(false)

	_title_box = VBoxContainer.new()
	_title_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_box.add_theme_constant_override("separation", 6)
	_title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_box.modulate = Color(1, 1, 1, 0)
	add_child(_title_box)

	_title_header = UI.title("", 30, UI.DIM)
	_title_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_rule = UI.hrule(180, Color(UI.AMBER.r, UI.AMBER.g, UI.AMBER.b, 0.7))
	_title_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_title_sub = UI.title("", 54)
	_title_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_box.add_child(_title_header)
	_title_box.add_child(_title_rule)
	_title_box.add_child(_title_sub)


func _make_bar(top: bool) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0, 0, 0, 1)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.anchor_left = 0.0
	c.anchor_right = 1.0
	if top:
		c.anchor_top = 0.0
		c.anchor_bottom = 0.0
		c.offset_bottom = 0.0
	else:
		c.anchor_top = 1.0
		c.anchor_bottom = 1.0
		c.offset_top = 0.0
	add_child(c)
	return c


# ------------------------------------------------------------------ fades

func to_black(duration := 0.8) -> void:
	var t := create_tween()
	t.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_property(_fade, "color:a", 1.0, duration)
	await t.finished


func from_black(duration := 0.8) -> void:
	var t := create_tween()
	t.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_property(_fade, "color:a", 0.0, duration)
	await t.finished


func set_black(on: bool) -> void:
	_fade.color.a = 1.0 if on else 0.0


func flash(color := Color(1, 0.4, 0.3), strength := 0.5, duration := 0.45) -> void:
	_flash.color = Color(color.r, color.g, color.b, strength)
	var t := create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	t.tween_property(_flash, "color:a", 0.0, duration)
	await t.finished


# ------------------------------------------------------------- letterbox

func letterbox(on: bool, duration := 0.9) -> void:
	if on == _bars_on:
		return
	_bars_on = on
	var vp := get_viewport().get_visible_rect().size
	var target := vp.y * BAR if on else 0.0
	var t := create_tween().set_parallel(true)
	t.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(_bar_top, "offset_bottom", target, duration)
	t.tween_property(_bar_bottom, "offset_top", -target, duration)
	await t.finished


# ------------------------------------------------------------ title cards

func show_title(header: String, subtitle: String, hold := 2.8, appear := 1.4) -> void:
	_title_header.text = header.to_upper()
	_title_sub.text = subtitle.to_upper()
	var t_in := create_tween()
	t_in.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	t_in.tween_property(_title_box, "modulate:a", 1.0, appear)
	await t_in.finished
	await get_tree().create_timer(hold).timeout
	var t_out := create_tween()
	t_out.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	t_out.tween_property(_title_box, "modulate:a", 0.0, appear * 0.8)
	await t_out.finished


## Non-blocking corner caption used for location callouts.
func caption(text: String, hold := 3.0) -> void:
	_title_header.text = ""
	_title_rule.modulate.a = 0.0
	_title_sub.text = text.to_upper()
	_title_sub.add_theme_font_size_override("font_size", 26)
	var t_in := create_tween()
	t_in.tween_property(_title_box, "modulate:a", 1.0, 0.5)
	await t_in.finished
	await get_tree().create_timer(hold).timeout
	var t_out := create_tween()
	t_out.tween_property(_title_box, "modulate:a", 0.0, 0.7)
	await t_out.finished
	_title_rule.modulate.a = 1.0
	_title_sub.add_theme_font_size_override("font_size", 54)
