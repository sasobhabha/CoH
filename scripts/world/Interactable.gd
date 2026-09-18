class_name Interactable
extends StaticBody3D
## Anything the player can look at and press E on.
##
## Lives on the interactable physics layer so the player's focus ray only ever
## sees these, and exposes `prompt()` / `interact()` as the duck-typed contract.

signal interacted(player: Node)

var label := "Inspect"
var enabled := true
var size := Vector3(0.6, 1.0, 0.6)


func _ready() -> void:
	collision_layer = 8      # interactable
	collision_mask = 0
	if get_child_count() == 0 or _has_no_shape():
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		add_child(cs)


func _has_no_shape() -> bool:
	for c in get_children():
		if c is CollisionShape3D:
			return false
	return true


func prompt() -> String:
	return label if enabled else ""


func interact(player: Node) -> void:
	if not enabled:
		return
	AudioDirector.play("ui_click", -8.0, 1.0, 0.0, "UI")
	interacted.emit(player)
