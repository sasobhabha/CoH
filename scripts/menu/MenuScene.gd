extends Node3D
## Main menu: a live shot of the monolith under a burning sky, with the menu
## laid over it.  Nothing here is a still image -- the camera orbits, the rain
## falls, and the post grade matches the game itself.

signal start_requested(new_game: bool)
signal quit_requested

const ORBIT_RADIUS := 27.0

var _cam: Camera3D
var _world: Node3D
var _rain: GPUParticles3D
var _t := 0.0
var _mouse := Vector2.ZERO
var _ui: CanvasLayer
var _options: OptionsPanel
var _menu_box: VBoxContainer
var _title_box: VBoxContainer
var _fps_label: Label
var _fps_accum := 0.0
var _fps_frames := 0
var _signs: Array[Label3D] = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_world()
	_build_camera()
	_build_ui()
	AudioDirector.music("mus_menu", 3.0, -3.0)
	AudioDirector.set_ambience(["amb_rain", "amb_wind"], 3.0)
	set_process(true)


# ------------------------------------------------------------------- world

func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "MenuWorld"
	add_child(_world)

	var we := WorldEnvironment.new()
	we.environment = EnvLib.menu_dusk()
	Settings.apply_quality(we.environment)
	_world.add_child(we)

	# low, hot sun behind the ruins
	Build.sun(_world, Vector3(-7, 158, 0), Color("ffab63"), 1.2, 3.5)
	Build.omni(_world, Vector3(0, 4, -2), Color("ffd9a8"), 3.0, 26.0, true, 1.2)

	# flood water
	var water := Build.water(_world, Vector2(420, 420), Vector3.ZERO,
			MatLib.water(MatLib.ripple_texture()))
	if water.material_override is ShaderMaterial:
		var sm := water.material_override as ShaderMaterial
		sm.set_shader_parameter("uv_scale", 22.0)
		sm.set_shader_parameter("horizon_color", Color("6b4a35"))
		sm.set_shader_parameter("deep_color", Color("080f14"))
		sm.set_shader_parameter("shallow_color", Color("131f27"))

	# the monolith
	var slab := MatLib.flat(Color("dfe9f0"), "monolith", 1.0)
	slab.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	slab.emission_enabled = true
	slab.emission = Color("bcd8ea")
	slab.emission_energy_multiplier = 0.28
	slab.roughness = 0.55
	slab.albedo_color = Color("ccd8e0")
	Build.box(_world, Vector3(4.2, 19.0, 3.2), Vector3(0, 9.5, 0), slab, Vector3.ZERO, false)
	Build.box(_world, Vector3(9.0, 1.6, 7.0), Vector3(0, -0.7, 0), MatLib.concrete_dark())

	# a cold rim around the base to make it read against the warm sky
	Build.spot(_world, Vector3(0, 1.2, 5.6), Vector3(0, 180, 0), Color("7fd4ff"), 9.0, 40.0, 42.0,
			true, 4.0)
	Build.spot(_world, Vector3(6.5, 1.2, -5.0), Vector3(0, 52, 0), Color("7fd4ff"), 7.0, 40.0, 46.0,
			true, 4.0)
	Build.omni(_world, Vector3(0, 1.4, 3.4), Color("9fe0ff"), 4.0, 18.0, false, 2.5)

	_skyline()
	_burn_barrels()
	_weather()


