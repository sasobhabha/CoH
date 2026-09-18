class_name GameScene
extends Node3D
## The campaign container.
##
## Owns the persistent things (player, HUD, post grade, effects, audio) and
## swaps the chapter world underneath them.  Chapters never talk to the UI
## directly; they raise signals and this scene routes them.

signal to_menu_requested
signal run_finished

const ENEMY_SCRIPT := "res://scripts/ai/Enemy.gd"
const CHAPTER_SCRIPTS := [
	"res://scripts/chapters/Ch01_OccupiedPlaza.gd",
	"res://scripts/chapters/Ch02_Tavern.gd",
	"res://scripts/chapters/Ch03_FloodMarket.gd",
	"res://scripts/chapters/Ch04_TheDark.gd",
	"res://scripts/chapters/Ch05_Meadow.gd",
]

var ui_layer: CanvasLayer
var world: Node3D
var chapter = null
var player: Player
var hud: HUD
var pause: PauseMenu
var radial: RadialMenu
var dialog: DialogueUI
var post: PostFX
var tracers: TracerPool
var impacts: ImpactPool
var env: WorldEnvironment
var enemies: Array = []

var _ui_built := false
var _dying := false
var _finished := false
var _radial_cb: Callable
var _respawn := Vector3.ZERO
var _respawn_yaw := 0.0
var _enemy_alert := 0.0
var _field_objective := ""


func begin(chapter_index: int, quick := false, force_intro := false) -> void:
	GameManager.chapter = clampi(chapter_index, 0, CHAPTER_SCRIPTS.size() - 1)
	_build_persistent()
	await _load_chapter(GameManager.chapter)

	# A forced intro has to run before the quick return, otherwise a capture or
	# dev launch skips straight past it.
	if force_intro:
		await play_intro()
		GameManager.complete_objective("__intro__")

	if quick:
		Transition.set_black(false)
		player.input_blocked = false
		if chapter != null and chapter.has_method("on_start"):
			chapter.call("on_start")
		return

	# Otherwise it is remembered in the save, so a fresh run gets it and a resumed
	# one does not sit through it again.  Chapters with no shot list skip it.
	if not GameManager.is_done("__intro__"):
		await play_intro()
		GameManager.complete_objective("__intro__")

	await _chapter_card(GameManager.chapter)
	player.input_blocked = false
	if chapter != null and chapter.has_method("on_start"):
		chapter.call("on_start")


# -------------------------------------------------------------------- intro
#
# A short in-engine opening.  The camera drifts along a path the chapter
# supplies and aims at points in the real level, so the cinematic cannot fall
# out of sync with the world it is showing -- there is no second copy of it.

## Set by the launcher when a capture run should also record the intro.
var capture_intro := false

var _intro_cam: Camera3D
var _intro_aim: Node3D
var _intro_shots: Array = []
var _intro_t := 0.0
var _intro_len := 0.0
var _intro_beat := -1
var _intro_grabbed := 0


func _intro_active() -> bool:
	return _intro_cam != null


func play_intro(total := 26.0) -> void:
	if chapter == null or not chapter.has_method("intro_shots"):
		return
	_intro_shots = chapter.call("intro_shots")
	if _intro_shots.size() < 2:
		return

	_intro_len = total
	_intro_t = 0.0
	_intro_beat = -1
	_intro_grabbed = 0
	player.input_blocked = true

	var first: Dictionary = _intro_shots[0]
	_intro_aim = Node3D.new()
	_intro_aim.name = "IntroAim"
	add_child(_intro_aim)
	_intro_aim.global_position = first["look"]

	_intro_cam = Camera3D.new()
	_intro_cam.name = "IntroCam"
	_intro_cam.fov = 46.0
	_intro_cam.near = 0.05
	_intro_cam.far = 700.0
	add_child(_intro_cam)
	_intro_cam.global_position = first["pos"]
	_intro_cam.look_at(_intro_aim.global_position, Vector3.UP)
	_intro_cam.current = true

	Transition.letterbox(true, 1.2)
	AudioDirector.set_ambience(["amb_rain", "amb_wind", "amb_water"], 3.5)
	AudioDirector.music("mus_explore", 6.0, -22.0)
	if hud != null:
		hud.visible = false
	# the boot already put us behind black, so the intro has to fade up itself
	await Transition.from_black(1.8)

	print("INTRO start shots=%d len=%.1fs" % [_intro_shots.size(), total])
	while _intro_active():
		await get_tree().process_frame
	print("INTRO done")


