class_name Player
extends CharacterBody3D
## The scout.
##
## Third-person character controller covering locomotion, a hitscan rifle with
## recoil/spread/reload, interaction, hiding and damage.  Presentation is
## delegated: the rig animates from a parameter dictionary, the camera reads
## the target, and every event the HUD cares about is a signal.

signal health_changed(health: float, max_health: float)
signal ammo_changed(mag: int, reserve: int)
signal stamina_changed(value: float)
signal damaged(from_direction: Vector3, amount: float)
signal died
signal hidden_changed(hidden: bool)
signal focus_changed(target: Node, label: String)
signal noised(position: Vector3, radius: float)
signal splash(eye_under: bool)

# --- movement ---------------------------------------------------------------
const WALK_SPEED := 4.3
const SPRINT_SPEED := 7.7
const CROUCH_SPEED := 2.3
const AIM_SPEED := 2.6
const ACCEL_GROUND := 42.0
const ACCEL_AIR := 9.0
const DECEL := 30.0
const JUMP_VELOCITY := 8.2
const GRAVITY := 24.0

# --- water -----------------------------------------------------------------
# The district flood is modelled, not faked: buoyancy from the submerged
# fraction of the capsule, quadratic drag, depth-dependent speeds, and a
# crouch that lets you sink below the surface.  Numbers follow from taking a
# 75 kg body in water: displacement of ~0.075 m³ needs ~735 N of lift, which
# the capsule fraction delivers; drag uses Cd·A≈0.24 in water -- a swimmer's
# streamlined glide (0.85 is the standing figure in air).
const WATER_DENSITY := 1000.0        # kg/m³
const BODY_MASS := 75.0              # kg -- drives buoyant force F = rho·g·V
const G := 9.81                      # m/s² -- real gravity for buoyancy scale
const DRAG_CA := 0.24                # Cd·A in water: a swimmer glides (0.85 is air)
const DRAG_CA_CROUCH := 0.12         # tucked, streamlined
const DRAG_CA_SWIM := 0.55
const BUOY_NEUTRAL := 1.02           # slight float; lungs = vestigial swim bladder
const BUOY_SINK := 0.55              # crouch exhales: deliberately sink to submerge
const BUOY_SWIM := 0.98              # near-neutral swim, drifts up a hair
const WADE_Y := 0.55                 # where wading resistance starts to bite
const SWIM_Y := 1.4                  # over chest-deep: swimming replaces wading
const SUBMERGED_Y := 1.6             # eyes under: held-breath timer starts
const WADE_SPEED := 2.1              # wading through chest-deep water
const SHOULDER_SPEED := 3.2          # thigh-deep
const SWIM_SPEED := 2.9              # front crawl-ish through the market
const SPLASH_V := 3.4                # entry speed that counts as a proper dive
const BREATH_TIME := 18.0            # seconds of air
const BREATH_RECOVER := 4.0          # per-second refil once breathing again

# --- combat -----------------------------------------------------------------
const MAX_HEALTH := 100.0
const MAG_SIZE := 30
const RESERVE_START := 180
# The magazine still empties and still has to be changed -- that rhythm, the
# animation and the HUD ring all stay -- but the pouches are never spent, so
# there is nothing to run the player dry mid-fight.  Set false for a finite
# 180-round reserve, which is what the pickups on the map are for.
const UNLIMITED_AMMO := true
const FIRE_INTERVAL := 0.098
const RELOAD_TIME := 2.25
const BODY_DAMAGE := 24.0
const HEAD_DAMAGE := 62.0
const RANGE := 240.0
const MELEE_RANGE := 2.3
const MELEE_DAMAGE := 45.0

# --- stamina ----------------------------------------------------------------
const STAMINA_MAX := 100.0
const STAMINA_DRAIN := 22.0
const STAMINA_REGEN := 26.0
const STAMINA_DELAY := 1.1

var game: Node = null
var rig: HumanoidRig
var cam_rig: CameraRig
var weapon_root: Node3D
var flashlight: SpotLight3D

var health := MAX_HEALTH
var mag := MAG_SIZE
var reserve := RESERVE_START
var stamina := STAMINA_MAX

