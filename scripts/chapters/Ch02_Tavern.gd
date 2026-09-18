extends Chapter
## CHAPTER II -- THE TAVERN AT KILOMETER NINE
##
## The character beat: one warm room, one person who will talk to you, and the
## radial wheel the whole interaction system is built around.
##
## Every surface here is inside, so the lighting does all the work.  Three
## pendant lamps throw warm pools down the room, the hearth throws a fourth, and
## cold moonlight rakes in through the windows on both long walls.  The contrast
## between those two temperatures is the whole mood.

const ROOM_W := 15.0
const ROOM_L := 28.0
const ROOM_H := 4.7
const BAR_Z := -8.6

var keeper: Talker
var _ledger: Interactable
var _lamp_nodes: Array = []
var _t := 0.0
var _ledger_taken := false
var _shrine_guards: Array = []


func describe() -> void:
	_spawn = Vector3(0, 0.4, 11.5)
	_spawn_yaw = 0.0
	AudioDirector.music("", 1.0)
	AudioDirector.set_ambience(["amb_interior", "amb_rain_light"], 2.0)
	GameManager.set_objectives([
		{"id": "speak", "text": "Speak with the keeper"},
		{"id": "ledger", "text": "Take the ledger"},
		{"id": "monument", "text": "Shoot the monument"},
	])


func build() -> void:
	_shell()
	_furniture()
	_keeper()
	_patrons()
	_shrine()
	_lights()
	_weather_outside()
	_triggers()
	set_process(true)


# --------------------------------------------------------------------- shell

func _shell() -> void:
	# floor slab with its own collision, then the wall shell on top of it
	plate(Vector2(ROOM_W + 3.0, ROOM_L + 3.0), 0.0, 0.0, MatLib.wood_dark(), 1.2)
	var mb := MeshBuilder.new()
	Kit.room(mb, Vector3(0, 0, 0), Vector3(ROOM_W, ROOM_H, ROOM_L), {
		"wall": MatLib.plaster(true),
		"floor": MatLib.wood(),
		"openings": [
			# the doorway out to the street
			{"side": 0, "x": 0.0, "y": 0.0, "w": 2.1, "h": 2.6, "kind": "door"},
			# windows: three a side, high enough to keep the rain out
			{"side": 2, "x": -8.0, "y": 1.55, "w": 2.0, "h": 1.7},
			{"side": 2, "x": -1.5, "y": 1.55, "w": 2.0, "h": 1.7},
			{"side": 2, "x": 5.5, "y": 1.55, "w": 2.0, "h": 1.7},
			{"side": 3, "x": -8.0, "y": 1.55, "w": 2.0, "h": 1.7},
			{"side": 3, "x": -1.5, "y": 1.55, "w": 2.0, "h": 1.7},
			{"side": 3, "x": 5.5, "y": 1.55, "w": 2.0, "h": 1.7},
		],
	})
	var b := Basis.IDENTITY
	# door frame and the street beyond it
	Kit.door_frame(mb, b, Vector3(0, 0, ROOM_L * 0.5), Vector3(0, 0, -1.0), 2.1, 2.6)
	mb.box_at(Vector3(0, 0.2, ROOM_L * 0.5 + 3.0), Vector3(9.0, 0.4, 6.0),
			MatLib.road(), Vector3.ZERO)
	mb.box_at(Vector3(0, 2.6, ROOM_L * 0.5 + 0.4), Vector3(2.4, 0.3, 0.5),
			MatLib.flat(Color(0.20, 0.26, 0.32), "lintel", 0.9))

	# exposed ceiling beams and a boarded-over section
	var timber := MatLib.wood_dark()
	for i in 7:
		var z := -ROOM_L * 0.45 + float(i) * (ROOM_L * 0.15)
		mb.box_at(Vector3(0, ROOM_H - 0.22, z), Vector3(ROOM_W, 0.34, 0.34), timber)

	# glazing and boarding on each window opening
	for side in [-1.0, 1.0]:
		var s := float(side)
		var heading := Vector3(s, 0, 0)
		for z in [-8.0, -1.5, 5.5]:
			var p := Vector3(s * (ROOM_W * 0.5 - 0.16), 1.55, z)
			# the night outside, seen as a flat card behind the glass
			mb.quad(p + heading * 0.34, Vector3(0, 0, 1), Vector3.UP, Vector2(2.2, 1.9),
					MatLib.flat(Color(0.045, 0.07, 0.10), "night", 0.98))
			mb.quad(p + heading * 0.22, Vector3(0, 0, 1), Vector3.UP, Vector2(2.0, 1.7),
					TexLib.glass(Color(0.16, 0.22, 0.26), 0.35))
			# muntins
			mb.box_at(p + heading * 0.20 + Vector3(0, 0.85, 0), Vector3(0.06, 0.06, 2.1),
					MatLib.wood_pale())
			mb.box_at(p + heading * 0.20, Vector3(0.06, 0.06, 2.1), MatLib.wood_pale())
			if absf(z + 1.5) < 0.1:
				# one window half boarded
				for k in 2:
					mb.box_at(p + heading * 0.12 + Vector3(0, -0.3 + float(k) * 0.55, 0.1),
							Vector3(0.07, 0.26, 2.0), MatLib.wood(),
							Vector3(0, 0, float(k) * 5.0 - 4.0))
	_commit(mb, "Shell")


