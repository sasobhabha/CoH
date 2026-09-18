class_name Enemy
extends CharacterBody3D
## A hostile trooper.
##
## Finite state machine (IDLE / PATROL / ALERT / COMBAT / SEARCH / DEAD) driven
## by a vision cone with line-of-sight plus a hearing channel fed by the game's
## noise events.  Movement is context steering over five whiskers rather than a
## navmesh, which is plenty for streets, plazas and interiors and costs nothing
## to bake.
##
## Damage is received through `bullet_hit()`, a duck-typed contract shared with
## the player, so neither class has to know the other exists.

signal died(enemy: Node)
signal state_changed(enemy: Node, new_state: int)

enum State { IDLE, PATROL, ALERT, COMBAT, SEARCH, DEAD }

const HEAD_SHAPE := 1
const BODY_RADIUS := 0.36
const MAX_HEALTH := 100.0

# --- perception -------------------------------------------------------------
var view_range := 30.0
var view_angle := 62.0          # half-angle of the cone, degrees
var hear_range := 26.0
var reaction_time := 0.42

# --- combat -----------------------------------------------------------------
var preferred_min := 7.0
var preferred_max := 15.0
var burst_min := 3
var burst_max := 5
var shot_interval := 0.14
var burst_pause := 0.95
var damage_min := 7.0
var damage_max := 13.0
var accuracy := 0.42

var kind := "trooper"
var game: Node = null
var rig: HumanoidRig
var patrol_points: PackedVector3Array = PackedVector3Array()
var has_light := false
var is_squad_leader := false

var health := MAX_HEALTH
var alive := true
var state: State = State.IDLE
var alert := 0.0                # 0..1 awareness, drives the alert pip
var last_known := Vector3.ZERO

var _patrol_i := 0
var _wait := 0.0
var _reaction := 0.0
var _fire_cd := 0.0
var _burst_left := 0
var _pause_cd := 0.0
var _search_t := 0.0
var _seen_t := 0.0
var _stagger := 0.0
var _yaw := 0.0
var _dead_t := 0.0
var _spawn := Vector3.ZERO
var _muzzle_light: OmniLight3D
var _light: SpotLight3D
var _bar_root: Node3D
var _bar_fill: MeshInstance3D
var _bar_vis := 0.0
var _strafe_sign := 1.0
var _hp_last := MAX_HEALTH
var _capsule: CapsuleShape3D


func _ready() -> void:
	collision_layer = 4                     # enemy
	collision_mask = 1 | 4                  # world + other enemies
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.4
	floor_constant_speed = true
	_spawn = global_position

	rig = HumanoidRig.new()
	rig.name = "Rig"
	add_child(rig)
	var pal := palette_for(kind)
	rig.build(pal)

	# Sized from the rig that was actually loaded.  The hitboxes were authored
	# against the trooper, so a heavy a head taller than the trooper had its
	# head shot land on its shoulders.
	var st := rig.stature
	_capsule = CapsuleShape3D.new()
	_capsule.radius = BODY_RADIUS * st
	_capsule.height = 1.72 * st
	var body := CollisionShape3D.new()
	body.name = "Body"
	body.shape = _capsule
	body.position.y = 0.86 * st
	add_child(body)

	var head := CollisionShape3D.new()
	head.name = "Head"
	var hs := SphereShape3D.new()
	hs.radius = 0.17 * st
	head.shape = hs
	head.position.y = 1.62 * st
	add_child(head)

	# An unarmed archetype is not handed a rifle it was never posed to hold.
	if rig.is_armed():
		Build.rifle(rig.weapon_mount)

	_muzzle_light = Build.omni(rig.muzzle, Vector3.ZERO, Color("ffbe72"), 0.0, 14.0)
	_muzzle_light.shadow_enabled = false

	if has_light:
		_light = Build.spot(rig, Vector3(0, 1.55 * st, -0.1), Vector3(-6, 0, 0),
				Color("ffe6c0"), 4.0, 24.0, 22.0, true, 2.5)

	_build_health_bar()
	_set_state(State.PATROL if patrol_points.size() > 0 else State.IDLE)## `model` picks the archetype's mesh.  `bulk` is deliberately 1.0 for all of