func _skyline() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 20260917
	var mats := [MatLib.concrete_dark(), MatLib.plaster(), MatLib.brick(), MatLib.metal_rust()]
	var signs := ["雨", "港", "区", "北", "铁", "光", "九", "海"]
	var sign_colors := [Color("ffb45a"), Color("7fd4ff"), Color("ff5f7a"), Color("8ff0c0")]
	for ring in 5:
		var radius := 34.0 + ring * 17.0
		var count := 26 + ring * 6
		for i in count:
			var a := TAU * float(i) / float(count) + r.randf() * 0.09
			var dist := radius + r.randf_range(-7.0, 7.0)
			var h := r.randf_range(7.0, 30.0) * (0.55 + ring * 0.16)
			var w := r.randf_range(5.0, 13.0)
			var d := r.randf_range(5.0, 13.0)
			var yaw := r.randf_range(-18.0, 18.0)
			var pos := Vector3(cos(a) * dist, h * 0.5 - 1.5, sin(a) * dist)
			var mat: Material = mats[r.randi() % mats.size()]
			if ring < 2:
				mat = MatLib.concrete_dark()
			Build.box(_world, Vector3(w, h, d), pos, mat, Vector3(0, yaw, 0))
			# broken top
			Build.box(_world, Vector3(w * 0.55, r.randf_range(1.5, 5.0), d * 0.6),
					pos + Vector3(r.randf_range(-1.5, 1.5), h * 0.5 + 1.0, r.randf_range(-1.5, 1.5)),
					MatLib.concrete_dark(), Vector3(0, r.randf_range(0, 40), 0))
			# lit windows
			if r.randf() < 0.55 and ring >= 1:
				var rows := int(h / 3.4)
				for row in rows:
					if r.randf() < 0.45:
						continue
					var wy := -h * 0.5 + 1.6 + row * 3.4
					var c: Color = sign_colors[r.randi() % sign_colors.size()]
					var em := MatLib.emissive(c, r.randf_range(0.8, 2.4))
					var face := r.randi() % 4
					var off := Vector3.ZERO
					var size := Vector3(w * 0.62, 0.5, 0.06)
					if face == 0:
						off = Vector3(0, 0, d * 0.5 + 0.05)
					elif face == 1:
						off = Vector3(0, 0, -d * 0.5 - 0.05)
					else:
						off = Vector3(w * 0.5 + 0.05, 0, 0)
						size = Vector3(0.06, 0.5, d * 0.62)
					Build.box(_world, size, pos + off + Vector3(0, wy, 0), em,
							Vector3(0, yaw, 0), false)
			# rooftop sign
			if r.randf() < 0.22:
				var col: Color = sign_colors[r.randi() % sign_colors.size()]
				var l := Build.sign(_world, signs[r.randi() % signs.size()],
						pos + Vector3(0, h * 0.5 + 2.4, 0), Vector3(0, yaw + r.randf_range(-20, 20), 0),
						col, 140)
				l.outline_size = 12
				l.outline_modulate = Color(col.r * 0.4, col.g * 0.4, col.b * 0.4, 1.0)
				_signs.append(l)


func _burn_barrels() -> void:
	## A few fires in the near water, for scale and warmth.
	for spec in [Vector3(-9.0, 0.0, 12.0), Vector3(13.0, 0.0, -7.0), Vector3(-16.5, 0.0, -9.0)]:
		var holder := Node3D.new()
		holder.position = spec
		_world.add_child(holder)
		Build.cylinder(holder, 0.42, 1.0, Vector3(0, 0.5, 0), MatLib.metal_rust())
		Build.omni(holder, Vector3(0, 1.2, 0), Color("ff9a3c"), 7.0, 22.0, false, 3.0)
		FX.fire_glow(holder, 28)
		FX.smoke_plume(holder, 18, 3.2)


func _weather() -> void:
	_rain = FX.rain(_world, 3200, Vector2(0.011, 0.62), Color(0.74, 0.82, 0.9, 0.26))
	FX.embers(_world, 90, Color(1.0, 0.58, 0.22, 0.5), Vector3(30, 8, 30), 0.06)


func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.fov = float(Settings.getv("fov"))
	_cam.far = 400.0
	_cam.near = 0.1
	add_child(_cam)
	_cam.global_position = Vector3(0, 6.5, ORBIT_RADIUS)