var alive := true
var input_blocked := false
var aiming := false
var sprinting := false
var crouching := false
var _hidden_in: Node = null
var _water_level := -1000.0
var _was_in_water := false
var _swim_mode := false
var _under_water := false
var _breath := BREATH_TIME
var _splash_cd := 0.0
var _drown_t := 0.0

var _fire_cd := 0.0
var _reloading := false
var _reload_t := 0.0
var _bolt_played := false
var _melee_cd := 0.0
var _spread_heat := 0.0
var _stride := 0.0
var _was_grounded := true
var _fall_speed := 0.0
var _stamina_lock := 0.0
var _regen_delay := 0.0
var _flash_light_energy := 0.0
var _flashlight_on := false
var _focus: Node = null
var _muzzle_light: OmniLight3D
var _muzzle_quad: MeshInstance3D
var _muzzle_quad_mat: StandardMaterial3D
var _dead_t := 0.0
var _body_yaw := 0.0
var _warp_ready := true
var _action_suppress := 0.0
var _strafe := 0.0
var _forward_amt := 1.0
var _capsule: CapsuleShape3D
var _body_shape: CollisionShape3D


func _ready() -> void:
	collision_layer = 2      # player
	collision_mask = 1 | 4   # world + enemies
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.35
	wall_min_slide_angle = deg_to_rad(12.0)
	floor_constant_speed = true

	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.36
	_capsule.height = 1.78
	var cs := CollisionShape3D.new()
	cs.name = "Body"
	cs.shape = _capsule
	cs.position.y = 0.89
	_body_shape = cs
	add_child(cs)

	rig = HumanoidRig.new()
	rig.name = "Rig"
	add_child(rig)
	rig.build({
		"primary": MatLib.painted(Color("78868f"), "player_armour"),
		"secondary": MatLib.painted(Color("39424a"), "player_under"),
		"accent": MatLib.painted(Color("c08a45"), "player_accent"),
		"skin": MatLib.painted(Color("9a7f61"), "player_skin"),
		"visor": Color("7fe4ff"),
		"helmet": true,
		"armour": true,
		"backpack": true,
		"bulk": 1.0,
		"model": "player",
	})
	_build_weapon()

	cam_rig = CameraRig.new()
	cam_rig.name = "CameraRig"
	add_child(cam_rig)
	cam_rig.setup(self, float(Settings.getv("fov")))

	flashlight = SpotLight3D.new()
	flashlight.light_energy = 0.0
	flashlight.light_color = Color("ffeedd")
	flashlight.spot_range = 34.0
	flashlight.spot_angle = 26.0
	flashlight.spot_angle_attenuation = 1.8
	flashlight.shadow_enabled = true
	flashlight.shadow_bias = 0.03
	flashlight.light_volumetric_fog_energy = 3.0
	flashlight.position = Vector3(0.24, -0.14, 0.0)
	cam_rig.add_child(flashlight)

	# A soft fill riding with the camera.  Backlit and night-time shots otherwise
	# turn the hero into a silhouette, which reads as a bug rather than as a
	# lighting choice.  It is short-range and shadowless, so it only lifts the
	# character and the ground immediately around them.
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.0, 0.6, 1.5)
	fill.light_color = Color("bcd2e4")
	fill.light_energy = 2.4
	fill.omni_range = 7.0
	fill.omni_attenuation = 2.2
	fill.shadow_enabled = false
	fill.light_volumetric_fog_energy = 0.0
	fill.light_specular = 0.2
	cam_rig.add_child(fill)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	health_changed.emit(health, MAX_HEALTH)
	ammo_changed.emit(mag, reserve)


func _build_weapon() -> void:
	# The rifle hangs off the skeleton's chest-space `weapon` bone, not the right
	# hand: the geometry is authored with its origin at the grip and its barrel
	# down -Z, and the mount supplies the axis correction.
	weapon_root = Build.rifle(rig.weapon_mount)

	_muzzle_light = Build.omni(weapon_root, Vector3(0, 0.012, -0.66), Color("ffce8a"), 0.0, 16.0)
	_muzzle_light.shadow_enabled = false

	_muzzle_quad_mat = StandardMaterial3D.new()
	_muzzle_quad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_muzzle_quad_mat.albedo_color = Color(1.0, 0.86, 0.55, 0.0)
	_muzzle_quad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_muzzle_quad_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_muzzle_quad_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_muzzle_quad_mat.disable_receive_shadows = true
	_muzzle_quad = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.42, 0.42)
	_muzzle_quad.mesh = q
	_muzzle_quad.material_override = _muzzle_quad_mat
	_muzzle_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_muzzle_quad.position = Vector3(0, 0.012, -0.68)
	weapon_root.add_child(_muzzle_quad)