## them: size is a property of the archetype now, carried in the geometry, and
## a per-kind bulk on top of that only fights the mesh it was authored from.
##
## One contingent, three roles.  The palette is sand cloth under a pale wrap
## with the contingent's red on the agal, and the roles are graded rather than
## recoloured so a column of them reads as one army: the line trooper wears the
## sand of the place, the heavy the same cloth in shadow under its plates, and
## the elite is nearly black so its pale wrap carries furthest.  These hexes are
## the same numbers `tools/gen_characters.py` authors the mesh with, which is
## what keeps the reference renders and the game showing one army.
const SAND := Color("8a7a5c")          # the line uniform
const SAND_PALE := Color("b8a688")     # its head-wrap
const SAND_DEEP := Color("6f6247")     # the heavy's cloth
const SAND_SHADOW := Color("9c8c6e")   # the heavy's wrap
const ELITE_CLOTH := Color("242a2e")
const ELITE_WRAP := Color("c8b493")
const ISSUE_RED := Color("a8342a")     # the agal, the plate band, the banner


static func palette_for(k := "trooper") -> Dictionary:
	match k:
		"guard":
			return {
				"primary": MatLib.painted(ELITE_CLOTH, "guard_a"),
				"secondary": MatLib.painted(Color("14181b"), "guard_b"),
				"scarf": MatLib.painted(ELITE_WRAP, "guard_wrap"),
				"gear": MatLib.painted(Color("1d1f21"), "guard_d"),
				"accent": MatLib.painted(Color("b03a26"), "guard_c"),
				"skin": MatLib.painted(Color("7d6448"), "guard_skin"),
				"visor": Color("ff7a4a"),
				"helmet": true,
				"armour": true,
				"bulk": 1.0,
				"model": "guard",
			}
		"heavy":
			return {
				"primary": MatLib.painted(SAND_DEEP, "heavy_a"),
				"secondary": MatLib.painted(Color("2f2b23"), "heavy_b"),
				"scarf": MatLib.painted(SAND_SHADOW, "heavy_wrap"),
				"gear": MatLib.painted(Color("3d3428"), "heavy_d"),
				"accent": MatLib.painted(ISSUE_RED, "heavy_c"),
				"skin": MatLib.painted(Color("8a765c"), "heavy_skin"),
				"helmet": true,
				"armour": true,
				"backpack": true,
				"bulk": 1.0,
				"model": "heavy",
			}
		_:
			return {
				"primary": MatLib.painted(SAND, "troop_a"),
				"secondary": MatLib.painted(Color("3a352b"), "troop_b"),
				"scarf": MatLib.painted(SAND_PALE, "troop_wrap"),
				"gear": MatLib.painted(Color("4a3f30"), "troop_d"),
				"accent": MatLib.painted(ISSUE_RED, "troop_c"),
				"skin": MatLib.painted(Color("8a765c"), "troop_skin"),
				"helmet": true,
				"armour": true,
				"bulk": 1.0,
				"model": "trooper",
			}


func _build_health_bar() -> void:
	_bar_root = Node3D.new()
	_bar_root.name = "HealthBar"
	_bar_root.position.y = 2.02 * (rig.stature if rig != null else 1.0)
	_bar_root.visible = false
	add_child(_bar_root)

	var back := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.78, 0.075)
	back.mesh = q
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(0.03, 0.03, 0.04, 0.78)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bm.billboard_keep_scale = true
	bm.disable_receive_shadows = true
	back.material_override = bm
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar_root.add_child(back)

	_bar_fill = MeshInstance3D.new()
	var qf := QuadMesh.new()
	qf.size = Vector2(1.0, 0.05)
	_bar_fill.mesh = qf
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(0.95, 0.32, 0.24)
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.billboard_keep_scale = true
	fm.disable_receive_shadows = true
	_bar_fill.material_override = fm
	_bar_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar_fill.position.z = -0.01
	_bar_root.add_child(_bar_fill)
	_update_health_bar()


# ------------------------------------------------------------------ interface

## Duck-typed damage entry point shared with the player's hitscan.
func bullet_hit(_point: Vector3, _normal: Vector3, dir: Vector3, shape_index: int,
		body_damage: float, head_damage: float) -> bool:
	if not alive:
		return false
	var head := shape_index == HEAD_SHAPE
	take_damage(head_damage if head else body_damage, _point, dir)
	return head


func take_damage(amount: float, point: Vector3, dir: Vector3) -> void:
	if not alive:
		return
	health -= amount
	_last_attacker_pos = point - dir * 3.0
	rig.flash(0.95)
	_stagger = 0.22
	alert = 1.0
	_update_health_bar()
	if player() != null:
		last_known = player().global_position
	if health <= 0.0:
		_die(dir)
		return
	if state != State.COMBAT:
		_set_state(State.COMBAT)
		AudioDirector.play_at("enemy_pain", global_position, -6.0, 1.0, 0.08)
	_shout()