## Returns true once the drift has run its length.
func _intro_step(delta: float) -> bool:
	_intro_t += delta
	var n := _intro_shots.size()
	var u := clampf(_intro_t / _intro_len, 0.0, 1.0)
	var f := u * float(n - 1)
	var i := clampi(int(floor(f)), 0, n - 2)
	var k := smoothstep(0.0, 1.0, f - float(i))
	var a: Dictionary = _intro_shots[i]
	var b: Dictionary = _intro_shots[i + 1]
	var pa: Vector3 = a["pos"]
	var pb: Vector3 = b["pos"]
	var la: Vector3 = a["look"]
	var lb: Vector3 = b["look"]
	_intro_cam.global_position = pa.lerp(pb, k)
	_intro_aim.global_position = la.lerp(lb, k)
	_intro_cam.look_at(_intro_aim.global_position, Vector3.UP)
	_intro_beat_for(i)
	if capture_intro and int(_intro_t / 3.0) > _intro_grabbed:
		_intro_grabbed += 1
		_save_intro_frame(_intro_grabbed)
	return u >= 1.0


func _intro_beat_for(i: int) -> void:
	if i <= _intro_beat:
		return
	_intro_beat = i
	var shot: Dictionary = _intro_shots[clampi(i, 0, _intro_shots.size() - 1)]
	if shot.has("title"):
		AudioDirector.play("chapter", -6.0, 1.0, 0.0, "UI")
		var info := GameManager.chapter_info(GameManager.chapter)
		Transition.show_title(String(shot["title"]),
				String(info.get("name", "")), 2.6, 1.2)
	elif shot.has("text") and hud != null:
		hud.subtitle("", String(shot["text"]), 4.6)


func _save_intro_frame(index: int) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://caps/intro_%02d.png" % index)
	print("captured intro_%02d" % index)


func _finish_intro() -> void:
	if _intro_cam != null:
		_intro_cam.queue_free()
		_intro_cam = null
	if _intro_aim != null:
		_intro_aim.queue_free()
		_intro_aim = null
	if hud != null:
		hud.visible = true
	# The viewport must be handed back to a camera, or the game renders nothing
	# at all once the intro camera is freed.
	if player != null and player.cam_rig != null:
		player.cam_rig.current = true
	AudioDirector.music("mus_explore", 2.5, -12.0)
	Transition.letterbox(false, 1.0)


## Cinematic chapter heading: letterbox, title card, one line of flavour.
func _chapter_card(index: int) -> void:
	var info := GameManager.chapter_info(index)
	await Transition.letterbox(true, 0.8)
	await Transition.show_title(String(info.get("title", "")), String(info.get("name", "")), 2.6, 1.4)
	if hud != null:
		hud.subtitle("", String(info.get("brief", "")), 4.2)
	await Transition.letterbox(false, 1.0)


func _build_persistent() -> void:
	if _ui_built:
		return
	_ui_built = true

	env = WorldEnvironment.new()
	add_child(env)

	tracers = TracerPool.new()
	tracers.name = "Tracers"
	add_child(tracers)

	impacts = ImpactPool.new()
	impacts.name = "Impacts"
	add_child(impacts)

	player = Player.new()
	player.name = "Player"
	player.game = self
	add_child(player)
	player.died.connect(_on_player_died)

	ui_layer = CanvasLayer.new()
	ui_layer.layer = 5
	add_child(ui_layer)

	post = PostFX.new()
	post.name = "PostFX"
	ui_layer.add_child(post)

	hud = HUD.new()
	ui_layer.add_child(hud)
	hud.bind_player(player)
	player.focus_changed.connect(func(_t, _l): pass)

	pause = PauseMenu.new()
	# The tree pauses while the menu is up, so this subtree must keep running:
	# without it the menu's buttons and its own input handling are frozen along
	# with the game and nothing on the pause screen responds.
	pause.process_mode = Node.PROCESS_MODE_ALWAYS
	pause.resumed.connect(func(): GameManager.set_paused(false))
	pause.quit_to_menu.connect(_on_quit_to_menu)
	ui_layer.add_child(pause)

	dialog = DialogueUI.new()
	ui_layer.add_child(dialog)

	radial = RadialMenu.new()
	radial.process_mode = Node.PROCESS_MODE_ALWAYS
	ui_layer.add_child(radial)

	player.noised.connect(_on_noise)
	player.damaged.connect(_on_player_damaged)

	Settings.changed.connect(_apply_quality)


