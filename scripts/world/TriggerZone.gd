class_name TriggerZone
extends Area3D
## One-shot volume trigger for objectives, ambushes and chapter exits.

signal entered(player: Node)

var once := true
var _fired := false
var tag := ""


static func make(parent: Node3D, pos: Vector3, size: Vector3, tag_name := "",
		trigger_once := true) -> TriggerZone:
	var t := TriggerZone.new()
	t.tag = tag_name
	t.once = trigger_once
	t.position = pos
	t.collision_layer = 16
	t.collision_mask = 2          # player only
	t.monitoring = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	t.add_child(cs)
	parent.add_child(t)
	return t


func _ready() -> void:
	body_entered.connect(_on_body)


func _on_body(body: Node) -> void:
	if _fired and once:
		return
	if not body is CharacterBody3D:
		return
	_fired = true
	entered.emit(body)