var _last_attacker_pos := Vector3.ZERO


func player() -> Node3D:
	if game == null:
		return null
	return game.player


func prompt() -> String:
	return "" 


func is_alerted() -> bool:
	return state == State.COMBAT or state == State.ALERT or state == State.SEARCH


# --------------------------------------------------------------------- senses

func _can_see_player() -> bool:
	var p := player()
	if p == null or not p.alive:
		return false
	if p.has_method("is_hidden") and p.is_hidden():
		return false
	var eye := rig.head.global_position
	var target := p.global_position + Vector3(0, 1.2, 0)
	var to := target - eye
	var dist := to.length()
	var eff_range := view_range
	if p.crouching:
		eff_range *= 0.62
	if Vector2(p.velocity.x, p.velocity.z).length() > 5.0:
		eff_range *= 1.15
	if dist > eff_range:
		return false
	var facing := -rig.global_transform.basis.z
	if dist > 2.0:
		var flat_facing := Vector3(facing.x, 0, facing.z).normalized()
		var flat_to := Vector3(to.x, 0, to.z).normalized()
		if rad_to_deg(flat_facing.angle_to(flat_to)) > view_angle:
			return false
	var q := PhysicsRayQueryParameters3D.create(eye, target)
	q.collision_mask = 1 | 2
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	return hit.get("collider") == p


## Called by the game when a noise is made nearby.
func hear_noise(pos: Vector3, radius: float) -> void:
	if not alive:
		return
	var dist := global_position.distance_to(pos)
	if dist > radius or dist > hear_range:
		return
	last_known = pos
	if state == State.COMBAT:
		return
	if dist < radius * 0.45:
		alert = 1.0
		_set_state(State.SEARCH)
		_search_t = 0.0
	else:
		alert = maxf(alert, 0.6)
		if state == State.IDLE or state == State.PATROL:
			_set_state(State.ALERT)


## A squadmate saw something.
func receive_alert(pos: Vector3) -> void:
	if not alive or state == State.COMBAT:
		return
	last_known = pos
	alert = 1.0
	_set_state(State.SEARCH)
	_search_t = 0.0


# --------------------------------------------------------------------- states

func _set_state(s: State) -> void:
	if s == state:
		return
	state = s
	state_changed.emit(self, s)
	match s:
		State.COMBAT:
			_shout()
		State.SEARCH:
			_search_t = 0.0
		State.ALERT:
			_search_t = 0.0


func _shout() -> void:
	if game == null:
		return
	AudioDirector.play_at("enemy_alert" if is_squad_leader else "enemy_shout",
			global_position, -7.0, 1.0, 0.08)
	if game.has_method("alert_enemies"):
		game.alert_enemies(global_position, last_known, 34.0)


func _physics_process(delta: float) -> void:
	if not alive:
		_dead_t += delta
		rig.update(delta, {"speed": 0.0})
		rig.tick_flash(delta)
		if _dead_t > 1.6:
			_bar_root.visible = false
		return

	if _stagger > 0.0:
		_stagger = maxf(0.0, _stagger - delta)

	_perceive(delta)

	var speed := 0.0
	match state:
		State.IDLE: speed = _do_idle(delta)
		State.PATROL: speed = _do_patrol(delta)
		State.ALERT: speed = _do_alert(delta)
		State.COMBAT: speed = _do_combat(delta)
		State.SEARCH: speed = _do_search(delta)

	if not is_on_floor():
		velocity.y -= 24.0 * delta
	else:
		velocity.y = -0.4
	move_and_slide()

	# --- facing ----------------------------------------------------------
	if rig != null:
		var face_yaw := _yaw
		if state == State.COMBAT and player() != null:
			face_yaw = atan2(-(player().global_position - global_position).x,
					-(player().global_position - global_position).z)
		else:
			var vel_flat := Vector3(velocity.x, 0, velocity.z)
			if vel_flat.length() > 0.4:
				face_yaw = atan2(-vel_flat.x, -vel_flat.z)
		rig.rotation.y = lerp_angle(rig.rotation.y, face_yaw, minf(1.0, delta * 7.0))

		rig.update(delta, {
			"speed": speed,
			"max_speed": 4.4,
			"crouch": 0.35 if state == State.SEARCH else 0.0,
			"grounded": is_on_floor(),
			"aiming": state == State.COMBAT and _reaction <= 0.0,
			"aim_pitch": 0.0,
			"strafe": 0.0,
			"forward": 1.0,
		})
		rig.tick_flash(delta)

	if _muzzle_light != null:
		_muzzle_light.light_energy = maxf(0.0, _muzzle_light.light_energy - delta * 46.0)

	# --- health bar fade --------------------------------------------------
	var want := 1.0 if (health < MAX_HEALTH and _visible_to_camera()) else 0.0
	_bar_vis = lerpf(_bar_vis, want, minf(1.0, delta * 6.0))
	_bar_root.visible = _bar_vis > 0.02
	_bar_root.scale = Vector3.ONE * lerpf(0.6, 1.0, _bar_vis)