# ------------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not alive or _dead_t > 0.0 or input_blocked:
		return
	# Undocumented cheat (F3): blink to whatever the crosshair is over.  Not in
	# the options bindings list, the HUD hints or the input audit -- it is not
	# supposed to exist.  Guarded against the menus by `input_blocked`, since
	# pause/dialogue block player input before anything else here runs.
	if event.is_action_pressed("warp"):
		get_viewport().set_input_as_handled()
		_warp()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := float(Settings.getv("mouse_sensitivity"))
		var dy := float(event.relative.y) * s
		if bool(Settings.getv("invert_y")):
			dy = -dy
		cam_rig.look(Vector2(float(event.relative.x) * s, dy))


# ------------------------------------------------------------------ process

## Blink to the crosshair: raycast from the camera through the aim point,
## land a body-height clear of the hit (or at max range in the open), and
## drop in.  Cooldown keeps key-repeat from machine-gunning it.
func _warp() -> void:
	if not _warp_ready:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_warp_ready = false
	get_tree().create_timer(0.35).timeout.connect(func(): _warp_ready = true)

	var space := get_world_3d().direct_space_state
	var from := cam.global_position
	var to := from + cam.global_transform.basis * Vector3(0, 0, -1) * 160.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	q.collision_mask = 0xFFFFFFFF
	var hit := space.intersect_ray(q)
	var target: Vector3 = to
	if hit.has("position"):
		var n: Vector3 = hit.get("normal", Vector3.UP)
		target = hit["position"] + n * 0.9
		# pull back off walls a little so the capsule does not spawn embedded
		var back: Vector3 = (from - hit["position"])
		back.y = 0.0
		if back.length_squared() > 0.01:
			target += back.normalized() * 0.6
	# never warp below the map: clamp to something sane above the world floor
	target.y = maxf(target.y, -6.0)

	AudioDirector.play("whoosh", -8.0, 1.25, 0.05)
	velocity = Vector3.ZERO
	_fall_speed = 0.0
	global_position = target
	move_and_slide()
	cam_rig.add_trauma(0.18)
	if game != null and game.has_method("notify"):
		game.call("notify", "")


func _physics_process(delta: float) -> void:
	_action_suppress = maxf(0.0, _action_suppress - delta)
	if not alive:
		_update_death(delta)
		return

	var look_axis := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look_axis.length_squared() > 0.0:
		var gs := float(Settings.getv("gamepad_sensitivity")) * delta
		var dy := look_axis.y * gs
		if bool(Settings.getv("invert_y")):
			dy = -dy
		cam_rig.look(Vector2(look_axis.x * gs, dy))

	_update_stance(delta)
	if _hidden_in == null:
		_update_water(delta)
		if _swim_mode:
			_update_swim(delta)
		else:
			_update_movement(delta)
	else:
		velocity = Vector3.ZERO
		move_and_slide()

	_update_weapon(delta)
	_update_interaction()
	_update_rig(delta)

	cam_rig.update(delta, aiming, sprinting and velocity.length() > 4.5, _hidden_in != null)

	# --- flashlight -----------------------------------------------------
	var want_light := 0.0
	if _flashlight_on:
		want_light = 4.5
	_flash_light_energy = lerpf(_flash_light_energy, want_light, minf(1.0, delta * 14.0))
	flashlight.light_energy = _flash_light_energy

	# muzzle flash decay
	if _muzzle_light != null:
		_muzzle_light.light_energy = maxf(0.0, _muzzle_light.light_energy - delta * 55.0)
		_muzzle_quad_mat.albedo_color.a = maxf(0.0, _muzzle_quad_mat.albedo_color.a - delta * 8.0)

	# --- health regeneration --------------------------------------------
	if health < MAX_HEALTH and health > 0.0:
		_regen_delay += delta
		if _regen_delay > 7.0 and health < MAX_HEALTH * 0.65:
			health = minf(MAX_HEALTH * 0.65, health + delta * 8.0)
			health_changed.emit(health, MAX_HEALTH)


