class_name Chapter
extends Node3D
## Base class for a campaign chapter.
##
## A chapter owns one place: it builds the geometry, spawns hostiles, pushes
## objectives into GameManager and emits `finished` when the last objective is
## done.  `game` is intentionally untyped -- the chapter talks to the campaign
## through `call()` so the two classes never need to know each other.

signal finished

var game: Node = null
var index := 0
var info := {}
var _spawn := Vector3.ZERO
var _spawn_yaw := 0.0
var _props: Node3D
var _structures: Node3D

## Surface height of any flood water this chapter renders.  The player's
## buoyancy is driven from this: 0.0 on dry ground, or the waterline (in
## metres, world Y) where the chapter is flooded.  Subclasses set it before
## or during build(); GameScene hands it to the player every frame.
var water_level := -1000.0


func setup(campaign: Node, chapter_index: int) -> void:
	game = campaign
	index = chapter_index
	info = GameManager.chapter_info(index)
	_props = Node3D.new()
	_props.name = "Props"
	add_child(_props)
	_structures = Node3D.new()
	_structures.name = "Structures"
	add_child(_structures)
	describe()
	build()


## Subclasses set spawn point, music and ambience here.
func describe() -> void:
	pass


## Subclasses build their world here.
func build() -> void:
	pass


## Called once the chapter heading has played and control is handed over.
func on_start() -> void:
	pass


func spawn_position() -> Vector3:
	return _spawn


func spawn_yaw() -> float:
	return _spawn_yaw


func surface_at(pos: Vector3) -> String:
	## Gameplay surface underfoot: deep flood water changes footfall sound,
	## splash noise and shot impacts.  Default asks the water level.
	if pos.y < water_level - 0.45:
		return "water"
	return "concrete"


# ------------------------------------------------------------------ campaign

func objective(id: String, text: String) -> void:
	GameManager.push_objective(id, text)


func complete(id: String) -> void:
	GameManager.complete_objective(id)


func done(id: String) -> bool:
	return GameManager.is_done(id)


func notify(text: String) -> void:
	GameManager.toast_message(text)


func spawn_enemy(pos: Vector3, kind := "trooper", patrol := [], light := false) -> Node:
	return game.call("spawn_enemy", pos, kind, patrol, light)


func enemies_alive() -> int:
	return int(game.call("enemies_alive"))


func finish() -> void:
	finished.emit()


func shake(amount: float) -> void:
	if game != null and game.player != null:
		game.player.cam_rig.add_trauma(amount)


# ------------------------------------------------------- the monument finale

## Every chapter ends the same way now: there is a monument somewhere in it,
## guarded, and shooting it enough times brings it down and ends the level.
## The guarding escalates chapter by chapter; only the placement does not.

var _monument_node: Node3D
var _monument_pos := Vector3.ZERO
var _monument_scale := 1.0
var _monument_hammer := 0.0     ## damage soaked by the monument so far
var _monument_health0 := 600.0
var _monument_body: DamageableBody
var _monument_reject_cooldown := 0.0   ## toast throttle for blocked shots

## Shots cannot harm the monument while hostiles are still up.  The finale
## only fires once the ground is clear.
const MONUMENT_LOCK_TOAST := "The monument will not fall while they still stand."
const MONUMENT_REJECT_TOAST_GAP := 4.0
var _monument_stage1 := false
var _monument_stage2 := false
var _monument_down := false


## Place the monument GLB with a shootable hitbox wrapped around it.  The
## hitbox is sized from the piece's measured bounds unless `hit_size` is given
## (Chapter I passes its hand-tuned 26 m cube).  `scale` scales the piece.
func place_monument(pos: Vector3, yaw := 0.0, scale := 1.0, health := 600.0,
		hit_size := Vector3.ZERO) -> DamageableBody:
	var node := EnvKit.place(structures(), "monument", pos, yaw, {"scale": scale})
	if node != null:
		node.name = "Monument"
	var b := EnvKit.bounds("monument")
	var size := hit_size
	if size == Vector3.ZERO:
		size = Vector3(b.size.x * scale + 0.6, b.size.y * scale + 0.4,
				b.size.z * scale + 0.6)
		if size.length() < 1.0:
			size = Vector3(4.0, 4.0, 4.0)
	var body := DamageableBody.new()
	body.name = "MonumentHitbox"
	body.make_box(size, Vector3(0, size.y * 0.5, 0))
	body.health = health
	body.debris_impact = "concrete"
	body.position = pos
	body.rotation.y = deg_to_rad(yaw)
	structures().add_child(body)
	_monument_node = node
	_monument_pos = pos
	_monument_scale = scale
	_monument_body = body
	# the monument is armoured against gunfire while guards are alive
	body.damage_blocked_reason = _monument_guarded
	return body