func _visible_to_camera() -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	return cam.global_position.distance_to(global_position) < 45.0


func _perceive(delta: float) -> void:
	# decay awareness when nothing is confirmed
	var p := player()
	var sees := _can_see_player()
	if sees:
		alert = 1.0
		last_known = p.global_position
		_seen_t = 0.0
	else:
		_seen_t += delta
		if _seen_t > 3.5:
			alert = maxf(0.0, alert - delta * 0.28)

	match state:
		State.IDLE, State.PATROL:
			if sees:
				_set_state(State.ALERT)
			elif alert > 0.35 and _seen_t > 0.6:
				_set_state(State.SEARCH)
		State.ALERT:
			_reaction -= delta
			if sees and _reaction <= 0.0:
				_set_state(State.COMBAT)
			elif not sees and _seen_t > 4.0:
				_set_state(State.SEARCH)
		State.COMBAT:
			if not sees and _seen_t > 5.0:
				_set_state(State.SEARCH)
		State.SEARCH:
			_search_t += delta
			if sees:
				_set_state(State.COMBAT)
			elif _search_t > 11.0:
				alert = 0.0
				_set_state(State.PATROL if patrol_points.size() > 0 else State.IDLE)


# --------------------------------------------------------------------- states

func _do_idle(_delta: float) -> float:
	_brake()
	return 0.0


func _do_patrol(delta: float) -> float:
	if patrol_points.size() == 0:
		return 0.0
	if _wait > 0.0:
		_wait -= delta
		_brake()
		return 0.0
	var target := patrol_points[_patrol_i]
	if global_position.distance_to(target) < 1.4:
		_patrol_i = (_patrol_i + 1) % patrol_points.size()
		_wait = randf_range(1.4, 3.6)
		_yaw = randf_range(0.0, TAU)
		return 0.0
	return _move_towards(target, 2.4, delta)


func _do_alert(delta: float) -> float:
	# turn towards the disturbance, weapon up, no advance yet
	var to := last_known - global_position
	_yaw = atan2(-to.x, -to.z)
	_brake()
	return 0.0


func _do_search(delta: float) -> float:
	var dist := global_position.distance_to(last_known)
	if dist > 2.0:
		return _move_towards(last_known, 4.0, delta)
	# sweep the area
	_yaw = _yaw + sin(_search_t * 1.1) * delta * 1.4
	if _search_t > 3.0 and randf() < delta * 0.4:
		last_known = _spawn + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
	_search_t += delta
	_brake()
	return 0.0


func _do_combat(delta: float) -> float:
	var p := player()
	if p == null:
		return 0.0
	var to := p.global_position - global_position
	var dist := to.length()
	var sees := _can_see_player()

	# hold a firing lane
	if dist > preferred_max:
		return _move_towards(p.global_position, 4.6, delta)
	if dist < preferred_min:
		return _move_towards(global_position * 2.0 - p.global_position, 3.2, delta)

	# strafe and keep the lane
	if randf() < delta * 0.5:
		_strafe_sign *= -1.0
	var sideways := Vector3(to.z, 0, -to.x).normalized() * _strafe_sign
	var lat := _steer(sideways)
	_set_horizontal(lat, 2.6, delta)
	_last_attacker_pos = p.global_position

	if sees and _reaction <= 0.0:
		_shoot(delta, dist)
	return velocity.length()