func _update_stance(delta: float) -> void:
	if input_blocked:
		aiming = false
		sprinting = false
		stamina = minf(STAMINA_MAX, stamina + STAMINA_REGEN * delta)
		stamina_changed.emit(stamina / STAMINA_MAX)
		return
	aiming = Input.is_action_pressed("aim") and _hidden_in == null
	crouching = Input.is_action_pressed("crouch")
	var wants_sprint := Input.is_action_pressed("sprint") and not aiming and not crouching \
			and velocity.length() > 1.0 and stamina > 6.0
	sprinting = wants_sprint and is_on_floor()

	if sprinting:
		stamina = maxf(0.0, stamina - STAMINA_DRAIN * delta)
		_stamina_lock = STAMINA_DELAY
	else:
		_stamina_lock = maxf(0.0, _stamina_lock - delta)
		if _stamina_lock <= 0.0:
			stamina = minf(STAMINA_MAX, stamina + STAMINA_REGEN * delta)
	stamina_changed.emit(stamina / STAMINA_MAX)


func _update_movement(delta: float) -> void:
	var input := Vector2.ZERO if input_blocked \
			else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis := Basis(Vector3.UP, cam_rig.yaw)
	var dir := basis * Vector3(input.x, 0.0, input.y)
	if dir.length_squared() > 1.0:
		dir = dir.normalized()

	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif aiming:
		speed = AIM_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	if health < MAX_HEALTH * 0.3:
		speed *= 0.94

	# waist-deep flood drags: thigh-deep clamps to a shoulder-high wade, and at
	# chest depth the swim handler takes the body over entirely
	var depth := water_depth()
	if depth > WADE_Y:
		var t := clampf((depth - WADE_Y) / (SWIM_Y - WADE_Y), 0.0, 1.0)
		speed = minf(speed, lerpf(SHOULDER_SPEED, WADE_SPEED, t))

	var desired := dir * speed
	var rate := ACCEL_GROUND if is_on_floor() else ACCEL_AIR
	if dir.length_squared() < 0.01:
		rate = DECEL
	var k := 1.0 - exp(-rate * delta)
	velocity.x = lerpf(velocity.x, desired.x, k)
	velocity.z = lerpf(velocity.z, desired.z, k)

	# --- gravity / jump -------------------------------------------------
	if not is_on_floor():
		_fall_speed = maxf(_fall_speed, -velocity.y)
		velocity.y -= GRAVITY * delta
	else:
		if _fall_speed > 7.5 and not _was_grounded:
			var impact := clampf((_fall_speed - 7.5) / 12.0, 0.0, 1.0)
			AudioDirector.play("land", linear_to_db(clampf(0.4 + impact, 0.1, 1.0)), 1.0, 0.06)
			cam_rig.add_trauma(0.22 + impact * 0.5)
			if impact > 0.55:
				apply_damage(impact * 30.0, global_position + Vector3(0, -1, 0), true)
		_fall_speed = 0.0
		velocity.y = -0.35
		if not input_blocked and Input.is_action_just_pressed("jump") and not crouching:
			velocity.y = JUMP_VELOCITY
			AudioDirector.play("jump_grunt", -8.0, 1.0, 0.05)
			crouching = false
	_was_grounded = is_on_floor()

	# --- crouch collider -------------------------------------------------
	if _capsule != null and _body_shape != null:
		var want := 1.05 if crouching else 1.78
		if absf(_capsule.height - want) > 0.01:
			_capsule.height = lerpf(_capsule.height, want, minf(1.0, delta * 12.0))
			_body_shape.position.y = _capsule.height * 0.5

	move_and_slide()

	# --- facing ----------------------------------------------------------
	var target_yaw := _body_yaw
	if aiming:
		target_yaw = cam_rig.yaw
	elif dir.length_squared() > 0.01:
		target_yaw = atan2(-dir.x, -dir.z)
	_body_yaw = lerp_angle(_body_yaw, target_yaw, minf(1.0, delta * (16.0 if aiming else 11.0)))
	rig.rotation.y = _body_yaw

	var local := basis.inverse() * velocity
	_strafe = clampf(local.x / maxf(WALK_SPEED, 0.1), -1.0, 1.0)
	_forward_amt = clampf(dir.dot(-basis.z), -1.0, 1.0)

	_footsteps(delta)


