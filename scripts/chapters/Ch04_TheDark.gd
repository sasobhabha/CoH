extends Chapter
## CHAPTER IV -- THE DARK
##
## Stealth.  The archive is unlit, the guards carry lamps, and the lockers are
## the only guaranteed way past them.  Fighting is possible but expensive: the
## chapter starts you with less than a full belt.

const HALL_W := 30.0
const HALL_L := 96.0
const HALL_H := 6.0

var _terminal: Interactable
var _guards: Array = []
var _lockers: Array = []
var _strobe: OmniLight3D
var _t := 0.0
var _garrison: Array = []


func describe() -> void:
	_spawn = Vector3(0, 0.3, 42)
	_spawn_yaw = 0.0
	GameManager.set_objectives([
		{"id": "unseen", "text": "Get inside without being seen"},
		{"id": "archive", "text": "Reach the archive terminal"},
		{"id": "monument", "text": "Shoot the monument"},
	])


func build() -> void:
	_shell()
	_rooms()
	_clutter()
	_guards_spawn()
	_shrine()
	_lights()
	# the dark chapter opens with a short belt: press F when you need the light
	if game != null and game.player != null:
		var p = game.player
		p.reserve = mini(p.reserve, 45)
		p.set_flashlight(false)
	set_process(true)


# -------------------------------------------------------------------- shell

func _shell() -> void:
	var concrete := MatLib.concrete_dark()
	ground(Vector2(HALL_W + 24, HALL_L + 24), 0.0, MatLib.concrete_wet(), 1.4)

	# outer walls
	Build.box(structures(), Vector3(HALL_W + 24, HALL_H + 1, 1.2),
			Vector3(0, (HALL_H + 1) * 0.5, -HALL_L * 0.5 - 6.0), concrete)
	Build.box(structures(), Vector3(HALL_W + 24, HALL_H + 1, 1.2),
			Vector3(0, (HALL_H + 1) * 0.5, HALL_L * 0.5 + 6.0), concrete)
	Build.box(structures(), Vector3(1.2, HALL_H + 1, HALL_L + 24),
			Vector3(-HALL_W * 0.5 - 6.0, (HALL_H + 1) * 0.5, 0), concrete)
	Build.box(structures(), Vector3(1.2, HALL_H + 1, HALL_L + 24),
			Vector3(HALL_W * 0.5 + 6.0, (HALL_H + 1) * 0.5, 0), concrete)

	# roof
	Build.box(structures(), Vector3(HALL_W + 26, 0.8, HALL_L + 26), Vector3(0, HALL_H + 0.4, 0),
			concrete, Vector3.ZERO, false)

	# interior columns down the hall
	for i in 9:
		var z := 34.0 - float(i) * 10.0
		for side in [-1.0, 1.0]:
			Build.box(structures(), Vector3(1.4, HALL_H, 1.4),
					Vector3(side * 9.0, HALL_H * 0.5, z), MatLib.concrete(), Vector3.ZERO, true)


func _rooms() -> void:
	# partition walls creating three chambers along the hall
	var walls := [
		[Vector3(-11.0, 0, 12.0), 10.0, 0.0],
		[Vector3(11.0, 0, 0.0), 10.0, 0.0],
		[Vector3(-11.0, 0, -16.0), 10.0, 0.0],
		[Vector3(11.0, 0, -30.0), 10.0, 0.0],
	]
	for w in walls:
		var pos: Vector3 = w[0]
		var w2: float = w[1]
		Build.box(structures(), Vector3(w2, HALL_H, 0.8), pos + Vector3(0, HALL_H * 0.5, 0),
				MatLib.brick(), Vector3.ZERO, true)

	# shelving units -- sightline blockers and cover
	for i in 22:
		var z := 36.0 - float(i) * 4.2
		var x := -12.0 if i % 2 == 0 else 12.0
		Build.box(props(), Vector3(2.4, 3.2, 1.0), Vector3(x, 1.6, z), MatLib.metal_rust(),
				Vector3(0, 90.0 if i % 4 == 0 else 0, 0), true)
		for shelf in 3:
			Build.box(props(), Vector3(2.2, 0.1, 0.9),
					Vector3(x, 0.9 + float(shelf) * 0.95, z), MatLib.wood_dark(), Vector3.ZERO, false)


