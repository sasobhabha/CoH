class_name EnvKit
extends RefCounted
## The occupied city's hero pieces, authored in Blender by `tools/gen_env.py`.
##
## Everything *modular* in this game is procedural: `Kit.gd` draws facades,
## barriers, tents and props straight into merged meshes, which is why a whole
## district costs under a thousand draw calls.  These five pieces are the ones
## with a silhouette worth authoring by hand -- the pale monument the plaza is
## built around, the tethered portrait balloon hanging over it, the checkpoint
## gate you walk through, the hung banner, and a billboard.
##
## Each GLB is a single `ArrayMesh` with one *surface per material* (Godot
## merges the glTF primitives on import), standing on `y = 0` and facing `-Z`,
## because Blender's +Y is glTF's -Z.  So a piece is placed with a position and
## a yaw and needs no per-piece correction.
##
## Collision is generated here rather than baked, and it is filtered per
## triangle: a tethered balloon's only solid part is the mooring rig at the
## bottom of it, and a trimesh of the envelope 50 m up is 6 000 triangles of
## nothing a player can ever touch.

const PIECES := {
	"monument": "res://assets/environment/monument.glb",
	"balloon": "res://assets/environment/balloon.glb",
	"checkpoint": "res://assets/environment/checkpoint.glb",
	"banner": "res://assets/environment/banner.glb",
	"billboard": "res://assets/environment/billboard.glb",
}

## Material names whose geometry is decorative: cloth, glass and lamp lenses.
## Colliding with a hanging banner feels like walking into a pane of glass, and
## a lamp lens is 6 cm of nothing.
const SOFT := ["env_red", "env_red_dark", "env_portrait", "env_glass", "env_lamp"]

static var _scenes := {}
static var _bounds := {}


static func load_piece(piece: String) -> PackedScene:
	if _scenes.has(piece):
		return _scenes[piece]
	var path: String = PIECES.get(piece, "")
	if path.is_empty():
		push_error("EnvKit: no such piece '%s' (have %s)"
				% [piece, ", ".join(PackedStringArray(PIECES.keys()))])
		return null
	var ps: PackedScene = load(path)
	if ps == null:
		push_error("EnvKit: could not load %s -- run tools/gen_env.py" % path)
		return null
	_scenes[piece] = ps
	return ps


## Place a piece.  `opts` may carry:
##   `collide`  bool   -- build a static trimesh body (default true)
##   `below`    float  -- only triangles under this height collide (default inf)
##   `skip`     Array  -- extra material-name prefixes to leave non-solid
##   `name`     String -- node name (defaults to the piece name)
##   `scale`    float  -- uniform scale for the whole piece (default 1.0)
static func place(parent: Node3D, piece: String, pos: Vector3, yaw := 0.0,
		opts := {}) -> Node3D:
	var ps := load_piece(piece)
	if ps == null:
		return null
	var root: Node3D = ps.instantiate()
	root.name = String(opts.get("name", piece))
	root.position = pos
	root.rotation.y = deg_to_rad(yaw)
	parent.add_child(root)
	# Scale the top-level children rather than the root: the baked trimesh
	# collision reads each mesh's transform, so the scale lands in the vertices
	# and the shape stays an honest, unscaled concave polygon.
	var s := float(opts.get("scale", 1.0))
	if not is_equal_approx(s, 1.0):
		for c in root.get_children():
			if c is Node3D:
				(c as Node3D).scale = (c as Node3D).scale * s
	if bool(opts.get("collide", true)):
		var below := float(opts.get("below", INF))
		var skip: Array = opts.get("skip", [])
		_build_collision(root, below, skip)
	return root


## The piece's local bounding box, measured from the mesh once.
static func bounds(piece: String) -> AABB:
	if _bounds.has(piece):
		return _bounds[piece]
	var ps := load_piece(piece)
	if ps == null:
		return AABB()
	var n: Node3D = ps.instantiate()
	var box := _mesh_aabb(n)
	n.free()
	_bounds[piece] = box
	return box


static func height(piece: String) -> float:
	return bounds(piece).size.y


static func _mesh_aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out = (n as MeshInstance3D).transform * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for c in n.get_children():
		var b := _mesh_aabb(c)
		if b.size == Vector3.ZERO:
			continue
		out = b if first else out.merge(b)
		first = false
	return out


# ------------------------------------------------------------------ collision

static func _build_collision(root: Node3D, below: float, skip: Array) -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	root.add_child(body)
	var total := 0
	# The array is typed on purpose.  Iterating an untyped Array gives `mi` the
	# Variant type, and `var x := mi.transform` then cannot infer -- which is a
	# parse error, so the whole class fails to load and every caller of it fails
	# with it, hundreds of lines away from the mistake.
	for mi in _meshes(root):
		var mesh: ArrayMesh = mi.mesh as ArrayMesh
		if mesh == null:
			continue
		var xf: Transform3D = mi.transform
		for s in mesh.get_surface_count():
			var mat: Material = mi.get_active_material(s)
			var mname: String = "" if mat == null else mat.resource_name
			if _is_soft(mname, skip):
				continue
			var faces := _surface_faces(mesh, s)
			if below < INF:
				faces = _clip_above(faces, below)
			if faces.is_empty():
				continue
			var shape := ConcavePolygonShape3D.new()
			if xf != Transform3D.IDENTITY:
				for i in faces.size():
					faces[i] = xf * faces[i]
			shape.set_faces(faces)
			var cs := CollisionShape3D.new()
			cs.name = "Shape_%s_%d" % [mname, s]
			cs.shape = shape
			body.add_child(cs)
			total += faces.size() / 3
	if total == 0:
		# A piece with no collision is a piece you walk through, which is a
		# silent level-design bug rather than a crash.
		push_warning("EnvKit: %s produced no collision triangles" % root.name)
	body.set_meta("tris", total)


static func _is_soft(mname: String, skip: Array) -> bool:
	for p in SOFT:
		if mname.begins_with(p):
			return true
	for p in skip:
		if mname.begins_with(String(p)):
			return true
	return false


static func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


## Triangles of one surface, as a plain vertex soup (what a trimesh shape wants).
static func _surface_faces(mesh: ArrayMesh, s: int) -> PackedVector3Array:
	var arrays := mesh.surface_get_arrays(s)
	if arrays.is_empty():
		return PackedVector3Array()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var out := PackedVector3Array()
	if arrays[Mesh.ARRAY_INDEX] == null:
		out.resize(verts.size())
		for i in verts.size():
			out[i] = verts[i]
		return out
	var pid: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if pid.is_empty():
		return verts
	out.resize(pid.size())
	for i in pid.size():
		out[i] = verts[pid[i]]
	return out


## Keep only the triangles that sit entirely below `limit`.
static func _clip_above(faces: PackedVector3Array, limit: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var i := 0
	while i + 2 < faces.size():
		if faces[i].y <= limit and faces[i + 1].y <= limit and faces[i + 2].y <= limit:
			out.append(faces[i])
			out.append(faces[i + 1])
			out.append(faces[i + 2])
		i += 3
	return out