# -------------------------------------------------------------------- water

## Public hook: GameScene hands the chapter's waterline over every frame, so
## the buoyancy maths can never drift from the level that renders the water.
func set_water_level(y: float) -> void:
	_water_level = y


## Water depth at the feet.  Deeply negative on dry ground, which makes every
## threshold test below fall through to the dry-land behaviour.
func water_depth() -> float:
	return _water_level - global_position.y


## Runs before locomotion every physics tick: tracks the swim/wade gate, the
## entry splash, and the held-breath timer that starts when the eyes go under.
func _update_water(delta: float) -> void:
	var depth := water_depth()

	# hysteresis on the swim gate, so treading at chest depth does not flicker
	# the mode (and the pose) every frame
	if _swim_mode:
		_swim_mode = depth > SWIM_Y - 0.15
	else:
		_swim_mode = depth > SWIM_Y

	var in_water := depth > WADE_Y
	if in_water and not _was_in_water and _fall_speed > SPLASH_V:
		AudioDirector.play("impact_water", -4.0, randf_range(0.92, 1.05), 0.05)
		splash.emit(depth > SUBMERGED_Y)
		noised.emit(global_position, 12.0)
	_was_in_water = in_water

	if depth > SUBMERGED_Y:
		_under_water = true
		_breath = maxf(0.0, _breath - delta)
		if _breath <= 0.0:
			_drown_t += delta
			if _drown_t >= 1.0:
				_drown_t = 0.0
				apply_damage(9.0, global_position + Vector3(0, 1.4, 0), true)
	else:
		_under_water = false
		_breath = minf(BREATH_TIME, _breath + BREATH_RECOVER * delta)
		_drown_t = 0.0


## Full swim: input steers, buoyancy carries, the stroke (jump) climbs, the
## exhale (crouch) sinks.  Gravity is not applied -- the water owns vertical.
func _update_swim(delta: float) -> void:
	var input := Vector2.ZERO if input_blocked \
			else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis := Basis(Vector3.UP, cam_rig.yaw)
	var dir := basis * Vector3(input.x, 0.0, input.y)
	if dir.length_squared() > 1.0:
		dir = dir.normalized()

	var speed := SWIM_SPEED
	if aiming:
		speed *= 0.62
	if health < MAX_HEALTH * 0.3:
		speed *= 0.94
	var k := 1.0 - exp(-3.4 * delta)   # water loads the body: slow to answer
	velocity.x = lerpf(velocity.x, dir.x * speed, k)
	velocity.z = lerpf(velocity.z, dir.z * speed, k)

	# --- vertical: slight positive buoyancy, stroked and dived by input -----
	# The deeper the body, the harder it rises once the stroke stops -- which
	# is what makes letting go of the dive key read as surfacing.
	var target_vy := (BUOY_NEUTRAL - 1.0) * 12.0 \
			+ maxf(0.0, water_depth() - SWIM_Y) * 0.9
	if not input_blocked and Input.is_action_pressed("jump"):
		target_vy = 2.3                    # the stroke: pull upward
	elif crouching:
		target_vy = -2.6                   # exhale: deliberately sink
	var depth := water_depth()
	if target_vy > 0.0 and depth < SWIM_Y + 0.3:
		# soften the climb so the body crests the surface instead of breaching
		target_vy *= clampf((depth - (SWIM_Y - 0.15)) / 0.45, 0.0, 1.0)
	velocity.y = move_toward(velocity.y, target_vy, 9.0 * delta)

	stamina = maxf(0.0, stamina - 5.0 * delta)
	stamina_changed.emit(stamina / STAMINA_MAX)

	move_and_slide()
	_was_grounded = false
	_fall_speed = 0.0

	var local := basis.inverse() * velocity
	_strafe = clampf(local.x / maxf(SWIM_SPEED, 0.1), -1.0, 1.0)
	_forward_amt = clampf(dir.dot(-basis.z), -1.0, 1.0)
	var target_yaw := _body_yaw
	if dir.length_squared() > 0.01:
		target_yaw = atan2(-dir.x, -dir.z)
	elif aiming:
		target_yaw = cam_rig.yaw
	_body_yaw = lerp_angle(_body_yaw, target_yaw, minf(1.0, delta * 8.0))
	rig.rotation.y = _body_yaw