func _commit(mb: MeshBuilder, name: String) -> void:
	if not mb.is_empty():
		mb.commit(structures(), name, true, true)


# ----------------------------------------------------------------- furniture

func _furniture() -> void:
	var mb := MeshBuilder.new()
	var b := Basis.IDENTITY
	var r := RandomNumberGenerator.new()
	r.seed = 5150

	# --- the bar, its back shelf and the bottles on it
	var bar := Vector3(0, 0, BAR_Z)
	Kit.bar_counter(mb, b, bar, Vector3(0, 0, 1.0), 9.6, 611)
	Kit.back_bar(mb, b, Vector3(0, 0, BAR_Z - 2.2), Vector3(0, 0, 1.0), 9.6, 2.7, 612)
	# a low gate at one end of the bar
	Kit.shelf_unit(mb, b, Vector3(5.6, 0, BAR_Z - 0.2), Vector3(-1, 0, 0), 1.4, 1.1, 613)

	# --- hearth on the left wall
	Kit.fireplace(mb, b, Vector3(-ROOM_W * 0.5 + 0.45, 0, 1.6), Vector3(1, 0, 0), 2.6)

	# --- tables, chairs and the mess left on them
	var spots := [Vector3(-4.6, 0, -3.4), Vector3(4.4, 0, -1.6), Vector3(-4.2, 0, 4.0),
			Vector3(4.8, 0, 5.4), Vector3(-1.0, 0, 8.6), Vector3(3.0, 0, -6.4)]
	for i in spots.size():
		var p: Vector3 = spots[i]
		var yaw := r.randf_range(-18, 18)
		Kit.table(mb, p, yaw, 700 + i)
		var chairs := r.randi_range(2, 4)
		for k in chairs:
			var a := TAU * float(k) / float(chairs) + deg_to_rad(yaw)
			var cp := p + Vector3(cos(a) * 1.02, 0, sin(a) * 1.02)
			Kit.chair(mb, cp, rad_to_deg(a) + 180.0 + r.randf_range(-14, 14),
					r.randf() < 0.14)

	# --- rugs
	Kit.rug(mb, Vector3(-3.4, 0, 1.2), Vector2(4.6, 3.4), Color("5a2f28"), 6.0)
	Kit.rug(mb, Vector3(4.0, 0, 3.6), Vector2(3.6, 2.8), Color("33465a"), -9.0)
	Kit.rug(mb, Vector3(0, 0, -5.4), Vector2(5.2, 2.2), Color("4a4432"), 2.0)

	# --- paintings, shelving and services
	for spec in [
		[Vector3(-ROOM_W * 0.5 + 0.22, 2.9, -6.4), Vector3(1, 0, 0)],
		[Vector3(-ROOM_W * 0.5 + 0.22, 2.7, 6.6), Vector3(1, 0, 0)],
		[Vector3(ROOM_W * 0.5 - 0.22, 2.8, -11.0), Vector3(-1, 0, 0)],
	]:
		Kit.painting(mb, b, spec[0], spec[1], 0.9, 1.3, int(spec[0].z) + 77)
	Kit.shelf_unit(mb, b, Vector3(ROOM_W * 0.5 - 0.5, 0, 10.4), Vector3(-1, 0, 0), 3.2, 2.3, 680)
	Kit.shelf_unit(mb, b, Vector3(-ROOM_W * 0.5 + 0.5, 0, -10.6), Vector3(1, 0, 0), 2.6, 2.1, 681)
	Kit.pipe_run(mb, Vector3(-ROOM_W * 0.5 + 0.4, 0, -12.6), Vector3(-ROOM_W * 0.5 + 0.4, 0, 13.4),
			3.9, 3, 0.11, 690)
	for side in [-1.0, 1.0]:
		Kit.pipe_run(mb, Vector3(float(side) * 3.2, 0, -12.8), Vector3(float(side) * 3.2, 0, 13.2),
				4.15, 2, 0.09, 692 + int(side))

	# --- crates, barrels and sacks stacked by the door
	Kit.crate(mb, Vector3(6.3, 0, 8.9), Vector3(1.05, 1.0, 1.05), 14.0)
	Kit.crate(mb, Vector3(6.3, 1.0, 8.9), Vector3(0.9, 0.85, 0.9), -8.0, true)
	Kit.crate(mb, Vector3(5.4, 0, 9.6), Vector3(1.1, 1.0, 1.1), 42.0, true)
	Kit.barrel(mb, Vector3(-6.4, 0, 10.2), 0.0, Color("44523a"))
	Kit.barrel(mb, Vector3(-5.5, 0, 11.2), 0.0, Color("5a3a2a"))
	Kit.barrel(mb, Vector3(-6.9, 0, 11.4), 0.0, Color("3a4a5a"))
	for i in 4:
		mb.box_at(Vector3(-7.0 + float(i) * 0.55, 0.28, 7.4), Vector3(0.5, 0.56, 0.4),
				Kit.m("canvas", Color("6b6350"), 0.8), Vector3(0, float(i) * 11.0 - 12.0, 0))

	# --- cellar stair, a hole in the floor with a rail around it
	var cellar := Vector3(-4.4, 0, -11.6)
	for i in 7:
		mb.box_at(cellar + Vector3(0, -0.14 - float(i) * 0.19, -float(i) * 0.34),
				Vector3(3.0, 0.18, 0.34), MatLib.wood())
	for i in 4:
		mb.box_at(cellar + Vector3(1.6, 0.5, -1.4 + float(i) * 0.95), Vector3(0.09, 1.0, 0.09),
				MatLib.wood_dark())
		mb.box_at(cellar + Vector3(1.6, 0.98, -1.4 + float(i) * 0.95), Vector3(0.06, 0.06, 0.95),
				MatLib.wood_dark())

	# --- the ledger, revealed once the keeper agrees to hand it over
	_ledger = Interactable.new()
	_ledger.label = "Take the ledger"
	_ledger.position = Vector3(1.6, 1.34, BAR_Z + 0.2)
	_ledger.visible = false
	_ledger.enabled = false
	_ledger.collision_layer = 0
	_props.add_child(_ledger)
	Build.box(_ledger, Vector3(0.36, 0.08, 0.28), Vector3.ZERO,
			MatLib.fabric(Color("4a3a24")), Vector3.ZERO, false)
	Build.box(_ledger, Vector3(0.32, 0.045, 0.24), Vector3(0, 0.055, 0),
			MatLib.flat(Color("d8cba8"), "pages"), Vector3.ZERO, false)
	Build.box(_ledger, Vector3(0.38, 0.02, 0.07), Vector3(0, -0.02, 0.11),
			MatLib.flat(Color("a83a2a"), "ribbon"), Vector3.ZERO, false)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.5, 0.5)
	cs.shape = box
	_ledger.add_child(cs)
	_ledger.interacted.connect(_on_ledger)

	_commit(mb, "Furniture")