# ---------------------------------------------------------------------- ui

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)

	var post := PostFX.new()
	post.vignette = 0.72
	post.contrast = 1.04
	post.desaturate = 0.12
	_ui.add_child(post)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 96)
	margin.add_theme_constant_override("margin_right", 96)
	margin.add_theme_constant_override("margin_top", 72)
	margin.add_theme_constant_override("margin_bottom", 56)
	_ui.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	margin.add_child(root)

	_title_box = VBoxContainer.new()
	_title_box.add_theme_constant_override("separation", 2)
	root.add_child(_title_box)

	var eyebrow := UI.label("AMERICA, 2050", UI.SIZE_SMALL, UI.FAINT, 6.0, 0.3)
	_title_box.add_child(eyebrow)
	# Sized down from 104: the old title was eight letters, this one is
	# twenty-three, and a title that overflows its own rule looks like a bug.
	var title := UI.title("CENTURY OF HUMILIATION", 62)
	_title_box.add_child(title)
	var sub := UI.label("A CENTURY OF ASH", 26, UI.AMBER, 15.0, 0.35)
	_title_box.add_child(sub)
	_title_box.add_child(UI.hsep(10))
	var rule := UI.hrule(560, Color(UI.AMBER.r, UI.AMBER.g, UI.AMBER.b, 0.55))
	_title_box.add_child(rule)
	_title_box.add_child(UI.label("They took the square and hung their face over it.",
			UI.SIZE_BODY, UI.DIM, 0.6))

	root.add_child(UI.hsep(38))

	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 2)
	root.add_child(_menu_box)

	var has_save := GameManager.has_save()
	_add_button("CONTINUE", func(): _start(false), not has_save)
	_add_button("NEW GAME", func(): _start(true), false)
	_add_button("OPTIONS", func(): _options.open(), false)
	_add_button("QUIT TO DESKTOP", func(): quit_requested.emit(), false)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 40)
	root.add_child(footer)
	footer.add_child(UI.label("v1.0.0", UI.SIZE_SMALL, UI.FAINT))
	if not has_save:
		footer.add_child(UI.label("no save data found", UI.SIZE_SMALL, UI.FAINT))
	_fps_label = UI.label("", UI.SIZE_SMALL, UI.FAINT)
	_fps_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(_fps_label)

	_options = OptionsPanel.new()
	_options.closed.connect(func(): _options_closed())
	_ui.add_child(_options)


func _add_button(text: String, action: Callable, disabled: bool) -> Button:
	var b := UI.button(text, 26)
	b.custom_minimum_size = Vector2(340, 0)
	b.disabled = disabled
	b.pressed.connect(func():
		AudioDirector.play("ui_confirm", -5.0, 1.0, 0.0, "UI")
		action.call())
	b.mouse_entered.connect(func():
		if not b.disabled:
			AudioDirector.play("ui_hover", -14.0, 1.0, 0.05, "UI"))
	_menu_box.add_child(b)
	return b


func _options_closed() -> void:
	var first := _menu_box.get_child(0)
	if first is Control:
		(first as Control).call_deferred("grab_focus")


func _start(new_game: bool) -> void:
	start_requested.emit(new_game)


# ----------------------------------------------------------------- process

func _process(delta: float) -> void:
	_t += delta
	var a := _t * 0.048
	var radius := ORBIT_RADIUS + sin(_t * 0.11) * 3.0
	var pos := Vector3(sin(a) * radius, 6.2 + sin(_t * 0.31) * 0.9, cos(a) * radius)
	if _cam != null:
		_cam.global_position = pos
		_cam.look_at(Vector3(0, 9.0, 0) + Vector3(_mouse.x * 3.0, _mouse.y * 1.4, 0), Vector3.UP)
	if _rain != null and _cam != null:
		_rain.global_position = _cam.global_position + Vector3(0, 14, 0)

	for l in _signs:
		var flicker := 0.75 + 0.25 * sin(_t * 7.0 + l.position.x * 0.7)
		l.modulate.a = clampf(flicker, 0.0, 1.0)

	_update_fps(delta)


func _update_fps(delta: float) -> void:
	if _fps_label == null:
		return
	if not bool(Settings.getv("show_fps")):
		_fps_label.text = ""
		return
	_fps_accum += delta
	_fps_frames += 1
	if _fps_accum >= 0.5:
		_fps_label.text = "%d FPS  |  %s" % [roundi(_fps_frames / _fps_accum),
				Settings.preset_name()]
		_fps_accum = 0.0
		_fps_frames = 0


func _unhandled_input(event: InputEvent) -> void:
	# handled before the early-outs so the mute key works with options open too
	if event.is_action_pressed("mute_toggle"):
		Settings.toggle_mute()
		return
	if _options != null and _options.visible:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		_mouse = Vector2(
				clampf(event.position.x / maxf(get_viewport().get_visible_rect().size.x, 1.0) * 2.0 - 1.0, -1.0, 1.0),
				clampf(event.position.y / maxf(get_viewport().get_visible_rect().size.y, 1.0) * 2.0 - 1.0, -1.0, 1.0))
	elif event.is_action_pressed("fps_toggle"):
		Settings.setv("show_fps", not bool(Settings.getv("show_fps")))
