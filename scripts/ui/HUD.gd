class_name HUD
extends Control
## Diegetic-but-clean combat interface.
##
## Split in two halves: node-based furniture (bars, labels, prompts) that is
## easy to lay out, and a single `_draw()` pass for the crosshair, hit markers
## and damage direction arcs, which need per-frame geometry.

var player: Player

var _health_fill: ColorRect
var _health_glow: ColorRect
var _health_label: Label
var _stamina_fill: ColorRect
var _ammo_label: Label
var _reserve_label: Label
var _weapon_label: Label
var _objective_box: VBoxContainer
var _objective_title: Label
var _objective_body: Label
var _prompt_root: HBoxContainer
var _prompt_key: Label
var _prompt_text: Label
var _subtitle_root: VBoxContainer
var _subtitle_speaker: Label
var _subtitle_text: Label
var _toast_box: VBoxContainer
var _alert_label: Label
var _status_label: Label
var _fps_label: Label

var _spread := 0.6
var _hit_t := 0.0
var _hit_head := false
var _damage_arcs: Array = []          # [{dir: float, t: float, amount: float}]
var _alert := 0.0
var _hidden := false
var _low_health := 0.0
var _fps_accum := 0.0
var _fps_frames := 0
var _toasts: Array = []

const HUD_FONT_COLOR := Color("dfe7ee")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	GameManager.objectives_changed.connect(refresh_objectives)
	GameManager.objective_completed.connect(_on_objective_completed)
	GameManager.toast.connect(toast)
	set_process(true)