# ------------------------------------------------------------------- people

func _keeper() -> void:
	keeper = Talker.new()
	keeper.setup(Vector3(0.4, 0, BAR_Z - 1.3), 0.0)
	keeper.caption = "THE KEEPER"
	keeper.build_body({
		"primary": MatLib.painted(Color("5c4d3d"), "keeper_coat"),
		"secondary": MatLib.painted(Color("302820"), "keeper_under"),
		"accent": MatLib.painted(Color("8a5c2c"), "keeper_apron"),
		"skin": MatLib.painted(Color("9a7a58"), "keeper_skin"),
		"bulk": 1.05,
	})
	# a lantern on the bar beside them, and a rag over one shoulder
	Build.omni(keeper, Vector3(0.75, 1.30, 0.35), Color("ffce8a"), 2.6, 6.5, true, 1.2)
	_props.add_child(keeper)
	keeper.option_chosen.connect(_on_keeper_option)


func _patrons() -> void:
	var specs := [
		[Vector3(-4.6, 0, -2.0), 12.0, Color("3f4a52"), Color("2a3036")],
		[Vector3(4.9, 0, 5.0), 196.0, Color("4a3f33"), Color("262019")],
		[Vector3(-1.0, 0, 9.4), 170.0, Color("463a46"), Color("28222a")],
	]
	for i in specs.size():
		var s: Array = specs[i]
		var p := Talker.new()
		p.setup(s[0], float(s[1]))
		p.caption = ["A FISHER", "A CARTER", "A WIDOW"][i]
		p.label = "Talk"
		p.build_body({
			"primary": MatLib.painted(s[2], "patron_a_%d" % i),
			"secondary": MatLib.painted(s[3], "patron_b_%d" % i),
			"accent": MatLib.painted(Color("7a5a2b"), "patron_c_%d" % i),
			"skin": MatLib.painted(Color("8a6a4a"), "patron_skin_%d" % i),
			"bulk": 0.97 + 0.06 * float(i),
		})
		if i != 2:
			p.options = [
				{"id": "talk", "label": "Talk", "hint": "ask about the market"},
				{"id": "inspect", "label": "Inspect", "hint": "look them over"},
				{"id": "leave", "label": "Leave", "hint": "step away"},
			]
			p.option_chosen.connect(_on_patron_option.bind(i))
		_props.add_child(p)