## Wire the shared hit feedback and destruction.  `on_down` runs exactly once,
## after the blast -- complete the objective, finish the chapter, whatever the
## chapter wants the fall of the monument to mean.
func monument_on_down(body: DamageableBody, on_down: Callable) -> void:
	_monument_health0 = body.health
	body.damaged.connect(_on_monument_hit)
	body.blocked.connect(_on_monument_blocked)
	body.destroyed.connect(_on_monument_destroyed.bind(on_down))


## The damage gate itself: true while any hostile is up.
func _monument_guarded() -> String:
	if enemies_alive() > 0:
		return "hostiles"
	return ""


## Feedback for shots the monument shrugs off: metal ping, no chips, no crack,
## no damage.  Toasted on a cooldown so sustained fire does not spam it.
func _on_monument_blocked(point: Vector3) -> void:
	AudioDirector.play_variant_at("impact_metal", 2, point, -6.0, 60.0)
	if _monument_reject_cooldown <= 0.0:
		_monument_reject_cooldown = MONUMENT_REJECT_TOAST_GAP
		notify(MONUMENT_LOCK_TOAST)


## Toast reminder if the player camps the monument with hostiles still up.
func _process(delta: float) -> void:
	if _monument_reject_cooldown > 0.0:
		_monument_reject_cooldown -= delta
		return
	if _monument_body == null or _monument_down or game == null:
		return
	var p: Node3D = game.get("player")
	if p == null:
		return
	if enemies_alive() > 0 \
			and _monument_pos.distance_to(p.global_position) < 24.0:
		_monument_reject_cooldown = 12.0
		notify(MONUMENT_LOCK_TOAST)


func _on_monument_hit(amount: float, point: Vector3) -> void:
	# Feedback first: rock chips, a thud, a bit of camera shake.
	AudioDirector.play_variant_at("impact_concrete", 3, point, -4.0, 90.0)
	AudioDirector.play_at("explosion", point, -22.0, 1.65, 0.15, 70.0)
	shake(0.05)
	_monument_hammer += amount
	var frac := _monument_hammer / maxf(_monument_health0, 1.0)
	# escalating damage: the stone starts to answer the gunfire.
	if not _monument_stage1 and frac >= 0.3:
		_monument_stage1 = true
		notify("The stone is cracking.")
		AudioDirector.play_at("explosion", _monument_pos + Vector3(0, 4, 0),
				-14.0, 1.3, 0.1, 120.0)
		shake(0.35)
	if not _monument_stage2 and frac >= 0.62:
		_monument_stage2 = true
		notify("It is starting to come apart.")
		AudioDirector.play_at("explosion", _monument_pos + Vector3(0, 5, 0),
				-10.0, 1.1, 0.1, 140.0)
		shake(0.55)


func _on_monument_destroyed(on_down: Callable) -> void:
	if _monument_down:
		return
	if enemies_alive() > 0:
		# can only happen if a straggler walks into the last shot; hold the
		# finale and let the damage gate re-arm
		_monument_hammer = _monument_health0 * 0.99
		_monument_down = false
		notify(MONUMENT_LOCK_TOAST)
		return
	_monument_down = true
	_monument_blast()
	on_down.call()