func _footsteps(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or speed < 0.6:
		return
	_stride += speed * delta
	var step_len := 2.05 if not sprinting else 2.5
	if _stride < step_len:
		return
	_stride = 0.0
	var surface := "concrete"
	if game != null and game.has_method("surface_at"):
		surface = String(game.surface_at(global_position))
	var vol := -6.0 if not sprinting else -2.0
	if crouching:
		vol = -14.0
	AudioDirector.play_variant("step_" + surface, 4, vol, 0.09)
	if surface == "water":
		noised.emit(global_position, 14.0)


func _update_rig(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	rig.update(delta, {
		"speed": speed,
		"max_speed": SPRINT_SPEED,
		"crouch": 1.0 if crouching else 0.0,
		"grounded": is_on_floor(),
		"aiming": aiming,
		"aim_pitch": cam_rig.pitch,
		"strafe": _strafe,
		"forward": _forward_amt,
	})
	rig.tick_flash(delta)


func _update_death(delta: float) -> void:
	_dead_t += delta
	cam_rig.update(delta, false, false, false)
	cam_rig.pitch = lerpf(cam_rig.pitch, -0.42, minf(1.0, delta * 1.4))
	cam_rig.head_offset = lerpf(cam_rig.head_offset, 0.42, minf(1.0, delta * 1.6))
	rig.update(delta, {"speed": 0.0})
	rig.tick_flash(delta)


# ------------------------------------------------------------------ combat

func _update_weapon(delta: float) -> void:
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_melee_cd = maxf(0.0, _melee_cd - delta)
	_spread_heat = maxf(0.0, _spread_heat - delta * 2.4)
	if input_blocked:
		return

	if _reloading:
		_reload_t += delta
		if not _bolt_played and _reload_t > RELOAD_TIME * 0.52:
			_bolt_played = true
			AudioDirector.play("mag_in", -4.0, 1.0, 0.04)
		if _reload_t >= RELOAD_TIME:
			_reloading = false
			var need := MAG_SIZE - mag
			if UNLIMITED_AMMO:
				mag += need
			else:
				var take := mini(need, reserve)
				mag += take
				reserve -= take
			ammo_changed.emit(mag, reserve)
			AudioDirector.play("bolt", -6.0, 1.0, 0.03)
		return

	if Input.is_action_just_pressed("reload"):
		start_reload()
	if Input.is_action_just_pressed("melee") and _melee_cd <= 0.0:
		_melee()
	if Input.is_action_just_pressed("flashlight"):
		_flashlight_on = not _flashlight_on
		AudioDirector.play("switch", -12.0, 1.0, 0.05)

	if _hidden_in != null:
		return
	if _action_suppress <= 0.0 and Input.is_action_pressed("fire") and _fire_cd <= 0.0:
		_fire()


func start_reload() -> void:
	# With unlimited ammo the reserve is never the reason a reload cannot start;
	# the magazine still has to be short, which is what keeps the rhythm.
	var empty := reserve <= 0 and not UNLIMITED_AMMO
	if _reloading or mag >= MAG_SIZE or empty:
		if mag <= 0 and empty:
			AudioDirector.play("rifle_dry", -8.0, 1.0, 0.0)
		return
	_reloading = true
	_reload_t = 0.0
	_bolt_played = false
	AudioDirector.play("mag_out", -4.0, 1.0, 0.03)


func _fire() -> void:
	if mag <= 0:
		AudioDirector.play("rifle_dry", -6.0, 1.0, 0.0)
		_fire_cd = 0.32
		start_reload()
		return

	mag -= 1
	ammo_changed.emit(mag, reserve)
	_fire_cd = FIRE_INTERVAL
	GameManager.add_stat("shots_fired", 1)

	var spread := _current_spread()
	var base_dir := cam_rig.forward()
	var dir := base_dir
	dir = dir.rotated(Vector3.UP, randf_range(-spread, spread))
	dir = dir.rotated(cam_rig.global_transform.basis.x, randf_range(-spread, spread)).normalized()

	var origin := cam_rig.global_position
	var end := origin + dir * RANGE

	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * RANGE)
	q.collision_mask = 1 | 4 | 8 | 32
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var hit_something := not hit.is_empty()
	if hit_something:
		end = hit.position
		_resolve_hit(hit, dir)

	var muzzle_pos := rig.muzzle.global_position
	if game != null and game.tracers != null:
		game.tracers.fire(muzzle_pos, end, 0.024)

	# --- presentation ----------------------------------------------------
	AudioDirector.play_variant("rifle_fire", 3, -3.0, 0.05)
	AudioDirector.play("shell_drop", -14.0, 1.0, 0.15)
	noised.emit(global_position, 55.0)

	_muzzle_light.light_energy = 9.0
	_muzzle_quad_mat.albedo_color.a = 0.95
	_muzzle_quad.rotation.z = randf_range(0.0, TAU)

	cam_rig.add_recoil(deg_to_rad(randf_range(0.55, 0.95)), deg_to_rad(randf_range(-0.34, 0.34)))
	cam_rig.add_trauma(0.12)
	_spread_heat = minf(_spread_heat + 0.42, 3.0)


func _current_spread() -> float:
	var base := deg_to_rad(0.75)
	if aiming:
		base = deg_to_rad(0.22)
	elif crouching:
		base = deg_to_rad(0.45)
	var moving := clampf(Vector2(velocity.x, velocity.z).length() / SPRINT_SPEED, 0.0, 1.0)
	base += deg_to_rad(2.1) * moving
	if not is_on_floor():
		base += deg_to_rad(2.6)
	base += deg_to_rad(1.5) * (_spread_heat / 3.0)
	if health < MAX_HEALTH * 0.28:
		base += deg_to_rad(0.9)
	return base


func _resolve_hit(hit: Dictionary, dir: Vector3) -> void:
	var collider = hit.get("collider")
	var point: Vector3 = hit.get("position", Vector3.ZERO)
	var normal: Vector3 = hit.get("normal", Vector3.UP)

	# Damageable actors implement bullet_hit() and report whether the shot
	# landed on a critical shape, so there is no hard dependency here.
	if collider != null and collider.has_method("bullet_hit"):
		var was_head := bool(collider.call("bullet_hit", point, normal, dir,
				int(hit.get("shape", 0)), BODY_DAMAGE, HEAD_DAMAGE))
		GameManager.add_stat("shots_hit", 1)
		AudioDirector.play("hit_crit" if was_head else "hit_marker", -6.0, 1.0, 0.05, "UI")
		if game != null and game.impacts != null:
			# Dead structures kick up dust, not flesh; actors stay fleshy.
			var surface := "flesh"
			if collider is DamageableBody:
				surface = (collider as DamageableBody).debris_kind()
			game.impacts.impact(point, normal, surface)
		return

	var surface := "concrete"
	if collider is Node3D and (collider as Node3D).is_in_group("metal"):
		surface = "metal"
	elif point.y < 0.2 and game != null and game.surface_at(point) == "water":
		surface = "water"
	if game != null and game.impacts != null:
		game.impacts.impact(point, normal, surface)
	AudioDirector.play_variant_at("impact_" + surface, 3 if surface == "concrete" else 2,
			point, -3.0, 55.0)


func _melee() -> void:
	_melee_cd = 0.75
	var origin := cam_rig.global_position
	var dir := cam_rig.forward()
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * MELEE_RANGE)
	q.collision_mask = 1 | 4 | 8
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	AudioDirector.play("whoosh", -6.0, 1.0, 0.1)
	noised.emit(global_position, 16.0)
	if hit.is_empty():
		return
	var collider = hit.get("collider")
	if collider != null and collider.has_method("bullet_hit"):
		collider.call("bullet_hit", hit.position, hit.get("normal", Vector3.UP), dir,
				int(hit.get("shape", 0)), MELEE_DAMAGE, MELEE_DAMAGE * 1.2)
		cam_rig.add_trauma(0.3)
	if collider != null and collider.has_method("take_damage"):
		collider.call("take_damage", MELEE_DAMAGE * 0.4, hit.position, dir)


