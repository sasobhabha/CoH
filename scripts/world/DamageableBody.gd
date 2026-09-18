class_name DamageableBody
extends StaticBody3D
## A shootable piece of the world.
##
## The player's hitscan only offers damage to things that answer
## `bullet_hit()`, and the authored GLB pieces come through EnvKit as plain
## static collision.  Anything that should react to being shot therefore needs
## one of these wrapped around it: an invisible box on the shootable layer
## (32) that soaks the damage and raises `destroyed` when it breaks.
##
## The body is deliberately movement-free: it sits on layer 32 only, so
## walking, enemy sight and interactions ignore it and the authored geometry
## underneath keeps doing that job.  Size it a hand's width larger than the
## visual surface so hitscan reaches the box before the static mesh.

signal damaged(amount: float, point: Vector3)
signal destroyed
## Raised when a hit is refused by `damage_blocked_reason` (point = hit point).
signal blocked(point: Vector3)

@export var health := 100.0
## Which impact puff the player's rifle kicks up on hits ("concrete", "metal").
@export var debris_impact := "concrete"
## Optional damage gate.  When valid, it is called on every hit; a non-empty
## String result refuses the damage outright (health untouched, no signals
## raised except `blocked`), an empty one lets it through.
var damage_blocked_reason := Callable()


## Box hit volume, positioned in this body's local space.  Call after adding
## the body to its parent so the shape exists before the first shot.
func make_box(size: Vector3, centre: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.name = "HitBox"
	cs.shape = shape
	cs.position = centre
	add_child(cs)
	collision_layer = 32          # shootable only
	collision_mask = 0


## Damage entry point shared with the player's hitscan.  Never reports a
## critical: structures have no heads.
func bullet_hit(_point: Vector3, _normal: Vector3, _dir: Vector3, _shape: int,
		body_damage: float, _head_damage: float) -> bool:
	if health <= 0.0:
		return false
	if damage_blocked_reason.is_valid():
		var reason: String = damage_blocked_reason.call()
		if not reason.is_empty():
			blocked.emit(_point)
			return false
	health -= body_damage
	damaged.emit(body_damage, _point)
	if health <= 0.0:
		destroyed.emit()
	return false


## Lets the shooter pick a surface-appropriate impact effect.
func debris_kind() -> String:
	return debris_impact