func _build() -> void:
	# ---------------------------------------------------------- health block
	var left := VBoxContainer.new()
	left.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	left.position = Vector2(56, -108)
	left.add_theme_constant_override("separation", 5)
	add_child(left)

	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 12)
	left.add_child(hp_row)
	var hp_tag := UI.label("VITALS", UI.SIZE_SMALL, UI.FAINT, 4.0, 0.3)
	hp_tag.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hp_row.add_child(hp_tag)
	_health_label = UI.label("100", 30, HUD_FONT_COLOR, 1.0, 0.35)
	hp_row.add_child(_health_label)

	var hp_bar := Control.new()
	hp_bar.custom_minimum_size = Vector2(330, 10)
	left.add_child(hp_bar)
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0.05, 0.06, 0.07, 0.75)
	hp_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp_bar.add_child(hp_bg)
	_health_fill = ColorRect.new()
	_health_fill.color = Color("cfe4ef")
	_health_fill.position = Vector2(1, 1)
	_health_fill.size = Vector2(328, 8)
	hp_bar.add_child(_health_fill)
	_health_glow = ColorRect.new()
	_health_glow.color = Color("7fd4ff")
	_health_glow.position = Vector2(1, 1)
	_health_glow.size = Vector2(328, 3)
	hp_bar.add_child(_health_glow)

	var st_bar := Control.new()
	st_bar.custom_minimum_size = Vector2(200, 4)
	left.add_child(st_bar)
	var st_bg := ColorRect.new()
	st_bg.color = Color(0.05, 0.06, 0.07, 0.7)
	st_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	st_bar.add_child(st_bg)
	_stamina_fill = ColorRect.new()
	_stamina_fill.color = Color("ffb45a")
	_stamina_fill.size = Vector2(200, 4)
	st_bar.add_child(_stamina_fill)

	_status_label = UI.label("", UI.SIZE_SMALL, UI.AMBER, 4.0, 0.3)
	left.add_child(_status_label)

	# ------------------------------------------------------------ ammo block
	var right := VBoxContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	right.position = Vector2(-304, -112)
	right.add_theme_constant_override("separation", 0)
	right.alignment = BoxContainer.ALIGNMENT_END
	add_child(right)

	_weapon_label = UI.label("MK-IV SCOUT RIFLE", UI.SIZE_SMALL, UI.FAINT, 4.0, 0.3)
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_weapon_label)

	var ammo_row := HBoxContainer.new()
	ammo_row.alignment = BoxContainer.ALIGNMENT_END
	ammo_row.add_theme_constant_override("separation", 8)
	right.add_child(ammo_row)
	_ammo_label = UI.label("30", 44, HUD_FONT_COLOR, 1.0, 0.4)
	ammo_row.add_child(_ammo_label)
	_reserve_label = UI.label("/ 180", 20, UI.FAINT)
	_reserve_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	ammo_row.add_child(_reserve_label)

	var ammo_rule := UI.hrule(240, Color(1, 1, 1, 0.18))
	ammo_rule.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.add_child(ammo_rule)

	# ------------------------------------------------------- objective block
	_objective_box = VBoxContainer.new()
	_objective_box.position = Vector2(56, 48)
	_objective_box.add_theme_constant_override("separation", 3)
	add_child(_objective_box)
	_objective_title = UI.label("", UI.SIZE_SMALL, UI.AMBER, 4.0, 0.3)
	_objective_box.add_child(_objective_title)
	var orule := UI.hrule(200, Color(UI.AMBER.r, UI.AMBER.g, UI.AMBER.b, 0.4))
	_objective_box.add_child(orule)
	_objective_body = UI.label("", 18, HUD_FONT_COLOR, 0.6)
	_objective_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_body.custom_minimum_size = Vector2(330, 0)
	_objective_box.add_child(_objective_body)

	# --------------------------------------------------------------- prompts
	_prompt_root = HBoxContainer.new()
	_prompt_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_root.position = Vector2(-100, -220)
	_prompt_root.add_theme_constant_override("separation", 10)
	_prompt_root.visible = false
	add_child(_prompt_root)
	_prompt_key = UI.label("[E]", 20, UI.AMBER, 1.0, 0.4)
	_prompt_root.add_child(_prompt_key)
	_prompt_text = UI.label("", 20, HUD_FONT_COLOR, 1.5)
	_prompt_root.add_child(_prompt_text)

	# ------------------------------------------------------------- subtitles
	_subtitle_root = VBoxContainer.new()
	_subtitle_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_subtitle_root.position = Vector2(-380, -150)
	_subtitle_root.custom_minimum_size = Vector2(760, 0)
	_subtitle_root.alignment = BoxContainer.ALIGNMENT_CENTER
	_subtitle_root.visible = false
	add_child(_subtitle_root)
	_subtitle_speaker = UI.label("", UI.SIZE_SMALL, UI.AMBER, 4.0, 0.3)
	_subtitle_speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_root.add_child(_subtitle_speaker)
	_subtitle_text = UI.label("", 20, HUD_FONT_COLOR, 0.4)
	_subtitle_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_text.custom_minimum_size = Vector2(760, 0)
	_subtitle_root.add_child(_subtitle_text)

	# ---------------------------------------------------------------- toasts
	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast_box.position = Vector2(-250, 96)
	_toast_box.custom_minimum_size = Vector2(500, 0)
	_toast_box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_toast_box)

	# ----------------------------------------------------------------- alert
	_alert_label = UI.label("", UI.SIZE_SMALL, UI.BLOOD, 5.0, 0.35)
	_alert_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_alert_label.position = Vector2(-100, 58)
	_alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alert_label.custom_minimum_size = Vector2(200, 0)
	add_child(_alert_label)

	_fps_label = UI.label("", UI.SIZE_SMALL, UI.FAINT)
	_fps_label.position = Vector2(0, 0)
	_fps_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.position = Vector2(-190, 40)
	_fps_label.custom_minimum_size = Vector2(170, 0)
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_fps_label)


# ------------------------------------------------------------------- binding

func bind_player(p: Player) -> void:
	player = p
	p.health_changed.connect(_on_health)
	p.ammo_changed.connect(_on_ammo)
	p.stamina_changed.connect(_on_stamina)
	p.focus_changed.connect(_on_focus)
	p.damaged.connect(_on_damaged)
	p.hidden_changed.connect(_on_hidden)
	p.died.connect(_on_died)
	_on_health(p.health, Player.MAX_HEALTH)
	_on_ammo(p.mag, p.reserve)
	refresh_objectives()