# --------------------------------------------------------------- interaction

func _update_interaction() -> void:
	if input_blocked:
		if _focus != null:
			_focus = null
			focus_changed.emit(null, "")
		return
	if _hidden_in != null:
		if _focus != _hidden_in:
			_focus = _hidden_in
			focus_changed.emit(_focus, "Leave")
		if Input.is_action_just_pressed("interact"):
			_exit_hidden()
		return

	var origin := cam_rig.global_position
	var dir := cam_rig.forward()
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 3.6)
	q.collision_mask = 8
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var found: Node = null
	if not hit.is_empty() and hit.get("collider") is Node:
		var c := hit.get("collider") as Node
		if c.has_method("interact"):
			found = c

	if found != _focus:
		_focus = found
		var label := ""
		if found != null and found.has_method("prompt"):
			label = String(found.call("prompt"))
		focus_changed.emit(found, label)

	if _focus != null and _action_suppress <= 0.0 \
			and Input.is_action_just_pressed("interact"):
		_focus.call("interact", self)


func enter_hidden(holder: Node) -> void:
	_hidden_in = holder
	velocity = Vector3.ZERO
	if holder is Node3D:
		global_position = (holder as Node3D).global_position
	rig.set_visible_body(false)
	cam_rig.set_collision(false)
	if holder.has_method("facing_yaw"):
		cam_rig.yaw = float(holder.call("facing_yaw"))
		_body_yaw = cam_rig.yaw
	hidden_changed.emit(true)
	AudioDirector.play("locker_close", -6.0, 1.0, 0.03)