func _apply_quality() -> void:
	if env != null and env.environment != null:
		Settings.apply_quality(env.environment)


# ------------------------------------------------------------------ chapters

func _load_chapter(index: int) -> void:
	if world != null:
		remove_child(world)
		world.queue_free()
		world = null
	if chapter != null:
		chapter = null
	enemies.clear()
	tracers.clear_all()

	env.environment = EnvLib.for_chapter(index)
	Settings.apply_quality(env.environment)

	world = Node3D.new()
	world.name = "World_%d" % index
	add_child(world)

	chapter = load(CHAPTER_SCRIPTS[index]).new()
	chapter.name = "Chapter"
	chapter.call("setup", self, index)
	world.add_child(chapter)
	chapter.finished.connect(_on_chapter_finished)

	var spawn: Vector3 = chapter.call("spawn_position")
	var yaw: float = chapter.call("spawn_yaw")
	_respawn = spawn
	_respawn_yaw = yaw
	player.revive(spawn, yaw)
	player.input_blocked = true
	hud.refresh_objectives()

	await get_tree().process_frame


func surface_at(pos: Vector3) -> String:
	if chapter != null and chapter.has_method("surface_at"):
		return String(chapter.call("surface_at", pos))
	return "concrete"


## One-shot screen flash for big moments (the monument blast).  Strength is
## the peak whiteness 0..1; the rect fades and frees itself.
func flash(strength := 0.9, tint := Color(1.0, 0.9, 0.75)) -> void:
	if post != null:
		post.flash(tint, strength, 0.7)


func _on_chapter_finished() -> void:
	if _finished:
		return
	_finished = true
	player.input_blocked = true
	AudioDirector.music("", 1.6)
	await Transition.to_black(1.8)

	var next := GameManager.chapter + 1
	if next >= CHAPTER_SCRIPTS.size():
		await _credits()
		run_finished.emit()
		return

	GameManager.chapter = next
	GameManager.save_game()
	await _load_chapter(next)
	await Transition.from_black(0.4)
	await _chapter_card(next)
	_finished = false
	player.input_blocked = false
	if chapter != null and chapter.has_method("on_start"):
		chapter.call("on_start")


## The monument finale: the chapter stages the collapse, waits out the dust,
## then calls this.  Straight to credits -- no next chapter, no save.
func finish_run() -> void:
	if _finished:
		return
	_finished = true
	player.input_blocked = true
	AudioDirector.music("", 1.6)
	await Transition.to_black(2.2)
	await _credits()
	run_finished.emit()


func _credits() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 8
	add_child(layer)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.position = Vector2(-420, -160)
	box.custom_minimum_size = Vector2(840, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.modulate.a = 0.0
	layer.add_child(box)

	box.add_child(_centered(UI.title("CENTURY OF HUMILIATION", 46)))
	box.add_child(_centered(UI.label("A CENTURY OF ASH", 20, UI.AMBER, 12.0, 0.35)))
	box.add_child(UI.hsep(24))
	box.add_child(_centered(UI.label("the square belongs to someone else", 18, UI.DIM)))
	box.add_child(UI.hsep(30))
	var stats := [
		"TIME  %s" % UI.format_time(float(GameManager.stats.get("playtime", 0.0))),
		"ACCURACY  %d%%" % roundi(GameManager.accuracy() * 100.0),
		"HOSTILES DOWN  %d" % int(GameManager.stats.get("kills", 0)),
		"DEATHS  %d" % int(GameManager.stats.get("deaths", 0)),
	]
	for s in stats:
		box.add_child(_centered(UI.label(s, 16, UI.FAINT, 2.0)))
	box.add_child(UI.hsep(34))
	box.add_child(_centered(UI.label("thank you for playing", 16, UI.FAINT, 1.0)))

	AudioDirector.music("mus_meadow", 4.0, -8.0)
	var t := create_tween()
	t.tween_property(box, "modulate:a", 1.0, 2.4)
	t.tween_interval(6.5)
	t.tween_property(box, "modulate:a", 0.0, 2.0)
	await t.finished
	layer.queue_free()


func _centered(c: Control) -> Control:
	if c is Label:
		(c as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return c


# -------------------------------------------------------------------- enemies

func spawn_enemy(pos: Vector3, kind := "trooper", patrol := [], has_light := false) -> Node:
	var e = load(ENEMY_SCRIPT).new()
	e.kind = kind
	e.game = self
	e.patrol_points = PackedVector3Array(patrol)
	e.has_light = has_light
	e.position = pos
	world.add_child(e)
	e.died.connect(_on_enemy_died)
	enemies.append(e)
	return e


func alert_enemies(from: Vector3, pos: Vector3, radius: float) -> void:
	for e in enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		if e.global_position.distance_to(from) <= radius:
			e.receive_alert(pos)


func on_enemy_died(e: Node) -> void:
	if randf() < 0.45:
		var p := Pickup.new()
		p.setup(e.global_position + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4)),
				"ammo", 45, randf_range(0, TAU))
		world.add_child(p)
	enemies.erase(e)