## The monument's last seconds: screen flash, fireball, shockwave, collapse
## and a rubble mound.  Sized from the placed scale, so the same sequence
## reads on a 1.7 m shrine and a 26 m monolith.
func _monument_blast() -> void:
	var k := maxf(_monument_scale, 0.12)
	# Fade the hero piece away under a screen flash so the moment the mesh
	# goes, it reads as a collapse instead of a pop.
	_monument_fade(0.55)
	if game != null:
		game.call("flash", 0.9, Color(1.0, 0.9, 0.75))
	AudioDirector.play("explosion", 2.0)
	shake(1.2 * clampf(k * 1.6, 0.5, 1.0))

	var fx := Node3D.new()
	fx.name = "MonumentBlast"
	fx.position = _monument_pos
	structures().add_child(fx)
	FX.fire_glow(fx, maxi(50, roundi(120.0 * k)))
	FX.smoke_plume(fx, maxi(24, roundi(60.0 * k)), 9.0 * clampf(k, 0.4, 1.0))
	FX.embers(fx, maxi(80, roundi(260.0 * k)), Color(1.0, 0.6, 0.2, 0.8))
	FX.dust(fx, maxi(120, roundi(320.0 * k)),
			Vector3(30, 9, 30) * clampf(k * 1.6, 0.5, 1.0), 0.5,
			Color(0.8, 0.76, 0.68, 0.5))
	Build.omni(fx, Vector3(0, 4.0 * k, 0), Color(1.0, 0.7, 0.35),
			9.0 * clampf(k * 1.5, 0.5, 1.0), maxf(26.0, 90.0 * k), false, 2.4)
	Build.quad(fx, Vector2(90, 90) * clampf(k * 1.4, 0.4, 1.0),
			Vector3(0, 0.12, 0), Kit.flat(Color(1.0, 0.85, 0.6, 0.5), 0.5))
	var ring := Build.quad(fx, Vector2(14, 14) * maxf(k, 0.5), Vector3(0, 0.3, 0),
			Kit.flat(Color(1.0, 0.95, 0.8, 0.85), 0.8))
	ring.rotation.x = -PI / 2
	var rt: Tween = create_tween()
	rt.tween_property(ring, "scale", Vector3.ONE * 7.0 * maxf(k, 0.5), 0.6) \
			.set_ease(Tween.EASE_OUT)
	var rt2: Tween = create_tween()
	rt2.parallel().tween_property(ring, "transparency", 1.0, 0.6)

	# the fall: masonry box pieces burst outwards and pile as a rubble mound
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	var pieces := Node3D.new()
	pieces.name = "MonumentDebris"
	fx.add_child(pieces)
	var masonry := MatLib.concrete()
	var spread := clampf(k * 1.4, 0.45, 1.0)
	var count := maxi(10, roundi(26.0 * k))
	for i in count:
		var a := TAU * float(i) / float(count) + r.randf_range(-0.15, 0.15)
		var dist := r.randf_range(4.0, 15.0) * spread
		var h := r.randf_range(0.3, 2.6) * spread
		Build.box(pieces,
				Vector3(r.randf_range(0.8, 2.8) * spread, h, r.randf_range(0.8, 2.8) * spread),
				Vector3(cos(a) * dist, h * 0.5, sin(a) * dist),
				masonry, Vector3(0, rad_to_deg(a), r.randf_range(-8, 8)), true)
	Build.rubble_field(pieces, Vector3(0, 0.4 * spread, 0),
			Vector3(11, 1.6, 11) * spread, maxi(60, roundi(120.0 * k)), 909)

	# fires burn in the wreckage for as long as anyone looks
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.7
		fire_barrel(Vector3(cos(a), 0, sin(a)) * (8.0 * maxf(k, 0.5)),
				2.2 * clampf(k * 1.2, 0.5, 1.0))

	notify("IT IS DOWN")


