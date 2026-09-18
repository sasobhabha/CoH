class_name MeshBuilder
extends RefCounted
## Bakes loose boxes, quads and prisms into one multi-surface ArrayMesh.
##
## A detailed building costs a few hundred primitives.  As nodes that is a few
## hundred draw calls and a few hundred shadow casters; as one merged mesh it is
## one of each, with every material becoming a surface.  That is the difference
## between a district made of forty grey slabs and a district made of forty
## buildings with window reveals, sills, fire escapes and rooftop plant.
##
## Colliders are accumulated separately and emitted as box shapes on a single
## StaticBody3D, so detail geometry costs no physics at all.

const AXES := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]


class Group:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	func add_tri(a: Vector3, b: Vector3, c: Vector3,
			na: Vector3, nb: Vector3, nc: Vector3,
			ua: Vector2, ub: Vector2, uc: Vector2) -> void:
		var base := verts.size()
		verts.push_back(a)
		verts.push_back(b)
		verts.push_back(c)
		norms.push_back(na)
		norms.push_back(nb)
		norms.push_back(nc)
		uvs.push_back(ua)
		uvs.push_back(ub)
		uvs.push_back(uc)
		idx.push_back(base)
		idx.push_back(base + 1)
		idx.push_back(base + 2)

	func add_quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3,
			scale: float) -> void:
		# p0..p3 wound counter-clockwise seen from the outside
		var e1 := p1 - p0
		var e2 := p3 - p0
		var ua := Vector2.ZERO
		var ub := Vector2(e1.length() * scale, 0.0)
		var uc := Vector2(e1.length() * scale, e2.length() * scale)
		var ud := Vector2(0.0, e2.length() * scale)
		add_tri(p0, p1, p2, n, n, n, ua, ub, uc)
		add_tri(p0, p2, p3, n, n, n, ua, uc, ud)


var _groups: Dictionary = {}          # Material -> Group
var _shapes: Array = []               # [{ "xf": Transform3D, "size": Vector3 }]
var _tris := 0

static var _shape_cache: Dictionary = {}


func is_empty() -> bool:
	return _tris == 0


func triangle_count() -> int:
	return _tris


func collider_count() -> int:
	return _shapes.size()


func _group(mat: Material) -> Group:
	var g = _groups.get(mat)
	if g == null:
		g = Group.new()
		_groups[mat] = g
	return g


# ------------------------------------------------------------------ geometry

## Axis-aligned-in-local-space box, placed by transform.
func box(xf: Transform3D, size: Vector3, mat: Material, uv := 1.0) -> void:
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0 or mat == null:
		return
	var h := size * 0.5
	var g := _group(mat)
	var c := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z),
		Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z),
		Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	# (indices, normal) for all six faces, wound CCW from outside
	var faces := [
		[[4, 5, 6, 7], Vector3(0, 0, 1)],
		[[1, 0, 3, 2], Vector3(0, 0, -1)],
		[[5, 1, 2, 6], Vector3(1, 0, 0)],
		[[0, 4, 7, 3], Vector3(-1, 0, 0)],
		[[3, 7, 6, 2], Vector3(0, 1, 0)],
		[[0, 1, 5, 4], Vector3(0, -1, 0)],
	]
	for f in faces:
		var quad: Array = f[0]
		var n: Vector3 = xf.basis * (f[1] as Vector3)
		var p0: Vector3 = xf * c[quad[0]]
		var p1: Vector3 = xf * c[quad[1]]
		var p2: Vector3 = xf * c[quad[2]]
		var p3: Vector3 = xf * c[quad[3]]
		g.add_quad(p0, p1, p2, p3, n.normalized(), uv)
	_tris += 12


func box_at(pos: Vector3, size: Vector3, mat: Material, rot_deg := Vector3.ZERO,
		uv := 1.0) -> void:
	box(Transform3D(euler_basis(rot_deg), pos), size, mat, uv)


func box_basis(b: Basis, pos: Vector3, size: Vector3, mat: Material, uv := 1.0) -> void:
	box(Transform3D(b, pos), size, mat, uv)


static func euler_basis(rot_deg: Vector3) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y),
			deg_to_rad(rot_deg.z)))


## A horizontal slab.  Reads better than a box for floors and road decks.
func slab(pos: Vector3, w: float, d: float, thickness: float, mat: Material,
		yaw := 0.0, uv := 1.0) -> void:
	box_at(pos, Vector3(w, thickness, d), mat, Vector3(0, yaw, 0), uv)


func quad(origin: Vector3, right: Vector3, up: Vector3, size: Vector2, mat: Material,
		uv := 1.0) -> void:
	if mat == null:
		return
	var g := _group(mat)
	var r := right.normalized() * size.x
	var u := up.normalized() * size.y
	var rv := right.normalized()
	var uv_v := up.normalized()
	var n := rv.cross(uv_v).normalized()
	var p0 := origin
	var p1 := origin + r
	var p2 := origin + r + u
	var p3 := origin + u
	g.add_tri(p0, p1, p2, n, n, n, Vector2.ZERO, Vector2(uv * size.x, 0),
			Vector2(uv * size.x, uv * size.y))
	g.add_tri(p0, p2, p3, n, n, n, Vector2.ZERO, Vector2(uv * size.x, uv * size.y),
			Vector2(0, uv * size.y))
	_tris += 2


