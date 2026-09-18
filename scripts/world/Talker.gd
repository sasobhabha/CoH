class_name Talker
extends Interactable
## A person you can talk to.  Pressing E raises the radial wheel so the player
## chooses inspect / talk / wait / leave, exactly like the reference footage.

signal option_chosen(id: String)

var options: Array = [
	{"id": "talk", "label": "Talk", "hint": "ask about the road"},
	{"id": "inspect", "label": "Inspect", "hint": "look them over"},
	{"id": "wait", "label": "Wait", "hint": "let the moment pass"},
	{"id": "leave", "label": "Leave", "hint": "step away"},
]
var rig: HumanoidRig
var caption := ""
var _busy := false
var _yaw := 0.0


func setup(pos: Vector3, facing_deg: float, pal := {}) -> void:
	position = pos
	rotation.y = deg_to_rad(facing_deg)
	_yaw = rotation.y
	label = "Talk"
	caption = ""


func build_body(pal := {}) -> void:
	rig = HumanoidRig.new()
	rig.name = "Rig"
	add_child(rig)
	if pal.is_empty():
		pal = {
			"primary": MatLib.painted(Color("4a4038"), "npc_coat"),
			"secondary": MatLib.painted(Color("2a2622"), "npc_under"),
			"accent": MatLib.painted(Color("7a5a2b"), "npc_accent"),
			"skin": MatLib.painted(Color("7d6144"), "npc_skin"),
			"bulk": 0.98,
		}
	# Nobody wandering this city wears armour, so every Talker is a civilian
	# unless a caller asks for something else.
	if not pal.has("model"):
		pal["model"] = "civilian"
	rig.build(pal)

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4 * rig.stature
	cap.height = 1.7 * rig.stature
	cs.shape = cap
	cs.position.y = 0.9 * rig.stature
	add_child(cs)


func _process(delta: float) -> void:
	if rig != null:
		rig.update(delta, {"speed": 0.0, "max_speed": 4.0, "aiming": false})
		rig.tick_flash(delta)


func prompt() -> String:
	if _busy:
		return ""
	return label


func listen(rig_t := 0.0) -> void:
	## Face the player while they talk to us.
	if rig != null:
		rig.rotation.y = 0.0


func interact(player: Node) -> void:
	if _busy:
		return
	_busy = true
	var game = player.get("game")
	if game != null and game.has_method("open_radial"):
		game.call("open_radial", options, caption, func(id: String):
			_busy = false
			option_chosen.emit(id))
	else:
		_busy = false
		option_chosen.emit("talk")
