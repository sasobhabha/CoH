extends Chapter
## CHAPTER V -- THE MEADOW
##
## The release.  After four chapters of rain and concrete the palette flips
## completely: full sun, volumetric god rays, and a walk uphill toward the
## light -- past the largest monument of the lot, guarded by their best.

const PATH_END := -120.0

var _light_node: Node3D
var _bloom: OmniLight3D
var _motes: GPUParticles3D
var _garrison: Array = []


func describe() -> void:
	_spawn = Vector3(0, 0.3, 34)
	_spawn_yaw = 0.0
	GameManager.set_objectives([
		{"id": "walk", "text": "Walk into the light"},
		{"id": "monument", "text": "Shoot the monument"},
	])


func build() -> void:
	_ground()
	_hills()
	_grass()
	_trees()
	_path()
	_the_light()
	_monument_camp()
	set_process(true)


func _ground() -> void:
	ground(Vector2(210, 200), 0.0, MatLib.meadow(), 2.0)


func _hills() -> void:
	# Flattened spheres read as rolling ground once the grass field covers them.
	var r := RandomNumberGenerator.new()
	r.seed = 5150
	for i in 9:
		var a := TAU * float(i) / 9.0 + 0.3
		var dist := 62.0 + r.randf_range(-10.0, 16.0)
		var radius := r.randf_range(14.0, 26.0)
		Build.sphere(structures(), radius, Vector3(cos(a) * dist, -radius * 0.86, sin(a) * dist),
				MatLib.meadow(), Vector3(1.0, 0.30, 1.0), false)
	# the rise the player walks up to
	Build.sphere(structures(), 34.0, Vector3(0, -28.0, PATH_END - 14.0), MatLib.meadow(),
			Vector3(1.0, 0.34, 1.0), false)
	# a walkable ramp so the rise is climbable
	Build.ramp(structures(), 16.0, 26.0, 2.6, Vector3(0, 0, PATH_END + 14.0), MatLib.meadow())


func _grass() -> void:
	Build.grass_field(self, Vector3(0, 0, -20), Vector3(80, 0, 80), 2600, 7, 0.55)
	Build.grass_field(self, Vector3(0, 0, -100), Vector3(40, 0, 30), 900, 8, 0.42)
	# wildflowers
	var r := RandomNumberGenerator.new()
	r.seed = 313
	var flowers := [
		MatLib.flat(Color("ffd85a"), "flower_a"),
		MatLib.flat(Color("ffffff"), "flower_b"),
		MatLib.flat(Color("d07ad0"), "flower_c"),
	]
	for i in 240:
		var p := Vector3(r.randf_range(-70, 70), r.randf_range(0.16, 0.34), r.randf_range(20, -150))
		Build.quad(self, Vector2(0.12, 0.12), p, flowers[r.randi() % flowers.size()],
				Vector3(0, r.randf_range(0, 90), 0))


func _trees() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 606
	var bark := MatLib.wood_dark()
	var leaf := MatLib.flat(Color("4f7a35"), "leaf", 1.0)
	leaf.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	leaf.albedo_color = Color("547f38")
	for i in 34:
		var a := r.randf_range(0.0, TAU)
		var dist := r.randf_range(52.0, 96.0)
		var p := Vector3(cos(a) * dist, 0, sin(a) * dist - 30.0)
		var h := r.randf_range(6.0, 13.0)
		var t := Node3D.new()
		t.position = p
		structures().add_child(t)
		Build.cylinder(t, 0.34, h, Vector3(0, h * 0.5, 0), bark, Vector3.ZERO, true)
		for k in 3:
			var off := Vector3(r.randf_range(-1.8, 1.8), h * 0.82 + float(k) * 1.5, r.randf_range(-1.8, 1.8))
			Build.sphere(t, r.randf_range(2.2, 3.6), off, leaf, Vector3(1.0, 0.82, 1.0), false)


func _path() -> void:
	var stone := MatLib.concrete()
	for i in 30:
		var z := 30.0 - float(i) * 5.0
		var x := sin(float(i) * 0.55) * 2.4
		Build.box(props(), Vector3(2.6, 0.10, 2.0), Vector3(x, 0.05, z), stone,
				Vector3(0, float(i) * 11.0, 0), false)
	# a marker stone at the end of the path
	Build.box(props(), Vector3(1.4, 3.0, 0.6), Vector3(0, 1.5, PATH_END + 12.0), MatLib.concrete_dark(),
			Vector3(0, 6.0, 0), true)