## A single free-standing triangle (gable ends, signs, fins).
func tri(a: Vector3, b: Vector3, c: Vector3, mat: Material, uv := 1.0) -> void:
	if mat == null:
		return
	var g := _group(mat)
	var n := (b - a).cross(c - a).normalized()
	g.add_tri(a, b, c, n, n, n, Vector2.ZERO,
			Vector2((b - a).length() * uv, 0.0),
			Vector2((b - a).length() * uv * 0.5, (c - a).length() * uv))
	_tris += 1


## A double-sided triangle, for surfaces seen from either side.
func tri2(a: Vector3, b: Vector3, c: Vector3, mat: Material, uv := 1.0) -> void:
	tri(a, b, c, mat, uv)
	tri(c, b, a, mat, uv)


## n-sided prism (a cylinder when `sides` is high, a bollard when it is low).
func prism(xf: Transform3D, radius: float, height: float, sides: int, mat: Material,
		taper := 1.0) -> void:
	if mat == null or sides < 3:
		return
	var g := _group(mat)
	var h := height * 0.5
	var rt := radius * taper
	var rr := maxf(0.001, radius)
	var rt2 := maxf(0.001, rt)
	var bottom_c: Vector3 = xf * Vector3(0, -h, 0)
	var top_c: Vector3 = xf * Vector3(0, h, 0)
	var dn: Vector3 = -(xf.basis * Vector3.UP).normalized()
	var up: Vector3 = (xf.basis * Vector3.UP).normalized()
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var b0 := Vector3(cos(a0), 0, sin(a0))
		var b1 := Vector3(cos(a1), 0, sin(a1))
		var s0 := xf * (b0 * rr + Vector3(0, -h, 0))
		var s1 := xf * (b1 * rr + Vector3(0, -h, 0))
		var t1 := xf * (b1 * rt2 + Vector3(0, h, 0))
		var t0 := xf * (b0 * rt2 + Vector3(0, h, 0))
		var n0: Vector3 = (xf.basis * b0).normalized()
		var n1: Vector3 = (xf.basis * b1).normalized()
		g.add_tri(s0, s1, t1, n0, n1, n1, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
		g.add_tri(s0, t1, t0, n0, n1, n0, Vector2(0, 0), Vector2(1, 1), Vector2(0, 1))
		# caps, wound to face outwards
		g.add_tri(bottom_c, s1, s0, dn, dn, dn,
				Vector2(0.5, 0.5), Vector2(1, 0), Vector2(0, 0))
		if taper > 0.0:
			g.add_tri(top_c, t0, t1, up, up, up,
					Vector2(0.5, 0.5), Vector2(0, 1), Vector2(1, 1))
		_tris += 5
	if taper <= 0.0:
		_tris += 0


func cylinder_at(pos: Vector3, radius: float, height: float, mat: Material,
		sides := 12, rot_deg := Vector3.ZERO) -> void:
	prism(Transform3D(Basis.from_euler(Vector3(deg_to_rad(rot_deg.x),
			deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))), pos),
			radius, height, sides, mat)


## Cylinder lying along an arbitrary direction (pipes, rails, cables).
func pipe(from: Vector3, to: Vector3, radius: float, mat: Material, sides := 8) -> void:
	var d := to - from
	var len := d.length()
	if len < 0.001:
		return
	var up := d.normalized()
	var ref := Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT
	var b := Basis(right_axis(up, ref), up, up.cross(right_axis(up, ref))).orthonormalized()
	prism(Transform3D(b, (from + to) * 0.5), radius, len, sides, mat)


func right_axis(fwd: Vector3, ref: Vector3) -> Vector3:
	return ref.cross(fwd).normalized()


# ----------------------------------------------------------------- collision

## Register a collision box.  Call once per volume the player should not walk
## through -- a building's footprint, a wall run, a ship's hull.
func collide(xf: Transform3D, size: Vector3) -> void:
	_shapes.append({"xf": xf, "size": size})


func collide_at(pos: Vector3, size: Vector3, yaw := 0.0) -> void:
	collide(Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(yaw), 0)), pos), size)


static func _shape(size: Vector3) -> BoxShape3D:
	var key := "%.2f_%.2f_%.2f" % [size.x, size.y, size.z]
	if _shape_cache.has(key):
		return _shape_cache[key]
	var s := BoxShape3D.new()
	s.size = size
	_shape_cache[key] = s
	return s


# -------------------------------------------------------------------- commit

func commit(parent: Node3D, name_hint := "Batch", collide := true,
		cast_shadows := true) -> MeshInstance3D:
	if _groups.is_empty():
		return null
	var mesh := ArrayMesh.new()
	var surf := 0
	var order: Array = _groups.keys()
	# stable ordering keeps material slots identical between runs
	order.sort_custom(func(a, b): return String(a.resource_name) < String(b.resource_name))
	for mat in _groups:
		var g: Group = _groups[mat]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.verts
		arrays[Mesh.ARRAY_NORMAL] = g.norms
		arrays[Mesh.ARRAY_TEX_UV] = g.uvs
		arrays[Mesh.ARRAY_INDEX] = g.idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(surf, mat)
		surf += 1

	var mi := MeshInstance3D.new()
	mi.name = name_hint
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

	if collide and not _shapes.is_empty():
		var body := StaticBody3D.new()
		body.name = name_hint + "_col"
		body.collision_layer = 1
		body.collision_mask = 0
		for s in _shapes:
			var cs := CollisionShape3D.new()
			cs.shape = _shape(s["size"])
			cs.transform = s["xf"]
			body.add_child(cs)
		parent.add_child(body)
	return mi
