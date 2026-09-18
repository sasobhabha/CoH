class_name CameraRig
extends Camera3D
## Third-person camera.
##
## Positions itself from a target each frame: yaw/pitch from look input, an arm
## that swings out behind the target and is pulled in by geometry (three rays,
## so it does not clip corners), a shoulder offset that grows when aiming, and
## trauma-based shake.  Recoil is a separate spring so firing does not fight
## the player's own aim.

var target: Node3D
var head_offset := 1.52
var yaw := 0.0
var pitch := -0.10

var arm := 3.05
var arm_aim := 1.95
var shoulder := 0.46
var shoulder_aim := 0.82

var fov_base := 78.0
var fov_aim := 54.0
var fov_sprint := 85.0
var fov_scale_speed := 7.0

var trauma := 0.0
var recoil_pitch := 0.0
var recoil_yaw := 0.0

var pitch_min := -1.15
var pitch_max := 0.85

var _arm_current := 3.5
var _fov := 78.0
var _shake_t := 0.0
var _noise := Vector3.ZERO
var _collide := true


func setup(target_node: Node3D, fov: float) -> void:
	target = target_node
	fov_base = fov
	_fov = fov
	fov = fov
	near = 0.08
	far = 600.0
	top_level = true
	_arm_current = arm


func look(relative: Vector2) -> void:
	yaw -= relative.x
	pitch = clampf(pitch - relative.y, pitch_min, pitch_max)


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func add_recoil(pitch_amount: float, yaw_amount: float) -> void:
	recoil_pitch += pitch_amount
	recoil_yaw += yaw_amount


func update(delta: float, aiming: bool, sprinting: bool, occupied := false) -> void:
	# --- recover spring --------------------------------------------------
	recoil_pitch = lerpf(recoil_pitch, 0.0, minf(1.0, delta * 7.0))
	recoil_yaw = lerpf(recoil_yaw, 0.0, minf(1.0, delta * 7.0))
	trauma = maxf(0.0, trauma - delta * 1.35)

	var desired_arm := arm_aim if aiming else arm
	if occupied:
		desired_arm = 0.02
	var target_arm := desired_arm
	var desired_shoulder := shoulder_aim if aiming else shoulder
	var shake_amount := trauma * trauma * float(Settings.getv("camera_shake"))

	_shake_t += delta * 22.0
	_noise = Vector3(
			_wobble(_shake_t, 0.0),
			_wobble(_shake_t, 13.7),
			_wobble(_shake_t, 29.1))

	var basis := Basis.from_euler(Vector3(pitch + recoil_pitch, yaw + recoil_yaw, 0.0))
	var origin := Vector3.ZERO
	if target != null:
		origin = target.global_position + Vector3(0, head_offset, 0)
	var pivot := origin + basis.x * desired_shoulder
	var back := basis.z

	# --- pull the arm in when geometry is in the way ---------------------
	if _collide and not occupied:
		var worst := target_arm
		for side: float in [-0.42, 0.0, 0.42]:
			var from := pivot + basis.x * side
			var to := from + back * target_arm
			var q := PhysicsRayQueryParameters3D.create(from, to)
			q.collision_mask = 1
			if target is CollisionObject3D:
				q.exclude = [(target as CollisionObject3D).get_rid()]
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			if hit.is_empty():
				continue
			var dist: float = from.distance_to(hit.position) - 0.22
			worst = minf(worst, maxf(dist, 0.35))
		target_arm = worst

	var rate := 26.0 if target_arm < _arm_current else 5.0
	_arm_current = lerpf(_arm_current, target_arm, minf(1.0, delta * rate))

	var final_pos := pivot + back * _arm_current
	final_pos += basis.x * _noise.x * shake_amount * 0.22
	final_pos += basis.y * _noise.y * shake_amount * 0.22
	final_pos += back * _noise.z * shake_amount * 0.14

	var shaken := Basis.from_euler(Vector3(
			pitch + recoil_pitch + _noise.y * shake_amount * 0.045,
			yaw + recoil_yaw + _noise.x * shake_amount * 0.045,
			_noise.z * shake_amount * 0.05))
	global_transform = Transform3D(shaken, final_pos)

	# --- fov -------------------------------------------------------------
	var want_fov := fov_aim if aiming else (fov_sprint if sprinting else fov_base)
	_fov = lerpf(_fov, want_fov, minf(1.0, delta * fov_scale_speed))
	fov = _fov


func _wobble(t: float, seed_v: float) -> float:
	## Cheap smooth noise in [-1, 1].
	return sin(t * 1.7 + seed_v) * 0.6 + sin(t * 3.9 + seed_v * 2.3) * 0.4


func forward() -> Vector3:
	return -global_transform.basis.z


func aim_point(distance := 200.0) -> Vector3:
	return global_position + forward() * distance


func set_collision(enabled: bool) -> void:
	_collide = enabled
