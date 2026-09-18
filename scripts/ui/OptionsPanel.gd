class_name OptionsPanel
extends Control
## The single options screen, shared by the main menu and the pause menu.
##
## Tabs mirror the layout of a console settings screen: Graphics, Audio,
## Display, Controls.  Every control writes straight through to Settings and
## the change is applied live so the player can see what they are choosing.

signal closed

const TABS := ["GRAPHICS", "AUDIO", "DISPLAY", "CONTROLS"]
const FPS_CHOICES := ["UNLIMITED", "30", "60", "90", "120", "144"]
const FPS_VALUES := [0, 30, 60, 90, 120, 144]

var _tab_bar: HBoxContainer
var _content: VBoxContainer
var _tab := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = Color(0.018, 0.022, 0.028, 0.95)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 120)
	margin.add_theme_constant_override("margin_right", 120)
	margin.add_theme_constant_override("margin_top", 70)
	margin.add_theme_constant_override("margin_bottom", 60)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 22)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 26)
	header.add_child(UI.title("OPTIONS", 40))
	root.add_child(header)
	root.add_child(UI.hrule(1200, Color(1, 1, 1, 0.12)))

	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", 4)
	root.add_child(_tab_bar)
	for i in TABS.size():
		var b := UI.button(TABS[i], 18, UI.COLD)
		b.pressed.connect(_select_tab.bind(i))
		_tab_bar.add_child(b)

	root.add_child(UI.hsep(6))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)
	scroll.add_child(_content)

	root.add_child(UI.hrule(1200, Color(1, 1, 1, 0.12)))
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 24)
	var back := UI.button("BACK", 18)
	back.pressed.connect(close)
	footer.add_child(back)
	var reset := UI.button("RESET TO DEFAULTS", 18, UI.BLOOD)
	reset.pressed.connect(_on_reset)
	footer.add_child(reset)
	footer.add_child(UI.label("changes apply immediately", UI.SIZE_SMALL, UI.FAINT))
	root.add_child(footer)

	visible = false


func open() -> void:
	visible = true
	AudioDirector.play("ui_tab", -8.0, 1.0, 0.0, "UI")
	_build(_tab)


func close() -> void:
	AudioDirector.play("ui_back", -8.0, 1.0, 0.0, "UI")
	visible = false
	Settings.save_settings()
	closed.emit()


func _select_tab(index: int) -> void:
	if index == _tab and _content.get_child_count() > 0:
		return
	_tab = index
	AudioDirector.play("ui_tab", -8.0, 1.0, 0.0, "UI")
	_build(_tab)


func _clear() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()


func _build(index: int) -> void:
	_clear()
	match index:
		0: _build_graphics()
		1: _build_audio()
		2: _build_display()
		3: _build_controls()
	# focus the first interactive control for keyboard navigation
	if _content.get_child_count() > 0:
		var first := _first_focusable(_content)
		if first != null:
			first.call_deferred("grab_focus")


func _first_focusable(n: Node) -> Control:
	for c in n.get_children():
		if c is Control and (c as Control).focus_mode != Control.FOCUS_NONE and (c as Control).visible:
			return c
		var deeper := _first_focusable(c)
		if deeper != null:
			return deeper
	return null


# ----------------------------------------------------------------- graphics

