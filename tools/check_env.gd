extends SceneTree
## Place every environment piece and measure what actually arrived.
##
##     godot --headless --path . --script res://tools/check_env.gd
##
## Checks the three things that go wrong silently with an imported hero piece:
## it lands somewhere other than where it was asked to, its scale is not metres,
## or it gets no collision -- which is a wall you walk through, a classroom of a
## bug that reads as level design.  Nothing here needs the game to boot.

const ASKED := {
	"monument": Vector3(0.0, 0.0, -176.0),
	"balloon": Vector3(0.0, 0.0, -130.0),
	"checkpoint": Vector3(0.0, 0.0, -108.0),
	"banner": Vector3(-18.65, 0.24, 26.0),
	"billboard": Vector3(-30.0, 0.0, -132.0),
}
const EXPECTED_HEIGHT := {
	"monument": 16.92,
	"balloon": 56.03,
	"checkpoint": 7.48,
	"banner": 9.27,
	"billboard": 6.70,
}


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var bad := 0
	for piece in ASKED:
		var at: Vector3 = ASKED[piece]
		# yaw 0 here on purpose: this check compares the placed bounds against the
		# piece's own local bounds, which is exact only without a rotation.  The
		# rotated placement the chapter uses is checked by the capture run.
		var node := EnvKit.place(world, piece, at, 0.0)
		if node == null:
			print("!! %-11s FAILED TO PLACE" % piece)
			bad += 1
			continue
		var box := _world_aabb(node)
		var body := node.get_node_or_null("Collision") as StaticBody3D
		var tris := 0
		var shapes := 0
		if body != null:
			tris = int(body.get_meta("tris", 0))
			for c in body.get_children():
				if c is CollisionShape3D:
					shapes += 1
		# Cross-check against the numbers Blender reported, so a scale or axis
		# mistake in the export cannot agree with itself.
		var want: float = EXPECTED_HEIGHT[piece]
		var note := ""
		if absf(box.size.y - want) > 0.05:
			note += "  <-- HEIGHT %.2f != %.2f" % [box.size.y, want]
			bad += 1
		var want_box := EnvKit.bounds(piece)
		want_box.position += at
		if (box.position - want_box.position).length() > 0.05 \
				or (box.size - want_box.size).length() > 0.05:
			note += "  <-- PLACED WRONG (want %s at %s)" % [str(want_box.size),
					str(want_box.position)]
			bad += 1
		# The banner hangs on a wall, so it is the one piece that should be
		# off the ground; everything else must sit on it.
		if piece == "banner":
			# 1.44 m is the banner's own lowest point above its mount
			if absf(box.position.y - (1.44 + at.y)) > 0.06:
				note += "  <-- mount height %.2f" % box.position.y
				bad += 1
		elif absf(box.position.y) > 0.06:
			note += "  <-- FLOATS (lowest y %.2f)" % box.position.y
			bad += 1
		if tris == 0 and piece != "banner":
			note += "  <-- NO COLLISION"
			bad += 1
		print("%-11s at %-22s  size %-24s  shapes=%d tris=%6d%s"
				% [piece, str(at), str(box.size), shapes, tris, note])
	print("-- %d pieces, %d problem%s" % [ASKED.size(), bad,
			"" if bad == 1 else "s"])
	quit(1 if bad else 0)


func _world_aabb(node: Node3D) -> AABB:
	## `global_transform` is not usable here: this runs out of `_initialize`, before
	## the tree is up, and it returns identity with an error.  So the transforms
	## are composed by hand from the piece's own transform down.
	return _acc(node, node.transform)


func _acc(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		out = (xf * mi.transform) * mi.mesh.get_aabb()
		first = false
	for c in n.get_children():
		if not (c is Node3D):
			continue
		var b := _acc(c, xf * (c as Node3D).transform)
		if b.size == Vector3.ZERO:
			continue
		out = b if first else out.merge(b)
		first = false
	return out