## Tween every mesh of the hero piece to full transparency.  The GLB is a
## stack of many MeshInstance3D surfaces, so this walks the whole subtree.
func _monument_fade(time := 0.55) -> void:
	if _monument_node == null or not is_instance_valid(_monument_node):
		return
	var stack: Array = [_monument_node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var tw: Tween = create_tween()
			tw.tween_property(n, "transparency", 1.0, time)
		stack.append_array(n.get_children())


# ------------------------------------------------------------ common scenery

func props() -> Node3D:
	return _props


func structures() -> Node3D:
	return _structures


## Ground slab with collision.  `size` is X/Z, `y` is the top surface height.
func ground(size: Vector2, y: float, mat: Material, thickness := 1.0) -> MeshInstance3D:
	return Build.box(_structures, Vector3(size.x, thickness, size.y),
			Vector3(0, y - thickness * 0.5, 0), mat, Vector3.ZERO, true)


## Ground slab with its top surface at `y`, centred on `centre_z`.
func plate(size: Vector2, y: float, centre_z: float, mat: Material,
		thickness := 1.0) -> MeshInstance3D:
	return Build.box(_structures, Vector3(size.x, thickness, size.y),
			Vector3(0, y - thickness * 0.5, centre_z), mat, Vector3.ZERO, true)


func water_surface(size: Vector2, y: float, uv := 26.0) -> void:
	water_level = y
	water_plate(size, y, 0.0, uv)


func water_plate(size: Vector2, y: float, centre_z: float, uv := 26.0,
		centre_x := 0.0) -> void:
	water_level = y
	var m := MatLib.water(MatLib.ripple_texture())
	if m is ShaderMaterial:
		(m as ShaderMaterial).set_shader_parameter("uv_scale", uv)
	Build.water(_structures, size, Vector3(centre_x, y, centre_z), m)


## A block of ruined mid-rise buildings inside a ring, with lit windows.
func ruined_quarter(centre: Vector3, radius: float, count: int, seed_v: int,
		min_h := 6.0, max_h := 26.0, lit_chance := 0.35) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var mats := [MatLib.concrete_dark(), MatLib.plaster(), MatLib.brick(), MatLib.metal_rust()]
	var colours := [Color("ffb45a"), Color("7fd4ff"), Color("ff5f7a"), Color("8ff0c0")]
	for i in count:
		var a := TAU * float(i) / float(count) + r.randf() * 0.25
		var dist := radius + r.randf_range(-radius * 0.25, radius * 0.25)
		var h := r.randf_range(min_h, max_h)
		var w := r.randf_range(5.0, 12.0)
		var d := r.randf_range(5.0, 12.0)
		var yaw := r.randf_range(-25.0, 25.0)
		var pos := centre + Vector3(cos(a) * dist, h * 0.5, sin(a) * dist)
		Build.box(_structures, Vector3(w, h, d), pos, mats[r.randi() % mats.size()], Vector3(0, yaw, 0))
		# sheared top
		Build.box(_structures, Vector3(w * r.randf_range(0.4, 0.8), r.randf_range(1.5, 6.0), d * 0.7),
				pos + Vector3(r.randf_range(-2, 2), h * 0.5 + 1.2, r.randf_range(-2, 2)),
				MatLib.concrete_dark(), Vector3(0, r.randf_range(0, 45), 0), false)
		if r.randf() < lit_chance:
			var rows := maxi(1, int(h / 3.6))
			for row in rows:
				if r.randf() < 0.55:
					continue
				var c: Color = colours[r.randi() % colours.size()]
				var off := Vector3.ZERO
				var sz := Vector3(w * 0.55, 0.45, 0.06)
				match r.randi() % 4:
					0: off = Vector3(0, 0, d * 0.5 + 0.06)
					1: off = Vector3(0, 0, -d * 0.5 - 0.06)
					2:
						off = Vector3(w * 0.5 + 0.06, 0, 0)
						sz = Vector3(0.06, 0.45, d * 0.55)
					_:
						off = Vector3(-w * 0.5 - 0.06, 0, 0)
						sz = Vector3(0.06, 0.45, d * 0.55)
				Build.box(_structures, sz, pos + off + Vector3(0, -h * 0.5 + 1.8 + row * 3.6, 0),
						MatLib.emissive(c, r.randf_range(0.7, 2.2)), Vector3(0, yaw, 0), false)


## A burning barrel with light, flame particles and smoke.
func fire_barrel(pos: Vector3, scale := 1.0) -> void:
	var holder := Node3D.new()
	holder.position = pos
	_props.add_child(holder)
	Build.cylinder(holder, 0.42 * scale, 1.05 * scale, Vector3(0, 0.52 * scale, 0), MatLib.metal_rust(),
			Vector3.ZERO, true)
	Build.omni(holder, Vector3(0, 1.3 * scale, 0), Color("ff9a3c"), 7.5 * scale, 22.0 * scale, false, 3.2)
	FX.fire_glow(holder, 30)
	FX.smoke_plume(holder, 16, 3.0)


func add_pickup(pos: Vector3, kind := "ammo", amount := 90) -> Node:
	var p := Pickup.new()
	p.setup(pos, kind, amount)
	_props.add_child(p)
	return p


func add_locker(pos: Vector3, yaw: float, height := 1.95) -> Locker:
	var l := Locker.new()
	l.setup(pos, yaw, height)
	_props.add_child(l)
	return l


func rain(amount := 2600) -> GPUParticles3D:
	return FX.rain(self, amount)


func embers(amount := 70, extents := Vector3(30, 6, 30)) -> GPUParticles3D:
	return FX.embers(self, amount, Color(1.0, 0.58, 0.22, 0.5), extents, 0.055)


## Guard patrol route generator around a square.
func ring_patrol(centre: Vector3, radius: float, points := 4, start_angle := 0.0) -> Array:
	var out: Array = []
	for i in points:
		var a := start_angle + TAU * float(i) / float(points)
		out.append(centre + Vector3(cos(a) * radius, 0, sin(a) * radius))
	return out


func line_patrol(from: Vector3, to: Vector3, points := 3) -> Array:
	var out: Array = []
	for i in points:
		out.append(from.lerp(to, float(i) / float(maxi(points - 1, 1))))
	return out