func _on_patron_option(id: String, index: int) -> void:
	match id:
		"talk":
			var lines: Array = [
				[
					{"speaker": "A Fisher", "text": "Market's west of here. They've got the bridge, and the bridge is the only dry way in."},
					{"speaker": "You", "text": "Who is 'they'?"},
					{"speaker": "A Fisher", "text": "Ask the ones with the rifles. I stopped asking."},
				],
				[
					{"speaker": "A Carter", "text": "Six of them on the square when I came through. Two on the roof of the grain house."},
					{"speaker": "A Carter", "text": "If you're going, go low and go quiet. The square carries sound."},
				],
			][index % 2]
			await _notify_lines(lines)
		"inspect":
			await _notify_lines([
				{"speaker": "You", "text": "Hands like a rope-maker. Boots that have never been dry."},
				{"speaker": "Them", "text": "What?"},
				{"speaker": "You", "text": "Nothing."},
			])
		_:
			pass


func _on_keeper_option(id: String) -> void:
	match id:
		"talk":
			_talk()
		"inspect":
			_notify_lines([
				{"speaker": "You", "text": "Apron is newer than the coat. Rope burns on both palms."},
				{"speaker": "The Keeper", "text": "You going to stand there reading me all night?"},
			])
		"wait":
			_notify_lines([
				{"speaker": "You", "text": "You wait. The rain keeps time on the roof."},
				{"speaker": "The Keeper", "text": "It'll do that until the roof gives. Sit, if you're staying."},
			])
		_:
			pass