func enemies_alive() -> int:
	var n := 0
	for e in enemies:
		if is_instance_valid(e) and e.alive:
			n += 1
	return n


func _on_enemy_died(_e: Node) -> void:
	pass


func _on_noise(pos: Vector3, radius: float) -> void:
	for e in enemies:
		if is_instance_valid(e) and e.alive:
			e.hear_noise(pos, radius)


# ---------------------------------------------------------------- interactions

func open_radial(options: Array, caption: String, callback: Callable) -> void:
	_radial_cb = callback
	player.input_blocked = true
	if not radial.chosen.is_connected(_on_radial_result):
		radial.chosen.connect(_on_radial_result)
	if not radial.cancelled.is_connected(_on_radial_cancel):
		radial.cancelled.connect(_on_radial_cancel)
	radial.open(options, caption)


func _on_radial_result(id: String) -> void:
	player.input_blocked = false
	# The press that closed the wheel must not also re-trigger the thing that
	# opened it (E) or fire a round (click release).
	player.suppress_actions(0.2)
	var cb := _radial_cb
	_radial_cb = Callable()
	if cb.is_valid():
		cb.call(id)


func _on_radial_cancel() -> void:
	player.input_blocked = false
	player.suppress_actions(0.2)
	var cb := _radial_cb
	_radial_cb = Callable()
	if cb.is_valid():
		cb.call("")


func play_dialogue(lines: Array) -> void:
	player.input_blocked = true
	dialog.play(lines)
	await dialog.finished
	player.input_blocked = false


func notify(text: String) -> void:
	GameManager.toast_message(text)


func checkpoint(pos: Vector3, yaw := 0.0) -> void:
	_respawn = pos
	_respawn_yaw = yaw
	AudioDirector.play("checkpoint", -6.0, 1.0, 0.0, "UI")
	GameManager.toast_message("CHECKPOINT")


# ---------------------------------------------------------------------- death

func _on_player_damaged(_dir: Vector3, _amount: float) -> void:
	pass


func _on_player_died() -> void:
	if _dying:
		return
	_dying = true
	hud.subtitle("", "You died. The district does not care.", 3.0)
	AudioDirector.duck_music(-22.0, 1.0)
	await get_tree().create_timer(2.4).timeout
	await Transition.to_black(1.6)
	enemies.clear()
	await _load_chapter(GameManager.chapter)
	player.input_blocked = false
	_dying = false
	await Transition.from_black(1.4)
	AudioDirector.unduck_music(1.5)


# -------------------------------------------------------------------- process