func _clutter() -> void:
	# crates and a fallen shelf for movement options
	Build.rubble_field(props(), Vector3(0, 0, 6), Vector3(12, 0, 30), 90, 31)
	for i in 8:
		var z := 30.0 - float(i) * 9.0
		var x := -6.0 + fmod(float(i * 5), 12.0)
		Build.box(props(), Vector3(1.2, 1.2, 1.2), Vector3(x, 0.6, z), MatLib.wood_dark(),
				Vector3(0, float(i) * 17.0, 0), true)

	# lockers: the reliable path through
	_lockers.append(add_locker(Vector3(-8.5, 0, 20.0), 90.0))
	_lockers.append(add_locker(Vector3(8.5, 0, 4.0), -90.0))
	_lockers.append(add_locker(Vector3(-8.5, 0, -12.0), 90.0))
	_lockers.append(add_locker(Vector3(8.5, 0, -26.0), -90.0))
	_lockers.append(add_locker(Vector3(-8.5, 0, -38.0), 90.0))

	add_pickup(Vector3(0, 0, 20), "ammo", 60)
	add_pickup(Vector3(-6, 0, -20), "health", 40)

	# the archive terminal at the far end
	_terminal = Interactable.new()
	_terminal.label = "Read the archive"
	_terminal.position = Vector3(0, 0, -44.0)
	_props.add_child(_terminal)
	Build.box(_terminal, Vector3(3.0, 1.0, 1.6), Vector3(0, 0.5, 0), MatLib.metal_dark(), Vector3.ZERO, false)
	Build.box(_terminal, Vector3(2.6, 1.5, 0.18), Vector3(0, 1.75, 0.5), MatLib.metal_dark(),
			Vector3(-12, 0, 0), false)
	Build.box(_terminal, Vector3(2.3, 1.2, 0.06), Vector3(0, 1.75, 0.40),
			MatLib.emissive(Color("7fd4ff"), 2.2), Vector3(-12, 0, 0), false)
	Build.omni(_terminal, Vector3(0, 1.8, 0.4), Color("7fd4ff"), 3.4, 9.0, false, 1.8)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.2, 2.6, 2.0)
	cs.shape = box
	cs.position = Vector3(0, 1.2, 0)
	_terminal.add_child(cs)
	_terminal.interacted.connect(_on_terminal)


func _guards_spawn() -> void:
	_guards = [
		spawn_enemy(Vector3(0, 0, 22), "guard", line_patrol(Vector3(-8, 0, 22), Vector3(8, 0, 22), 3), true),
		spawn_enemy(Vector3(0, 0, 6), "guard", line_patrol(Vector3(-10, 0, 6), Vector3(10, 0, 6), 4), true),
		spawn_enemy(Vector3(0, 0, -10), "guard", ring_patrol(Vector3(0, 0, -10), 9.0, 4), true),
		spawn_enemy(Vector3(6, 0, -26), "guard", line_patrol(Vector3(6, 0, -26), Vector3(-6, 0, -32), 2), true),
		spawn_enemy(Vector3(0, 0, -38), "heavy", line_patrol(Vector3(-8, 0, -38), Vector3(8, 0, -38), 3), true),
	]
	for g in _guards:
		g.died.connect(_on_guard_died)
		g.hear_range = 20.0
		g.view_range = 22.0
		g.reaction_time = 0.55

	# the first guard never ambushes the player at the door
	if game != null and game.player != null:
		_guards[0].receive_alert(Vector3(0, 0, 30))