func _talk() -> void:
	if done("speak"):
		_notify_lines([
			{"speaker": "The Keeper", "text": "Ledger's on the bar. Take it before I change my mind."},
		])
		return
	await _notify_lines([
		{"speaker": "The Keeper", "text": "You came up the flooded street. Nobody comes up the flooded street."},
		{"speaker": "You", "text": "I am looking for the archive."},
		{"speaker": "The Keeper", "text": "Then you are looking for the dark. The market holds the way in -- and they hold the market."},
		{"speaker": "You", "text": "How many?"},
		{"speaker": "The Keeper", "text": "More than you. Less than you think, if you use your head."},
		{"speaker": "The Keeper", "text": "Take the ledger. It's the only honest map left on this side of the water."},
	])
	complete("speak")
	objective("ledger", "Take the ledger")
	_ledger.visible = true
	_ledger.enabled = true
	_ledger.collision_layer = 8


func _notify_lines(lines: Array) -> void:
	if game != null:
		await game.call("play_dialogue", lines)


func _on_ledger(_player: Node) -> void:
	if _ledger_taken:
		return
	_ledger_taken = true
	complete("ledger")
	_ledger.enabled = false
	GameManager.toast_message("LEDGER ACQUIRED")
	AudioDirector.play("objective", -4.0, 1.0, 0.0, "UI")
	await get_tree().create_timer(1.4).timeout
	if done("monument"):
		return
	_notify_lines([
		{"speaker": "The Keeper", "text": "Now look at what they keep in the corner. " +
				"Their whole faith in one pale stone. Shoot it."},
	])


# ------------------------------------------------------------------- shrine

## The occupiers keep a small stone replica of their monument at the back of
## the room, under a warm lamp -- and two of them to watch it.  Bringing it
## down is how this level ends.
func _shrine() -> void:
	var body := place_monument(Vector3(3.4, 0, -12.2), 0.0, 0.10, 240.0)
	monument_on_down(body, _on_monument_down)
	_shrine_guards = [
		spawn_enemy(Vector3(1.2, 0, -11.0), "guard",
				line_patrol(Vector3(1.2, 0, -11.0), Vector3(5.8, 0, -11.0), 2)),
		spawn_enemy(Vector3(5.8, 0, -8.6), "trooper",
				line_patrol(Vector3(5.8, 0, -8.6), Vector3(2.0, 0, -8.6), 2)),
	]
	body.damaged.connect(func(_amount: float, point: Vector3) -> void:
		for g in _shrine_guards:
			if is_instance_valid(g) and g.alive:
				g.receive_alert(point))
	# a warm lamp so the pale stone reads against the dark back wall
	Build.omni(props(), Vector3(3.4, 2.6, -12.2), Color("ffd9a8"), 6.0, 8.0, true, 1.2)


func _on_monument_down() -> void:
	complete("monument")
	notify("THE SHRINE IS DOWN")
	await get_tree().create_timer(2.6).timeout
	finish()


# -------------------------------------------------------------------- light

