class_name Locker
extends Interactable
## A steel locker the player can climb into.
##
## While concealed the player is invisible to enemy vision and their camera
## sits inside the cabinet looking out, which is the whole stealth verb.

var door: Node3D
var _open := false
var _eye := Vector3.ZERO
var _yaw := 0.0
var _interior_light: OmniLight3D


func setup(pos: Vector3, yaw_deg: float, height := 1.95) -> void:
	# called before the node enters the tree, so this is a local transform
	position = pos
	rotation.y = deg_to_rad(yaw_deg)
	_yaw = rotation.y
	label = "Hide"
	_build(height)


func facing_yaw() -> float:
	return _yaw


func _build(height: float) -> void:
	var w := 0.78
	var d := 0.62
	var steel := MatLib.metal()
	var dark := MatLib.metal_dark()

	# shell: back, sides, top, bottom, shelf
	Build.box(self, Vector3(w, height, 0.06), Vector3(0, height * 0.5, d * 0.5), steel, Vector3.ZERO, false)
	Build.box(self, Vector3(0.06, height, d), Vector3(-w * 0.5, height * 0.5, 0), steel, Vector3.ZERO, false)
	Build.box(self, Vector3(0.06, height, d), Vector3(w * 0.5, height * 0.5, 0), steel, Vector3.ZERO, false)
	Build.box(self, Vector3(w, 0.06, d), Vector3(0, height, 0), dark, Vector3.ZERO, false)
	Build.box(self, Vector3(w, 0.05, d), Vector3(0, 0.02, 0), dark, Vector3.ZERO, false)

	# collision: one box the player cannot walk through, plus a blocker so the
	# body never clips out the back while concealed
	var solid := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, height, d)
	solid.shape = box
	solid.position = Vector3(0, height * 0.5, 0)
	add_child(solid)
	size = Vector3(w, height, d)

	# door, hinged on the left edge
	var hinge := Node3D.new()
	hinge.position = Vector3(-w * 0.5, 0, -d * 0.5)
	add_child(hinge)
	Build.box(hinge, Vector3(w, height * 0.94, 0.05), Vector3(w * 0.5, height * 0.5, 0), steel,
			Vector3.ZERO, false)
	Build.box(hinge, Vector3(0.10, 0.05, 0.04), Vector3(w - 0.12, height * 0.52, -0.04),
			MatLib.metal_rust(), Vector3.ZERO, false)
	for row in 3:
		Build.box(hinge, Vector3(w * 0.62, 0.02, 0.02),
				Vector3(w * 0.5, height * (0.34 + row * 0.16), -0.04), dark, Vector3.ZERO, false)
	door = hinge

	_eye = Vector3(0, height * 0.62, 0.02)
	_interior_light = Build.omni(self, Vector3(0, height * 0.75, 0.05), Color("ffce9a"),
			0.35, 2.4, false, 0.4)


func interact(player: Node) -> void:
	if _open:
		return
	_open = true
	var t := create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(door, "rotation:y", deg_to_rad(-104.0), 0.45)
	if _interior_light != null:
		_interior_light.light_energy = 1.6
	label = "Leave"
	player.call("enter_hidden", self)
	interacted.emit(player)


func release() -> void:
	if not _open:
		return
	_open = false
	var t := create_tween()
	t.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(door, "rotation:y", 0.0, 0.4)
	if _interior_light != null:
		_interior_light.light_energy = 0.35
	label = "Hide"


func eye_position() -> Vector3:
	return global_position + Vector3(0, _eye.y, 0).rotated(Vector3.UP, _yaw)
