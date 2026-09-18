class_name Pickup
extends Interactable
## Ammunition crate or field dressing.  Bobs, glows, and grants on use.

var kind := "ammo"
var amount := 90
var _glow: OmniLight3D
var _body: Node3D
var _t := 0.0
var _taken := false


func setup(pos: Vector3, pickup_kind := "ammo", value := 90, rotate := 0.0) -> void:
	kind = pickup_kind
	amount = value
	position = pos
	rotation.y = rotate
	label = "Take supplies" if kind == "ammo" else "Take field dressing"
	_build()


func _build() -> void:
	_body = Node3D.new()
	_body.position.y = 0.22
	add_child(_body)

	var case_mat := MatLib.painted(Color("2f3a30"), "ammo_case")
	var accent := MatLib.emissive(Color("ffb45a"), 2.0)
	if kind == "health":
		case_mat = MatLib.painted(Color("7a2f2f"), "med_case")
		accent = MatLib.emissive(Color("ff6f6f"), 2.2)

	Build.box(_body, Vector3(0.34, 0.20, 0.24), Vector3.ZERO, case_mat, Vector3.ZERO, false)
	Build.box(_body, Vector3(0.36, 0.05, 0.26), Vector3(0, 0.10, 0), MatLib.metal_rust(),
			Vector3.ZERO, false)
	var mark := MatLib.flat(accent.emission, "pickup_mark")
	Build.box(_body, Vector3(0.20, 0.02, 0.02), Vector3(0, 0.04, -0.13), mark, Vector3.ZERO, false)
	if kind == "health":
		Build.box(_body, Vector3(0.02, 0.13, 0.02), Vector3(0, 0.04, -0.13), mark, Vector3.ZERO, false)

	_glow = Build.omni(_body, Vector3(0, 0.1, 0), accent.emission, 1.6, 3.2, false, 0.8)

	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.5, 0.4)
	cs.shape = box
	cs.position.y = 0.22
	add_child(cs)

	set_process(true)


func _process(delta: float) -> void:
	if _taken or _body == null:
		return
	_t += delta
	_body.position.y = 0.22 + sin(_t * 1.8) * 0.05
	_body.rotation.y += delta * 0.7
	if _glow != null:
		_glow.light_energy = 1.3 + sin(_t * 2.4) * 0.4


func prompt() -> String:
	return label if not _taken else ""


func interact(player: Node) -> void:
	if _taken:
		return
	_taken = true
	AudioDirector.play("pickup", -6.0, 1.0, 0.0, "UI")
	if kind == "ammo":
		if player.has_method("give_ammo"):
			player.call("give_ammo", amount)
		GameManager.toast_message("+%d ROUNDS" % amount)
	else:
		if player.has_method("heal"):
			player.call("heal", float(amount))
		GameManager.toast_message("+%d VITALS" % amount)
	interacted.emit(player)
	collision_layer = 0
	set_process(false)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_body, "position:y", _body.position.y + 0.5, 0.5)
	t.tween_property(_body, "scale", Vector3.ZERO, 0.5)
	t.chain().tween_callback(queue_free)