func refresh_objectives() -> void:
	var info := GameManager.chapter_info(GameManager.chapter)
	_objective_title.text = String(info.get("title", "")) + "  //  " + String(info.get("name", ""))
	var active := GameManager.active_objective()
	if active.is_empty():
		var prog := GameManager.objective_progress()
		_objective_body.text = "— all objectives complete —" if prog.y > 0 else ""
	else:
		_objective_body.text = "▸ " + active


func _on_objective_completed(_id: String) -> void:
	_hit_flash_objective()
	refresh_objectives()


func _hit_flash_objective() -> void:
	if _objective_body == null:
		return
	var t := create_tween()
	_objective_body.modulate = UI.GREEN
	t.tween_property(_objective_body, "modulate", Color(1, 1, 1), 1.0)


# -------------------------------------------------------------------- events

func _on_health(health: float, max_health: float) -> void:
	var ratio := clampf(health / max_health, 0.0, 1.0)
	_health_fill.size.x = 328.0 * ratio
	_health_glow.size.x = 328.0 * ratio
	var col := Color("cfe4ef")
	if ratio < 0.35:
		col = UI.BLOOD
	elif ratio < 0.65:
		col = UI.AMBER
	_health_fill.color = col
	_health_glow.color = Color(col.r, col.g, col.b, 0.55)
	_health_label.text = "%d" % roundi(health)
	_health_label.add_theme_color_override("font_color", col)
	_low_health = 0.0 if ratio > 0.35 else (0.35 - ratio) / 0.35
	if player != null and player.game != null and player.game.post != null:
		player.game.post.low_health = _low_health


func _on_ammo(mag: int, reserve: int) -> void:
	_ammo_label.text = "%d" % mag
	if player != null and player._reloading:
		_ammo_label.text = "--"
	# An unlimited reserve is drawn as unlimited, not as a number that never
	# moves, which just reads as a broken counter.  The fallback font really does
	# carry the glyph: tools/check_glyph.gd checks rather than assumes.
	_reserve_label.text = ("/ ∞" if Player.UNLIMITED_AMMO else "/ %d" % reserve)
	var low := mag <= 5
	_ammo_label.add_theme_color_override("font_color", UI.AMBER if low else HUD_FONT_COLOR)


func _on_stamina(value: float) -> void:
	_stamina_fill.size.x = 200.0 * clampf(value, 0.0, 1.0)
	_stamina_fill.color = UI.AMBER if value > 0.25 else UI.BLOOD


func _on_focus(target: Node, label: String) -> void:
	var showing := target != null
	_prompt_root.visible = showing
	if showing:
		_prompt_text.text = label.to_upper()
		_prompt_root.position.x = -110.0 - float(_prompt_text.text.length()) * 4.0


func _on_damaged(from_direction: Vector3, amount: float) -> void:
	if player == null or player.cam_rig == null:
		return
	if amount <= 0.0:
		return
	var local := player.cam_rig.global_transform.basis.inverse() * from_direction
	_damage_arcs.append({"dir": atan2(local.x, -local.z), "t": 1.0, "amount": amount})
	_hit_t = maxf(_hit_t, 0.0)


func _on_hidden(hidden: bool) -> void:
	_hidden = hidden
	_status_label.text = "CONCEALED — [E] to leave" if hidden else ""
	_status_label.add_theme_color_override("font_color", UI.COLD)


func _on_died() -> void:
	_status_label.text = ""


func hitmarker(head := false) -> void:
	_hit_t = 0.34
	_hit_head = head


func set_spread(radians: float) -> void:
	_spread = radians


func set_alert(level: float) -> void:
	_alert = level
	if level > 0.75:
		_alert_label.text = "◤ SPOTTED ◢"
		_alert_label.add_theme_color_override("font_color", UI.BLOOD)
	elif level > 0.35:
		_alert_label.text = "◤ SEARCHING ◢"
		_alert_label.add_theme_color_override("font_color", UI.AMBER)
	else:
		_alert_label.text = ""