func _process(delta: float) -> void:
	if _intro_cam != null:
		# A 26-second drift with no way out is the first thing between a player
		# and the game.  Jump or pause skips to the last shot rather than cutting
		# the camera, so the segment still resolves into the fades and the title.
		if Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("jump"):
			_intro_t = _intro_len
		if _intro_step(delta):
			_finish_intro()
	if player != null and hud != null and not player.alive:
		hud.set_alert(0.0)
		return

	# The chapter owns the waterline; the player owns buoyancy.  One float a
	# frame keeps the two from ever disagreeing.
	if player != null and chapter != null:
		player.set_water_level(chapter.water_level)

	# Out-of-bounds net: any fall past the world's floor returns the player to
	# the last checkpoint instead of stranding them under the map.  Cheap -- one
	# height compare a frame -- and it covers every chapter, including places
	# the geometry backfill may still miss.
	if player != null and player.alive and player.global_position.y < -30.0:
		player.velocity = Vector3.ZERO
		player.global_position = _respawn + Vector3(0, 0.5, 0)
		player.cam_rig.yaw = _respawn_yaw
		player.rig.rotation.y = _respawn_yaw
		hud.subtitle("", "The district spat you back out.", 2.2)

	# alert pip derived from the squad's state
	var worst := 0.0
	for e in enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		var s: int = e.state
		match s:
			2: worst = maxf(worst, 0.55)
			3: worst = maxf(worst, 1.0)
			4: worst = maxf(worst, 0.7)
	_enemy_alert = lerpf(_enemy_alert, worst, minf(1.0, delta * 2.5))
	if hud != null:
		hud.set_alert(_enemy_alert)


func _unhandled_input(event: InputEvent) -> void:
	if _finished or _dying:
		return
	if dialog != null and dialog.is_open():
		return
	if radial != null and radial.is_open():
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if pause.visible:
			GameManager.set_paused(false)
			pause.close()
		else:
			GameManager.set_paused(true)
			pause.open()
	elif event.is_action_pressed("radial"):
		get_viewport().set_input_as_handled()
		_open_field_radial()
	elif event.is_action_pressed("screenshot"):
		_take_screenshot()
	elif event.is_action_pressed("fps_toggle"):
		Settings.setv("show_fps", not bool(Settings.getv("show_fps")))
	elif event.is_action_pressed("mute_toggle"):
		var on := Settings.toggle_mute()
		if hud != null:
			hud.subtitle("", "AUDIO %s" % ("MUTED" if on else "ON"), 1.4)


func _open_field_radial() -> void:
	_field_objective = GameManager.active_objective()
	if _field_objective.is_empty():
		_field_objective = "the district is quiet"
	open_radial([
		{"id": "objective", "label": "Objective", "hint": _field_objective.substr(0, 26)},
		{"id": "status", "label": "Status", "hint": "vitals and rounds"},
		{"id": "leave", "label": "Resume", "hint": "back to it"},
	], "FIELD MENU", _on_field_option)


func _on_field_option(id: String) -> void:
	match id:
		"objective":
			GameManager.toast_message(_field_objective)
		"status":
			var spare := "UNLIMITED" if Player.UNLIMITED_AMMO else str(player.reserve)
			GameManager.toast_message("%d VITALS  %d ROUNDS  %s SPARE"
					% [roundi(player.health), player.mag, spare])