func _shoot(delta: float, dist: float) -> void:
	_fire_cd -= delta
	_pause_cd -= delta
	if _pause_cd > 0.0:
		return
	if _burst_left <= 0:
		_burst_left = randi_range(burst_min, burst_max)
	if _fire_cd > 0.0:
		return

	_fire_cd = shot_interval
	_burst_left -= 1
	if _burst_left <= 0:
		_pause_cd = burst_pause * randf_range(0.7, 1.5)

	var p := player()
	if p == null:
		return

	var eye := rig.muzzle.global_position
	var aim_point := p.global_position + Vector3(0, randf_range(0.7, 1.5), 0)
	# Accuracy falls off with range and improves while the target is tracked.
	var falloff := clampf(1.0 - (dist - 6.0) / 34.0, 0.25, 1.0)
	var spread := deg_to_rad(lerpf(5.5, 0.7, accuracy * falloff))
	var dir := (aim_point - eye).normalized()
	dir = dir.rotated(Vector3.UP, randf_range(-spread, spread))
	dir = dir.rotated(rig.global_transform.basis.x, randf_range(-spread, spread)).normalized()

	var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * 120.0)
	q.collision_mask = 1 | 2 | 8
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end_pos := eye + dir * 120.0
	if not hit.is_empty():
		end_pos = hit.position
		if hit.get("collider") == p:
			var dmg := randf_range(damage_min, damage_max) * falloff
			if p.has_method("apply_damage"):
				p.call("apply_damage", dmg, global_position)

	if game != null and game.tracers != null:
		game.tracers.fire(eye, end_pos, 0.018, Color(1.0, 0.45, 0.32))
	if game != null and game.impacts != null and not hit.is_empty() and hit.get("collider") != p:
		game.impacts.impact(hit.position, hit.get("normal", Vector3.UP), "concrete")

	AudioDirector.play_at("rifle_fire_%d" % randi_range(1, 3), global_position, -6.0, 0.9, 0.06, 90.0)
	_muzzle_light.light_energy = 7.0
	if game != null and game.has_method("alert_enemies"):
		game.alert_enemies(global_position, p.global_position, 34.0)


# ------------------------------------------------------------------- steering

func _move_towards(target: Vector3, speed: float, delta: float) -> float:
	var to := target - global_position
	to.y = 0.0
	if to.length() < 0.05:
		_brake()
		return 0.0
	var dir := _steer(to.normalized())
	_set_horizontal(dir, speed, delta)
	return velocity.length()


func _set_horizontal(dir: Vector3, speed: float, delta: float) -> void:
	var slow := 0.55 if _stagger > 0.0 else 1.0
	var desired := dir * speed * slow
	var rate := 12.0
	var k := 1.0 - exp(-rate * delta)
	velocity.x = lerpf(velocity.x, desired.x, k)
	velocity.z = lerpf(velocity.z, desired.z, k)


func _brake() -> void:
	velocity.x = move_toward(velocity.x, 0.0, 18.0 * get_physics_process_delta_time())
	velocity.z = move_toward(velocity.z, 0.0, 18.0 * get_physics_process_delta_time())


func _steer(desired: Vector3) -> Vector3:
	var best := desired
	var best_score := -1e9
	for a in range(-70, 71, 14):
		var d := desired.rotated(Vector3.UP, deg_to_rad(float(a)))
		var free := _free_distance(d, 2.4)
		var score := free + d.dot(desired) * 1.5
		if score > best_score:
			best_score = score
			best = d
	return best.normalized()


func _free_distance(dir: Vector3, max_dist: float) -> float:
	var from := global_position + Vector3(0, 0.9, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * max_dist)
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return max_dist
	return from.distance_to(hit.position)


# ---------------------------------------------------------------------- death

func _die(dir: Vector3) -> void:
	alive = false
	state = State.DEAD
	_dead_t = 0.0
	collision_layer = 0
	collision_mask = 0
	rig.die(randf_range(-0.5, 0.5))
	AudioDirector.play_at("enemy_death", global_position, -4.0, 1.0, 0.08)
	AudioDirector.play_at("flesh_fall", global_position, -8.0, 1.0, 0.1)
	GameManager.add_stat("kills", 1)
	died.emit(self)
	if game != null and game.has_method("on_enemy_died"):
		game.on_enemy_died(self)
	set_physics_process(true)


func _update_health_bar() -> void:
	if _bar_fill == null:
		return
	var ratio := clampf(health / MAX_HEALTH, 0.0, 1.0)
	_bar_fill.scale.x = maxf(ratio, 0.001)
	_bar_fill.position.x = -(0.78 * (1.0 - ratio)) * 0.5
	_bar_vis = maxf(_bar_vis, 0.3)


func disarm() -> void:
	## Used by scripted moments (surrender, cutscene).
	set_physics_process(false)
	velocity = Vector3.ZERO