func _lights() -> void:
	var mb := MeshBuilder.new()
	# pendant lamps down the middle of the room
	for i in 4:
		var z := -7.0 + float(i) * 5.4
		var top := Vector3(0, 0, z) + Vector3(0, ROOM_H - 1.35, 0)
		var bulb := Kit.hanging_lamp(mb, top, Color("ffc074"), Color("2e4a40"))
		var l := Build.omni(props(), bulb, Color("ffbb77"), 9.0, 14.0, true, 1.1)
		_lamp_nodes.append(l)
		var flick := l.create_tween()
		flick.set_loops()
		flick.tween_property(l, "light_energy", 3.7, randf_range(0.5, 1.1))
		flick.tween_property(l, "light_energy", 5.0, randf_range(0.6, 1.4))
	# caged lamps on the long walls
	for spec in [[Vector3(-ROOM_W * 0.5 + 0.4, 3.1, -6.0), Vector3(1, 0, 0)],
			[Vector3(-ROOM_W * 0.5 + 0.4, 3.1, 6.2), Vector3(1, 0, 0)],
			[Vector3(ROOM_W * 0.5 - 0.4, 3.1, -11.4), Vector3(-1, 0, 0)],
			[Vector3(ROOM_W * 0.5 - 0.4, 3.1, 8.0), Vector3(-1, 0, 0)]]:
		var at := Kit.caged_lamp(mb, Basis.IDENTITY, spec[0], spec[1])
		Build.omni(props(), at, Color("ffd0a0"), 1.8, 6.0, true, 0.6)
	_commit(mb, "Fixtures")

	# hearth fire
	Build.omni(props(), Vector3(-ROOM_W * 0.5 + 1.7, 0.95, 1.6), Color("ff7a2a"), 5.0,
			13.0, true, 1.6)
	FX.fire_glow(props(), 30)

	# cold moonlight raking in through the windows, for contrast
	for side in [-1.0, 1.0]:
		for z in [-8.0, -1.5, 5.5]:
			var x := float(side) * (ROOM_W * 0.5 - 1.4)
			Build.spot(props(), Vector3(x, 2.4, z), Vector3(6, float(side) * 90.0, 0),
					Color("7fa8d8"), 5.5, 13.0, 46.0, true, 1.4)


func _weather_outside() -> void:
	# a rain volume out beyond each window so the glass always has something
	# moving behind it
	for side in [-1.0, 1.0]:
		var s := float(side)
		for z in [-8.0, -1.5, 5.5]:
			var f := FX.rain(self, 260)
			f.position = Vector3(s * (ROOM_W * 0.5 + 2.0), 3.0, z)
			f.scale = Vector3(1.4, 1.4, 4.0)


func _triggers() -> void:
	var door := TriggerZone.make(self, Vector3(0, 1.2, 10.0), Vector3(6.0, 5, 3), "door")
	door.entered.connect(func(_p):
		if game != null:
			game.call("notify", "The one warm room left on this side of the water."))


func surface_at(_pos: Vector3) -> String:
	return "wood"


func review_vantages() -> Array:
	return [
		{"name": "entry", "pos": Vector3(0, 0.5, 12.4), "yaw": 0.0, "pitch": -0.04},
		{"name": "room", "pos": Vector3(0.5, 0.5, 4.0), "yaw": 0.0, "pitch": -0.02},
		{"name": "bar", "pos": Vector3(0.4, 0.5, -4.6), "yaw": 0.0, "pitch": 0.02},
		{"name": "hearth", "pos": Vector3(0.0, 0.5, 3.2), "yaw": 1.35, "pitch": 0.0},
		{"name": "bar_left", "pos": Vector3(-4.2, 0.5, -4.0), "yaw": -0.35, "pitch": 0.06},
		{"name": "tables", "pos": Vector3(-5.6, 0.5, 7.6), "yaw": 2.4, "pitch": -0.05},
		{"name": "keeper", "pos": Vector3(0.4, 0.5, -4.0), "yaw": 0.0, "pitch": 0.04},
		{"name": "back", "pos": Vector3(0.0, 0.5, -11.0), "yaw": 3.14, "pitch": 0.02},
	]


func _process(delta: float) -> void:
	super._process(delta)
	_t += delta
	for i in _lamp_nodes.size():
		var l: OmniLight3D = _lamp_nodes[i]
		l.light_energy += sin(_t * 6.0 + float(i) * 2.1) * delta * 0.35