## Developer aid: orbit the camera, grab frames, quit.  Used to review the
## look of each chapter without a human at the keyboard.
func capture_views(count := 8, settle := 2.5) -> void:
	var dir := "user://caps"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	player.input_blocked = true
	Transition.set_black(false)
	_hide_ui_for_capture()
	# A window that macOS considers hidden stops presenting frames, and a
	# stopped renderer hands back the same framebuffer forever.
	DisplayServer.window_move_to_foreground()
	# An automated review run must always terminate, even if a frame stalls --
	# but a *flat* budget cuts the review short instead: as the chapters got
	# heavier, a run that was still making progress began dying eight vantages
	# in, and the missing views looked like vantages that had not been authored.
	# So the deadline is reset by each captured frame: it still catches a stall,
	# and no longer mistakes slow for stuck.
	# A `Timer` node rather than `create_timer`: a SceneTreeTimer fires once and
	# cannot be restarted, so it cannot be used as a deadline that moves.
	var watchdog := Timer.new()
	watchdog.name = "CaptureWatchdog"
	watchdog.one_shot = true
	watchdog.wait_time = 75.0
	watchdog.timeout.connect(func(): push_warning("capture watchdog fired"); get_tree().quit())
	add_child(watchdog)
	watchdog.start()
	print("CAP begin ch%d" % GameManager.chapter)
	_diag()
	var shots: Array = []
	if chapter != null and chapter.has_method("review_vantages"):
		shots = chapter.call("review_vantages")
	if shots.is_empty():
		for i in count:
			shots.append({"yaw": TAU * float(i) / float(count), "spin": true})
	await get_tree().create_timer(settle).timeout
	_diag_rig()
	var n := 0
	for s in shots:
		if bool(s.get("spin", false)):
			player.cam_rig.yaw = float(s.get("yaw", 0.0))
			player.rig.rotation.y = player.cam_rig.yaw
		else:
			var p: Vector3 = s.get("pos", player.global_position)
			player.global_position = p
			player.velocity = Vector3.ZERO
			player.cam_rig.yaw = float(s.get("yaw", 0.0))
			player.rig.rotation.y = player.cam_rig.yaw
		player.cam_rig.pitch = float(s.get("pitch", -0.06))
		await get_tree().create_timer(0.7).timeout
		watchdog.start()
		print("CAP at %s want %s cam%s yaw%.2f" % [str(player.global_position.round()),
				str(Vector3(s.get("pos", Vector3.ZERO)).round()),
				str(player.cam_rig.global_position.round()), player.cam_rig.yaw])
		_probe_view(String(s.get("name", "v%d" % n)))
		# The framebuffer is only valid to read once the renderer has finished a
		# draw for this frame; process_frame alone can hand back the previous
		# one, which is how every vantage ends up identical.
		# Read back only after the renderer has actually presented the frame we
		# just posed; process_frame alone can hand back the previous one.
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/ch%d_%02d.png" % [dir, GameManager.chapter, n])
		print("captured ch%d_%02d %s" % [GameManager.chapter, n, String(s.get("name", ""))])
		n += 1
	get_tree().quit()


func _hide_ui_for_capture() -> void:
	## Capture mode reviews the world, not the interface.
	if hud != null:
		hud.visible = false
	if post != null:
		post.vignette = 0.35


## What is actually in front of a review camera, so a dark frame can be told
## apart from an empty one.
##
## This exists because "the suburb vantage renders almost black" is a symptom
## with unrelated causes -- nothing in frame, geometry in frame that is unlit,
## or the third-person arm pulled in against a wall behind the player -- and
## the frame itself cannot distinguish them.
func _probe_view(tag: String) -> void:
	var cam := player.cam_rig
	if cam == null:
		return
	var space := player.get_world_3d().direct_space_state
	var vp := get_viewport().get_visible_rect().size
	var tally := {}
	# Pre-sized rows: `append([""])` would be a row holding one empty string,
	# not an empty row, and every column past the first then fails to assign.
	var cell: Array = []
	for _gy in 5:
		var row: Array = []
		row.resize(5)
		cell.append(row)
	for gy in 5:
		for gx in 5:
			var px := vp * Vector2((float(gx) + 0.5) / 5.0, (float(gy) + 0.5) / 5.0)
			var origin := cam.project_ray_origin(px)
			var dir := cam.project_ray_normal(px)
			var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 300.0)
			query.collide_with_areas = false
			var hit := space.intersect_ray(query)
			var key := "(open sky)"
			var dist := 300.0
			if not hit.is_empty():
				var collider = hit.get("collider")
				key = String(collider.name) if collider is Node else "?"
				dist = origin.distance_to(hit["position"])
			var code := _short(key)
			cell[gy][gx] = "%s%-4.0f" % [code, dist] if key != "(open sky)" \
					else "sky--"
			if not tally.has(key):
				tally[key] = {"n": 0, "min": 1e9, "max": 0.0}
			var t: Dictionary = tally[key]
			t["n"] = int(t["n"]) + 1
			t["min"] = minf(float(t["min"]), dist)
			t["max"] = maxf(float(t["max"]), dist)
	var keys := tally.keys()
	keys.sort_custom(func(a, b): return int(tally[a]["n"]) > int(tally[b]["n"]))
	var parts: Array = []
	for k in keys.slice(0, 5):
		parts.append("%s x%d %.0f-%.0fm" % [k, int(tally[k]["n"]),
				float(tally[k]["min"]), float(tally[k]["max"])])
	print("PROBE %-9s cam=%s arm=%.2f fov=%.0f | %s" % [tag,
			str(cam.global_position.round()),
			cam.global_position.distance_to(player.global_position + Vector3(0, 1.52, 0)),
			cam.fov, " | ".join(PackedStringArray(parts))])
	# A second pass, laid out like the frame it belongs to: `cells[row][col]`
	# reads top-to-bottom, left-to-right, so it can be held against the measured
	# brightness of the same picture.  A frame knows it is dark; only this knows
	# whether the reason is sky, near ground, or a wall thirty metres away.
	var cells: Array = []
	for gy in 5:
		var row: Array = []
		for gx in 5:
			row.append(cell[gy][gx])
		cells.append(" ".join(PackedStringArray(row)))
	print("PROBE %-9s map: %s" % [tag, cells[0]])
	for r in range(1, 5):
		print("                %s" % cells[r])