func toast(text: String) -> void:
	if _toast_box == null:
		return
	var l := UI.label(text.to_upper(), 18, UI.TEXT, 2.0, 0.3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.modulate.a = 0.0
	_toast_box.add_child(l)
	var t := create_tween()
	t.tween_property(l, "modulate:a", 1.0, 0.25)
	t.tween_interval(2.6)
	t.tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)
	while _toast_box.get_child_count() > 4:
		_toast_box.get_child(0).queue_free()
		_toast_box.remove_child(_toast_box.get_child(0))


func subtitle(speaker: String, text: String, duration := 3.5) -> void:
	if not bool(Settings.getv("subtitles")):
		return
	_subtitle_root.visible = true
	_subtitle_speaker.text = speaker.to_upper()
	_subtitle_text.text = text
	var t := create_tween()
	t.tween_interval(duration)
	t.tween_property(_subtitle_root, "modulate:a", 0.0, 0.5)
	t.tween_callback(func():
		_subtitle_root.visible = false
		_subtitle_root.modulate.a = 1.0)


# ------------------------------------------------------------------- drawing

func _process(delta: float) -> void:
	_hit_t = maxf(0.0, _hit_t - delta * 2.6)
	var alive_arcs: Array = []
	for a in _damage_arcs:
		a["t"] = float(a["t"]) - delta * 0.75
		if a["t"] > 0.0:
			alive_arcs.append(a)
	_damage_arcs = alive_arcs

	if player != null and player.alive and not _hidden:
		_spread = player._current_spread()
	elif _hidden:
		_spread = 0.0

	_update_fps(delta)
	queue_redraw()


func _update_fps(delta: float) -> void:
	if not bool(Settings.getv("show_fps")):
		if _fps_label.text != "":
			_fps_label.text = ""
		return
	_fps_accum += delta
	_fps_frames += 1
	if _fps_accum < 0.5:
		return
	_fps_label.text = "%d FPS" % roundi(_fps_frames / _fps_accum)
	_fps_accum = 0.0
	_fps_frames = 0


func _draw() -> void:
	var centre := size * 0.5
	if _hidden:
		_draw_damage_arcs(centre)
		return

	var gap := 5.0 + _spread * 165.0
	var tick := 9.0
	var col := Color(0.87, 0.93, 0.97, 0.85)
	if player != null and player.aiming:
		col = Color(1.0, 0.72, 0.35, 0.95)
		tick = 11.0
	var w := 1.6
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(centre + d * gap, centre + d * (gap + tick), col, w)
	draw_circle(centre, 1.6, col)

	# --- hit marker -------------------------------------------------------
	if _hit_t > 0.0:
		var a := clampf(_hit_t / 0.34, 0.0, 1.0)
		var hc := Color(1.0, 0.95, 0.85, a)
		if _hit_head:
			hc = Color(1.0, 0.45, 0.35, a)
		var inner := 5.0
		var outer := 5.0 + 9.0 * (1.0 - a) + 5.0
		for d in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			draw_line(centre + d * inner, centre + d * outer, hc, 2.0)

	_draw_damage_arcs(centre)

	# --- reload ring ------------------------------------------------------
	if player != null and player._reloading:
		var prog := clampf(player._reload_t / Player.RELOAD_TIME, 0.0, 1.0)
		var pts := PackedVector2Array()
		var steps := 36
		for i in range(steps + 1):
			var ang := -PI / 2.0 + TAU * prog * float(i) / float(steps)
			pts.append(centre + Vector2(cos(ang), sin(ang)) * 26.0)
		if pts.size() > 1:
			draw_polyline(pts, Color(1.0, 0.72, 0.35, 0.9), 2.4)


func _draw_damage_arcs(centre: Vector2) -> void:
	for a in _damage_arcs:
		var t: float = a["t"]
		var dir: float = a["dir"]
		var alpha := clampf(t, 0.0, 1.0) * 0.85
		var r := 62.0
		var span := deg_to_rad(26.0)
		var pts := PackedVector2Array()
		for i in range(13):
			var ang := -PI / 2.0 + dir + span * (float(i) / 12.0 - 0.5)
			pts.append(centre + Vector2(cos(ang), sin(ang)) * r)
		draw_polyline(pts, Color(1.0, 0.28, 0.22, alpha), 3.0)
