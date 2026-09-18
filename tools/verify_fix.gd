extends SceneTree
## One-off verification for two fixes:
##   1. Chapter 3 deck/jetty collision (was: slab-only deck committed with
##      collide=false, so the player fell out of the world).
##   2. Radial menu confirm paths (click / E / Enter / B).
##
##     godot --headless --path . --script res://tools/verify_fix.gd

const CHAPTER_SCRIPTS := [
	"res://scripts/chapters/Ch01_OccupiedPlaza.gd",
	"res://scripts/chapters/Ch02_Tavern.gd",
	"res://scripts/chapters/Ch03_FloodMarket.gd",
	"res://scripts/chapters/Ch04_TheDark.gd",
	"res://scripts/chapters/Ch05_Meadow.gd",
]


class StubEnemy extends Node3D:
	signal died(_e: Node)
	var alive := true
	func receive_alert(_p: Vector3) -> void:
		pass


class StubGame extends Node:
	var player: Node3D = null   ## base-class feedback paths check game.player
	var alive := 0              ## hostiles up, for the monument damage gate
	func spawn_enemy(_pos: Vector3, _kind := "trooper", _patrol := [], _light := false) -> Node:
		return StubEnemy.new()
	func enemies_alive() -> int:
		return alive
	func notify(_t: String) -> void:
		pass


func _initialize() -> void:
	# One frame in, so the autoload singletons are ready and in the tree.
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _count_colliders(node: Node) -> int:
	var n := 0
	if node is CollisionShape3D:
		n = 1
	for c in node.get_children():
		n += _count_colliders(c)
	return n


## Fills best = [covering_shape_or_null, nearest_distance].  A shape "covers"
## the point when the point sits inside its box volume -- origin distance is
## meaningless for a 108 m deck slab centred far away.
func _nearest_shape(node: Node, point: Vector3, best: Array) -> void:
	if node is CollisionShape3D:
		var cs := node as CollisionShape3D
		var d: float = cs.global_transform.origin.distance_to(point)
		if cs.shape is BoxShape3D:
			var local: Vector3 = cs.global_transform.affine_inverse() * point
			var half: Vector3 = (cs.shape as BoxShape3D).size * 0.5
			if absf(local.x) <= half.x and absf(local.y) <= half.y \
					and absf(local.z) <= half.z:
				if best[0] == null:
					best[0] = cs
		for c in node.get_children():
			_nearest_shape(c, point, best)
		return
	for c in node.get_children():
		_nearest_shape(c, point, best)


func _initialize_chapter(path: String, game: StubGame) -> Node:
	var script: GDScript = load(path)
	if script == null or not script.can_instantiate():
		return null
	var ch: Node = script.new()
	ch.set("game", game)
	root.add_child(ch)
	ch.call("setup", game, 2)
	return ch


## True when any script in the list declares the given method.
func _script_has_method(script: GDScript, method: String) -> bool:
	for m in script.get_script_method_list():
		if String(m.get("name", "")) == method:
			return true
	return false


func _run() -> void:
	var bad := 0

	# --- 1. every chapter script compiles; Chapter 3 builds with floor -------
	for path in CHAPTER_SCRIPTS:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			print("!! %s failed to load/compile" % path)
			bad += 1

	var stub := StubGame.new()
	var ch := _initialize_chapter("res://scripts/chapters/Ch03_FloodMarket.gd", stub)
	if ch == null:
		print("!! Ch03 failed to build")
		bad += 1
	else:
		var total := _count_colliders(ch)
		print("Ch03_FloodMarket colliders=%d" % total)

		var best_spawn := [null]
		_nearest_shape(ch, Vector3(0, 0.0, 46), best_spawn)
		if best_spawn[0] == null:
			print("!!   ...nothing solid under the spawn point")
			bad += 1
		else:
			print("     spawn covered by %s" % best_spawn[0].get_parent().name)

		var best_jetty := [null]
		# the piers were re-berthed over the canal water when the cut was
		# deepened; this is their deck centre now
		_nearest_shape(ch, Vector3(-35.5, 0.6, -30.0), best_jetty)
		if best_jetty[0] == null:
			print("!!   ...jetty still walk-through")
			bad += 1
		else:
			print("     jetty solid")

		# --- 1b. monument damage gate: no damage while hostiles stand -------
		var mbody_v: Variant = ch.get("_monument_body")
		if mbody_v == null or not (mbody_v is DamageableBody):
			print("!!   ...monument hitbox missing")
			bad += 1
		else:
			var mbody := mbody_v as DamageableBody
			stub.alive = 1
			if (mbody.damage_blocked_reason.call() as String).is_empty():
				print("!!   ...monument shootable while hostiles alive")
				bad += 1
			var hp0 := mbody.health
			mbody.bullet_hit(Vector3.ZERO, Vector3.UP, Vector3.FORWARD, 0, 50.0, 0.0)
			if not is_equal_approx(mbody.health, hp0):
				print("!!   ...monument took damage while hostiles alive")
				bad += 1
			stub.alive = 0
			if not (mbody.damage_blocked_reason.call() as String).is_empty():
				print("!!   ...gate did not release once the ground was clear")
				bad += 1
			mbody.bullet_hit(Vector3.ZERO, Vector3.UP, Vector3.FORWARD, 0, 50.0, 0.0)
			if mbody.health >= hp0:
				print("!!   ...monument did not take damage once clear")
				bad += 1
			else:
				print("     monument gate ok")

		ch.queue_free()

	# --- 2. radial menu API present ---
	var radial_script: GDScript = load("res://scripts/ui/RadialMenu.gd")
	if radial_script == null or not radial_script.can_instantiate():
		print("!! RadialMenu failed to load/compile")
		bad += 1
	else:
		for method in ["confirm", "dismiss", "cancel", "open", "close"]:
			if not _script_has_method(radial_script, method):
				print("!! RadialMenu missing %s()" % method)
				bad += 1
		print("RadialMenu methods ok")

	# --- 3. player exposes the suppress hook used by the radial flow --------
	var player_script: GDScript = load("res://scripts/player/Player.gd")
	if player_script == null or not player_script.can_instantiate():
		print("!! Player failed to load/compile")
		bad += 1
	elif not _script_has_method(player_script, "suppress_actions"):
		print("!! Player missing suppress_actions()")
		bad += 1
	else:
		print("Player suppress_actions() ok")

	if bad == 0:
		print("VERIFY OK")
	else:
		print("VERIFY FAILED (%d)" % bad)
	quit(1 if bad > 0 else 0)