## Four-to-six characters for a collider name, so a 5x5 map stays one screen.
func _short(name: String) -> String:
	var s := name.replace("__", "").replace("_col", "").replace("_collision", "")
	s = s.replace("StaticBody3D", "body").replace("@", "")
	return s.substr(0, 5).rpad(5)


func _diag() -> void:
	## World-side sanity check, valid the moment the chapter is built.

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(chapter, meshes)
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for m in meshes:
		var p := m.global_position
		lo = lo.min(p)
		hi = hi.max(p)
	print("DIAG chapter_children=%d meshes=%d" % [chapter.get_child_count(), meshes.size()])
	print("DIAG structures=%d props=%d" % [chapter.structures().get_child_count(),
			chapter.props().get_child_count()])
	print("DIAG mesh_bounds lo=%s hi=%s" % [str(lo), str(hi)])
	print("DIAG player=%s cam=%s yaw=%.2f" % [str(player.global_position),
			str(player.cam_rig.global_position), player.cam_rig.yaw])
	print("DIAG visible_meshes=%d" % meshes.filter(func(m): return m.is_visible_in_tree()).size())


func _diag_rig() -> void:
	## Keep separate from _diag(): pose data is only meaningful once the
	## AnimationPlayer has ticked at least once, so this runs after the settle.
	if player == null or player.rig == null:
		print("DIAG rig missing")
		return
	var r = player.rig
	print("DIAG rig built=%s skel=%s anim=%s cur=%s"
			% [str(r.model != null), str(r.skeleton != null), str(r.anim != null),
				str(r.current_clip())])
	if r.muzzle != null:
		print("DIAG muzzle=%s" % str(r.muzzle.global_position))
	print("DIAG weapon_fwd=%s body_fwd=%s"
			% [str(r.weapon_forward()), str(-r.global_transform.basis.z)])
	_diag_roster(r)


func _diag_roster(player_rig) -> void:
	## One line per archetype actually present, with the stature measured off the
	## loaded mesh and whether it is holding a rifle.  A kind that silently fell
	## back to the trooper mesh shows up here as a duplicate.
	var seen := {}
	# `enemies` is the list GameScene spawns into, which is the authoritative
	# one: they are parented to `world`, not to the chapter.
	var rigs: Array = [player_rig]
	for e in enemies:
		if is_instance_valid(e) and e.rig != null:
			rigs.append(e.rig)
	var talkers: Array = []
	_collect_talkers(chapter, talkers)
	for t in talkers:
		if t.rig != null:
			rigs.append(t.rig)
	for rig in rigs:
		# `rig` comes out of an untyped Array, so this needs an explicit type:
		# `:=` cannot infer through a Variant and fails at parse time.
		var key: String = String(rig.model_key)
		if seen.has(key):
			continue
		seen[key] = true
		var held := 0
		if rig.weapon_mount != null:
			for c in rig.weapon_mount.get_children():
				if c is MeshInstance3D or (c is Node3D and c.get_child_count() > 0):
					held += 1
		print("DIAG archetype model=%-8s stature=%.3f armed=%s rifle=%s"
				% [key, rig.stature, str(rig.is_armed()), str(held > 0)])


func _collect_talkers(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Talker:
			out.append(c)
		_collect_talkers(c, out)


func _collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		_collect_meshes(c, out)


func _take_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "user://century_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	if img.save_png(path) == OK:
		GameManager.toast_message("SHOT SAVED")


func _on_quit_to_menu() -> void:
	GameManager.set_paused(false)
	pause.close()
	GameManager.save_game()
	to_menu_requested.emit()