func _build_graphics() -> void:
	var names: Array = Settings.PRESET_NAMES.duplicate()
	var cur := int(Settings.getv("preset"))
	if cur < 0:
		names.append("CUSTOM")
	var preset := UI.option(names, cur if cur >= 0 else names.size() - 1)
	preset.item_selected.connect(func(i):
		if i < Settings.PRESET_NAMES.size():
			Settings.set_preset(i)
		_build(0))
	_content.add_child(UI.row("QUALITY PRESET", preset, "master switch"))

	_content.add_child(UI.hsep(4))
	_content.add_child(UI.section("effects"))
	_check("SHADOWS", "shadows")
	_check("AMBIENT OCCLUSION", "ssao")
	_check("SCREEN-SPACE REFLECTIONS", "ssr")
	_check("LIGHT INDIRECT (SSIL)", "ssil")
	_check("BLOOM", "glow")
	_check("VOLUMETRIC FOG", "volumetric_fog")
	_check("FILM GRAIN", "film_grain")

	_content.add_child(UI.hsep(4))
	_content.add_child(UI.section("resolution"))
	var scale_slider := UI.slider(0.5, 1.0, 0.05, float(Settings.getv("render_scale")))
	var scale_val := UI.label("", UI.SIZE_BODY, UI.TEXT)
	scale_val.custom_minimum_size = Vector2(60, 0)
	scale_val.text = "%d%%" % roundi(float(Settings.getv("render_scale")) * 100.0)
	scale_slider.value_changed.connect(func(v):
		scale_val.text = "%d%%" % roundi(v * 100.0)
		Settings.setv("render_scale", v)
		Settings.apply_viewport())
	var scale_row := UI.row("RENDER SCALE", scale_slider, "3D resolution multiplier")
	scale_row.add_child(scale_val)
	_content.add_child(scale_row)

	var msaa := UI.option(["OFF", "2x", "4x", "8x"], int(Settings.getv("msaa")))
	msaa.item_selected.connect(func(i):
		Settings.setv("msaa", i)
		Settings.apply_viewport())
	_content.add_child(UI.row("ANTI-ALIASING", msaa, "MSAA samples"))


func _check(text: String, key: String) -> void:
	var c := UI.check(text, bool(Settings.getv(key)))
	c.toggled.connect(func(on):
		Settings.setv(key, on)
		Settings.data["preset"] = -1)
	_content.add_child(c)


# -------------------------------------------------------------------- audio

func _build_audio() -> void:
	_content.add_child(UI.section("levels"))
	_volume("MASTER", "master_volume")
	_volume("MUSIC", "music_volume")
	_volume("EFFECTS", "sfx_volume")
	_volume("AMBIENCE", "ambience_volume")
	_volume("VOICE", "voice_volume")
	_content.add_child(UI.hsep(6))
	# Deliberately not via _check(): that marks the *graphics* preset as custom,
	# which a mute toggle has no business doing.
	var m := UI.check("MUTE ALL AUDIO  [M]", bool(Settings.getv("muted")))
	m.toggled.connect(func(on): Settings.setv("muted", on))
	_content.add_child(m)
	_content.add_child(UI.hsep(6))
	var t := UI.button("TEST TONE", 16, UI.COLD)
	t.pressed.connect(func(): AudioDirector.play("rifle_fire_1", -6.0, 1.0, 0.0))
	_content.add_child(t)


func _volume(text: String, key: String) -> void:
	var s := UI.slider(0.0, 1.0, 0.01, float(Settings.getv(key)))
	var v := UI.label("%d%%" % roundi(float(Settings.getv(key)) * 100.0), UI.SIZE_BODY, UI.TEXT)
	v.custom_minimum_size = Vector2(60, 0)
	s.custom_minimum_size = Vector2(160, 22)
	s.value_changed.connect(func(x):
		v.text = "%d%%" % roundi(x * 100.0)
		Settings.setv(key, x)
		Settings.apply_audio())
	var row := UI.row(text, s, "")
	row.add_child(v)
	_content.add_child(row)


# ------------------------------------------------------------------ display

func _build_display() -> void:
	_content.add_child(UI.section("window"))
	var fs := UI.check("FULLSCREEN", bool(Settings.getv("fullscreen")))
	fs.toggled.connect(func(on):
		Settings.setv("fullscreen", on)
		Settings.apply_display())
	_content.add_child(fs)

	var vs := UI.check("V-SYNC", bool(Settings.getv("vsync")))
	vs.toggled.connect(func(on):
		Settings.setv("vsync", on)
		Settings.apply_display())
	_content.add_child(vs)

	var fps_idx := 0
	for i in FPS_VALUES.size():
		if FPS_VALUES[i] == int(Settings.getv("max_fps")):
			fps_idx = i
	var fps := UI.option(FPS_CHOICES, fps_idx)
	fps.item_selected.connect(func(i):
		Settings.setv("max_fps", FPS_VALUES[i])
		Settings.apply_display())
	_content.add_child(UI.row("FRAME RATE CAP", fps, ""))

	_content.add_child(UI.hsep(6))
	_content.add_child(UI.section("interface"))
	var sub := UI.check("SUBTITLES", bool(Settings.getv("subtitles")))
	sub.toggled.connect(func(on): Settings.setv("subtitles", on))
	_content.add_child(sub)
	var fps_lbl := UI.check("SHOW FRAME RATE", bool(Settings.getv("show_fps")))
	fps_lbl.toggled.connect(func(on): Settings.setv("show_fps", on))
	_content.add_child(fps_lbl)

	var res := UI.label("%d x %d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
			UI.SIZE_BODY, UI.FAINT)
	_content.add_child(UI.row("RENDER RESOLUTION", res, "from the window"))


