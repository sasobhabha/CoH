extends SceneTree
## Dump what the environment GLBs actually contain once Godot has imported them.
##
##     godot --headless --path . --script res://tools/inspect_env.gd
##
## The Blender export writes one glTF *primitive per material*, so a piece
## arrives as a handful of MeshInstance3D nodes and not as one mesh.  Collision
## filtering and material tinting both depend on that structure, so it is worth
## looking at rather than assuming.

const PIECES := ["monument", "balloon", "checkpoint", "banner", "billboard"]


func _initialize() -> void:
	for piece in PIECES:
		var path := "res://assets/environment/%s.glb" % piece
		var ps: PackedScene = load(path)
		if ps == null:
			print("== %s  !! failed to load" % piece)
			continue
		var root: Node3D = ps.instantiate()
		print("== %s  root=%s  children=%d" % [piece, root.get_class(),
				root.get_child_count()])
		_walk(root, 1)
		root.free()
	quit()


func _walk(n: Node, depth: int) -> void:
	var pad := "   ".repeat(depth)
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		var mats: Array = []
		for s in mesh.get_surface_count():
			var m := mi.get_active_material(s)
			mats.append(m.resource_name if m != null else "?")
		var faces := mesh.get_faces()
		var aabb := mi.transform * mesh.get_aabb()
		print("%s%s  [%s]  verts=%d mats=%s  xf=%s  aabb=%s" % [pad, mi.name,
				mesh.get_class(), faces.size(),
				",".join(PackedStringArray(mats)), str(mi.transform),
				str(aabb)])
	else:
		print("%s%s  [%s]" % [pad, n.name, n.get_class()])
	for c in n.get_children():
		_walk(c, depth + 1)