func _lights() -> void:
	# almost nothing: one failing strip lamp so the room reads as a space
	_strobe = Build.omni(props(), Vector3(0, 4.6, -8.0), Color("8fb8d8"), 0.9, 12.0, true, 1.2)
	Build.box(props(), Vector3(2.4, 0.12, 0.3), Vector3(0, 4.9, -8.0),
			MatLib.emissive(Color("8fb8d8"), 0.6), Vector3.ZERO, false)
	# emergency exit glow over the terminal
	Build.spot(props(), Vector3(0, 5.2, -42.0), Vector3(-80, 0, 0), Color("7fd4ff"), 4.0, 16.0, 30.0,
			true, 3.0)


func _on_guard_died(_e: Node) -> void:
	if enemies_alive() == 0 and not done("unseen"):
		complete("unseen")


func _on_terminal(_player: Node) -> void:
	if done("archive"):
		return
	complete("archive")
	GameManager.toast_message("ARCHIVE READ")
	if game != null:
		await game.call("play_dialogue", [
			{"speaker": "Archive", "text": "RECORD 0041 -- " +
					"the water came in the spring and did not leave."},
			{"speaker": "Archive", "text": "RECORD 0042 -- the monolith was poured the " +
					"same year. Nobody will say by whom."},
			{"speaker": "Archive", "text": "RECORD 0043 -- go up. There is a door in the north " +
					"wall that opens onto grass."},
		])
	await get_tree().create_timer(0.6).timeout
	if done("monument"):
		return
	notify("Leave them something to remember. Shoot the monument.")
	_monument_garrison(true)


# ---------------------------------------------------------------- monument

## A shrine to the monolith stands in the archive chamber, ringed by lamplight
## and lamplight-carrying guards.  After the archive is read, the garrison
## doubles down around it.
func _shrine() -> void:
	var body := place_monument(Vector3(-7.0, 0, -43.0), 90.0, 0.09, 240.0)
	monument_on_down(body, _on_monument_down)
	_garrison = [
		spawn_enemy(Vector3(-4.0, 0, -40.0), "guard",
				ring_patrol(Vector3(-8.0, 0, -44.0), 5.0, 4), true),
		spawn_enemy(Vector3(-12.0, 0, -48.0), "guard",
				ring_patrol(Vector3(-8.0, 0, -44.0), 5.0, 4, PI), true),
	]
	for g in _garrison:
		g.died.connect(_on_guard_died)
		g.hear_range = 20.0
		g.view_range = 22.0
		g.reaction_time = 0.55
	body.damaged.connect(func(_amount: float, point: Vector3) -> void:
		for g in _garrison:
			if is_instance_valid(g) and g.alive:
				g.receive_alert(point))
	# one warm lamp on the pale stone, the only warmth in the room
	Build.omni(props(), Vector3(-8.0, 2.6, -44.0), Color("ffd9a8"), 5.0, 7.0, true, 1.4)


func _monument_garrison(reinforce: bool) -> void:
	if not reinforce:
		return
	for spec in [[Vector3(-2.0, 0, -46.0), "guard"],
			[Vector3(-14.0, 0, -40.0), "guard"],
			[Vector3(-8.0, 0, -38.0), "heavy"]]:
		var e := spawn_enemy(spec[0], spec[1], [])
		_garrison.append(e)
		e.receive_alert(Vector3(-8.0, 0, -44.0))
	notify("THE GARRISON CLOSES ON THE MONUMENT")


func _on_monument_down() -> void:
	complete("monument")
	notify("THE MONUMENT IS DOWN")
	for e in _garrison:
		if is_instance_valid(e) and e.alive:
			e.queue_free()
	_garrison.clear()
	await get_tree().create_timer(2.6).timeout
	finish()


func surface_at(_pos: Vector3) -> String:
	return "metal"


func _process(delta: float) -> void:
	super._process(delta)
	_t += delta
	if _strobe != null:
		# intermittent failure on the strip light
		var s := sin(_t * 1.7) * sin(_t * 11.3)
		_strobe.light_energy = 0.9 if s > -0.7 else 0.05


func on_start() -> void:
	GameManager.toast_message("PRESS F FOR THE LAMP")