# ----------------------------------------------------------------- controls

func _build_controls() -> void:
	_content.add_child(UI.section("camera"))
	var sens := UI.slider(0.0004, 0.006, 0.0001, float(Settings.getv("mouse_sensitivity")))
	var sens_val := UI.label("%.2f" % (float(Settings.getv("mouse_sensitivity")) * 1000.0), UI.SIZE_BODY, UI.TEXT)
	sens_val.custom_minimum_size = Vector2(60, 0)
	sens.custom_minimum_size = Vector2(160, 22)
	sens.value_changed.connect(func(v):
		sens_val.text = "%.2f" % (v * 1000.0)
		Settings.setv("mouse_sensitivity", v))
	var r1 := UI.row("MOUSE SENSITIVITY", sens, "")
	r1.add_child(sens_val)
	_content.add_child(r1)

	var fov := UI.slider(60.0, 110.0, 1.0, float(Settings.getv("fov")))
	var fov_val := UI.label("%d" % roundi(float(Settings.getv("fov"))), UI.SIZE_BODY, UI.TEXT)
	fov_val.custom_minimum_size = Vector2(60, 0)
	fov.custom_minimum_size = Vector2(160, 22)
	fov.value_changed.connect(func(v):
		fov_val.text = "%d" % roundi(v)
		Settings.setv("fov", v))
	var r2 := UI.row("FIELD OF VIEW", fov, "")
	r2.add_child(fov_val)
	_content.add_child(r2)

	var invert := UI.check("INVERT VERTICAL LOOK", bool(Settings.getv("invert_y")))
	invert.toggled.connect(func(on): Settings.setv("invert_y", on))
	_content.add_child(invert)

	var shake := UI.slider(0.0, 2.0, 0.1, float(Settings.getv("camera_shake")))
	var shake_val := UI.label("%d%%" % roundi(float(Settings.getv("camera_shake")) * 100.0), UI.SIZE_BODY, UI.TEXT)
	shake_val.custom_minimum_size = Vector2(60, 0)
	shake.custom_minimum_size = Vector2(160, 22)
	shake.value_changed.connect(func(v):
		shake_val.text = "%d%%" % roundi(v * 100.0)
		Settings.setv("camera_shake", v))
	var r3 := UI.row("CAMERA SHAKE", shake, "")
	r3.add_child(shake_val)
	_content.add_child(r3)

	_content.add_child(UI.hsep(6))
	_content.add_child(UI.section("bindings"))
	var binds := [
		["MOVE", "W A S D  ·  ARROWS"], ["SPRINT", "SHIFT"], ["CROUCH", "CTRL"],
		["JUMP", "SPACE"], ["FIRE", "LEFT MOUSE"], ["AIM", "RIGHT MOUSE"],
		["RELOAD", "R"], ["INTERACT", "E"], ["MELEE", "V"],
		["FLASHLIGHT", "F"], ["RADIAL MENU", "TAB"], ["MUTE", "M"],
		["PAUSE", "ESC"],
	]
	for b in binds:
		_content.add_child(UI.row(String(b[0]), UI.label(String(b[1]), UI.SIZE_BODY, UI.COLD), ""))
	_content.add_child(UI.label("gamepads are supported and rebind automatically",
			UI.SIZE_SMALL, UI.FAINT))


func _on_reset() -> void:
	Settings.reset_to_defaults()
	Settings.save_settings()
	_build(_tab)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