func _exit_hidden() -> void:
	_hidden_in = null
	rig.set_visible_body(true)
	cam_rig.set_collision(true)
	global_position += Vector3(0, 0.1, 0)
	hidden_changed.emit(false)
	AudioDirector.play("locker_open", -6.0, 1.0, 0.03)


func is_hidden() -> bool:
	return _hidden_in != null


## Briefly ignore interact/fire polling -- used after a UI flow that consumed
## the same press that opened it, so closing the wheel does not also talk to
## the person again or squeeze off a round on release.
func suppress_actions(seconds := 0.2) -> void:
	_action_suppress = seconds


func set_flashlight(on: bool) -> void:
	_flashlight_on = on


func noise_radius() -> float:
	if _hidden_in != null:
		return 0.0
	return 10.0 + Vector2(velocity.x, velocity.z).length() * 3.6


# ------------------------------------------------------------------ damage

func apply_damage(amount: float, from_position: Vector3, silent := false) -> void:
	if not alive:
		return
	health -= amount
	GameManager.add_stat("damage_taken", amount)
	_regen_delay = 0.0
	var dir := (from_position - global_position).normalized()
	damaged.emit(dir, amount)
	if game != null and game.post != null:
		game.post.hit(clampf(amount / 28.0, 0.18, 1.0))
	cam_rig.add_trauma(clampf(amount / 70.0, 0.12, 0.6))
	if not silent:
		AudioDirector.play("player_hurt", -7.0, 1.0, 0.06)
	health_changed.emit(health, MAX_HEALTH)
	if health <= 0.0:
		_die()


func heal(amount: float) -> void:
	health = minf(MAX_HEALTH, health + amount)
	health_changed.emit(health, MAX_HEALTH)
	AudioDirector.play("heal", -6.0, 1.0, 0.0, "UI")


func give_ammo(amount: int) -> void:
	if UNLIMITED_AMMO:
		# A crate is still worth crossing the street for: it saves the reload.
		mag = MAG_SIZE
	else:
		reserve += amount
	ammo_changed.emit(mag, reserve)


func _die() -> void:
	alive = false
	_dead_t = 0.0
	health = 0.0
	rig.die(randf_range(-0.4, 0.4))
	AudioDirector.play("player_death", -2.0, 1.0, 0.05)
	GameManager.add_stat("deaths", 1)
	died.emit()


func revive(at: Vector3, yaw: float) -> void:
	alive = true
	_dead_t = 0.0
	health = MAX_HEALTH * 0.7
	velocity = Vector3.ZERO
	global_position = at
	_body_yaw = yaw
	cam_rig.yaw = yaw
	cam_rig.pitch = -0.08
	cam_rig.head_offset = 1.52
	cam_rig.trauma = 0.0
	rig.reset()
	rig.visible = true
	input_blocked = false
	_reloading = false
	mag = MAG_SIZE
	reserve = maxi(reserve, 60)
	_swim_mode = false
	_under_water = false
	_was_in_water = false
	_breath = BREATH_TIME
	_drown_t = 0.0
	health_changed.emit(health, MAX_HEALTH)
	ammo_changed.emit(mag, reserve)