func _the_light() -> void:
	_light_node = Node3D.new()
	_light_node.position = Vector3(0, 0, PATH_END - 6.0)
	structures().add_child(_light_node)

	# a standing ring of pale stone around the light
	for i in 10:
		var a := TAU * float(i) / 10.0
		Build.box(_light_node, Vector3(0.8, 4.4, 0.8),
				Vector3(cos(a) * 7.0, 2.2, sin(a) * 7.0), MatLib.concrete(),
				Vector3(0, rad_to_deg(a), 0), true)

	var core := MatLib.emissive(Color("fff4d8"), 12.0)
	Build.sphere(_light_node, 1.5, Vector3(0, 4.6, 0), core, Vector3.ONE, false)
	_bloom = Build.omni(_light_node, Vector3(0, 4.6, 0), Color("fff0cf"), 26.0, 70.0, false, 6.0)

	# god rays through the gap
	for i in 7:
		var a := TAU * float(i) / 7.0
		Build.shaft(_light_node, Vector2(4.0, 26.0),
				Vector3(cos(a) * 2.4, 12.0, sin(a) * 2.4), Vector3(-16.0, rad_to_deg(a), 0),
				Color(1.0, 0.95, 0.82), 0.055)
	Build.spot(_light_node, Vector3(0, 12.0, 0), Vector3(-88, 0, 0), Color("fff2d6"), 9.0, 60.0, 44.0,
			false, 6.0)

	_motes = FX.dust(self, 320, Vector3(16, 8, 16), 0.035, Color(1.0, 0.96, 0.85, 0.55))
	_motes.position = Vector3(0, 4.0, PATH_END - 6.0)

	Build.sun(self, Vector3(-34, 24, 0), Color("fff2d8"), 1.9, 1.4)

	var arrive := TriggerZone.make(_light_node, Vector3(0, 2.0, 2.0), Vector3(12, 6, 6), "light")
	arrive.entered.connect(_on_arrive)


func _on_arrive(_p: Node) -> void:
	if done("walk"):
		return
	complete("walk")
	if done("monument"):
		return
	if game != null:
		await game.call("play_dialogue", [
			{"speaker": "You", "text": "The record said there was a door. It did not say it opened onto this."},
			{"speaker": "", "text": "Someone has been looking after it. There are tools by the wall, and the wall is straight."},
			{"speaker": "", "text": "Down the hill, in the wet city, the monolith finishes another century of rain."},
		])


func surface_at(_pos: Vector3) -> String:
	return "grass"


# ---------------------------------------------------------------- monument

## Even here, at the door out, they raised the largest monument of the lot --
## half the size of the true monolith, on its own rise, ringed by their best.
## Bringing it down is the whole campaign's ending.
func _monument_camp() -> void:
	var pos := Vector3(38.0, 0.0, 26.0)
	var body := place_monument(pos, 135.0, 0.45, 900.0)
	monument_on_down(body, _on_monument_down)
	_garrison = [
		spawn_enemy(pos + Vector3(-7.0, 0.3, 6.0), "heavy",
				ring_patrol(pos, 10.0, 4), true),
		spawn_enemy(pos + Vector3(7.0, 0.3, -6.0), "guard",
				ring_patrol(pos, 10.0, 4, PI * 0.5), true),
		spawn_enemy(pos + Vector3(8.0, 0.3, 7.0), "guard",
				ring_patrol(pos, 10.0, 4, PI), true),
		spawn_enemy(pos + Vector3(-6.0, 0.3, -8.0), "trooper",
				line_patrol(pos + Vector3(-12.0, 0.3, -14.0),
						pos + Vector3(12.0, 0.3, -14.0), 3)),
	]
	body.damaged.connect(func(_amount: float, point: Vector3) -> void:
		for g in _garrison:
			if is_instance_valid(g) and g.alive:
				g.receive_alert(point))
	add_pickup(pos + Vector3(0.0, 0.3, 14.0), "ammo", 90)
	add_pickup(pos + Vector3(-10.0, 0.3, 4.0), "health", 50)


func _on_monument_down() -> void:
	complete("monument")
	notify("IT IS DOWN. IT IS OVER.")
	for e in _garrison:
		if is_instance_valid(e) and e.alive:
			e.queue_free()
	_garrison.clear()
	await get_tree().create_timer(2.6).timeout
	finish()


func _process(delta: float) -> void:
	super._process(delta)
	if _bloom != null:
		_bloom.light_energy = 26.0 + sin(Time.get_ticks_msec() / 1400.0) * 3.0
	if _motes != null and game != null and game.player != null:
		_motes.position = Vector3(game.player.global_position.x, 4.0, game.player.global_position.z)
