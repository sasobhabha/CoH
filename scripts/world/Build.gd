class_name Build
## Kit-bash toolkit for building levels out of unit primitives.
##
## All meshes are shared 1x1x1 resources and are sized with the node
## transform, so the entire city costs a handful of GPU buffers.  Collision
## shapes are funnelled into one StaticBody3D per parent, which keeps the
## physics broadphase tidy.

static var _meshes: Dictionary = {}
static var _shapes: Dictionary = {}


# ------------------------------------------------------------------- meshes

static func _mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var m: Mesh
	match kind:
		"box":
			var b := BoxMesh.new()
			b.size = Vector3.ONE
			m = b
		"sphere":
			var s := SphereMesh.new()
			s.radius = 0.5
			s.height = 1.0
			s.radial_segments = 20
			s.rings = 10
			m = s
		"cyl":
			var c := CylinderMesh.new()
			c.top_radius = 0.5
			c.bottom_radius = 0.5
			c.height = 1.0
			c.radial_segments = 18
			c.rings = 1
			m = c
		"cone":
			var k := CylinderMesh.new()
			k.top_radius = 0.0
			k.bottom_radius = 0.5
			k.height = 1.0
			k.radial_segments = 14
			m = k
		"capsule":
			var p := CapsuleMesh.new()
			p.radius = 0.5
			p.height = 2.0
			p.radial_segments = 14
			p.rings = 6
			m = p
		"plane":
			var pl := PlaneMesh.new()
			pl.size = Vector2.ONE
			pl.subdivide_width = 4
			pl.subdivide_depth = 4
			m = pl
		"waterplane":
			var wp := PlaneMesh.new()
			wp.size = Vector2.ONE
			wp.subdivide_width = 64
			wp.subdivide_depth = 64
			m = wp
		"quad":
			var q := QuadMesh.new()
			q.size = Vector2.ONE
			m = q
		"prism":
			var pr := PrismMesh.new()
			pr.size = Vector3.ONE
			m = pr
		_:
			m = BoxMesh.new()
	_meshes[kind] = m
	return m


static func _body_shape(size: Vector3) -> Shape3D:
	var key := "%.3f_%.3f_%.3f" % [size.x, size.y, size.z]
	if _shapes.has(key):
		return _shapes[key]
	var s := BoxShape3D.new()
	s.size = size
	_shapes[key] = s
	return s


static func _sphere_shape(r: float) -> Shape3D:
	var key := "s%.3f" % r
	if _shapes.has(key):
		return _shapes[key]
	var s := SphereShape3D.new()
	s.radius = r
	_shapes[key] = s
	return s


static func xform(pos: Vector3, rot_deg := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	var r := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	return Transform3D(r * Basis.from_scale(scl), pos)


# ----------------------------------------------------------------- physics

static func collision_body(parent: Node) -> StaticBody3D:
	for c in parent.get_children():
		if c is StaticBody3D and String(c.name) == "__collision":
			return c
	var b := StaticBody3D.new()
	b.name = "__collision"
	b.collision_layer = 1
	b.collision_mask = 0
	parent.add_child(b)
	return b


static func _add_shape(parent: Node3D, pos: Vector3, rot: Vector3, shape: Shape3D) -> void:
	var body := collision_body(parent)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xform(pos, rot)
	body.add_child(cs)


# --------------------------------------------------------------- primitives

static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		rot := Vector3.ZERO, collide := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh("box")
	if mat != null:
		mi.material_override = mat
	mi.transform = xform(pos, rot, size)
	parent.add_child(mi)
	if collide:
		_add_shape(parent, pos, rot, _body_shape(size))
	return mi


static func cylinder(parent: Node3D, radius: float, height: float, pos: Vector3,
		mat: Material, rot := Vector3.ZERO, collide := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh("cyl")
	if mat != null:
		mi.material_override = mat
	mi.transform = xform(pos, rot, Vector3(radius * 2.0, height, radius * 2.0))
	parent.add_child(mi)
	if collide:
		_add_shape(parent, pos, rot, _body_shape(Vector3(radius * 2.0, height, radius * 2.0)))
	return mi


static func cone(parent: Node3D, radius: float, height: float, pos: Vector3,
		mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh("cone")
	if mat != null:
		mi.material_override = mat
	mi.transform = xform(pos, rot, Vector3(radius * 2.0, height, radius * 2.0))
	parent.add_child(mi)
	return mi


static func sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material,
		squash := Vector3.ONE, collide := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh("sphere")
	if mat != null:
		mi.material_override = mat
	mi.transform = xform(pos, Vector3.ZERO, Vector3(radius * 2, radius * 2, radius * 2) * squash)
	parent.add_child(mi)
	if collide:
		_add_shape(parent, pos, Vector3.ZERO, _sphere_shape(radius))
	return mi


static func capsule(parent: Node3D, radius: float, height: float, pos: Vector3,
		mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh("capsule")
	if mat != null:
		mi.material_override = mat
	mi.transform = xform(pos, rot, Vector3(radius * 2.0, height * 0.5, radius * 2.0))
	parent.add_child(mi)
	return mi


static func floor_plane(parent: Node3D, size: Vector2, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh("plane")
	if mat != null:
		mi.material_override = mat
	mi.transform = xform(pos, Vector3.ZERO, Vector3(size.x, 1.0, size.y))
	parent.add_child(mi)
	return mi


## Subdivided, displacing water surface.  Never collides.
static func water(parent: Node3D, size: Vector2, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh("waterplane")
	if mat != null:
		mi.material_override = mat
	mi.transform = xform(pos, Vector3.ZERO, Vector3(size.x, 1.0, size.y))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func quad(parent: Node3D, size: Vector2, pos: Vector3, mat: Material,
		rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh("quad")
	if mat != null:
		mi.material_override = mat
	mi.transform = xform(pos, rot, Vector3(size.x, size.y, 1.0))
	parent.add_child(mi)
	return mi


static func ramp(parent: Node3D, width: float, length: float, height: float, pos: Vector3,
		mat: Material, yaw := 0.0) -> MeshInstance3D:
	## A box tilted about its local X axis so it reads as a ramp.
	var pitch := atan2(height, length)
	var len := sqrt(length * length + height * height)
	return box(parent, Vector3(width, 0.4, len),
			pos + Vector3(0, height * 0.5, 0), mat, Vector3(-rad_to_deg(pitch), yaw, 0), true)


# ------------------------------------------------------------------ detail

static func multimesh(parent: Node3D, kind: String, mat: Material, xforms: Array,
		name_hint := "Scatter") -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _mesh(kind)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = name_hint
	mi.multimesh = mm
	if mat != null:
		mi.material_override = mat
	parent.add_child(mi)
	return mi


## Scatter `count` randomly transformed instances inside a box region.
static func scatter(parent: Node3D, kind: String, mat: Material, count: int,
		center: Vector3, extents: Vector3, base_scale: Vector3, seed_v := 1,
		yaw_random := true, jitter := 0.35) -> MultiMeshInstance3D:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var xf: Array = []
	for i in count:
		var p := center + Vector3(
				r.randf_range(-extents.x, extents.x),
				r.randf_range(-extents.y, extents.y),
				r.randf_range(-extents.z, extents.z))
		var s := base_scale * (1.0 - jitter * 0.5 + r.randf() * jitter)
		var yaw := r.randf_range(0.0, TAU) if yaw_random else 0.0
		xf.append(xform(p, Vector3(0, rad_to_deg(yaw), 0), s))
	return multimesh(parent, kind, mat, xf, "Scatter_%s" % kind)


static func rubble_field(parent: Node3D, center: Vector3, extents: Vector3, count := 60,
		seed_v := 5) -> void:
	scatter(parent, "box", MatLib.concrete_dark(), count, center + Vector3(0, 0.15, 0),
			extents, Vector3(0.55, 0.35, 0.55), seed_v, true, 0.9)
	scatter(parent, "box", MatLib.brick(), int(count * 0.4), center,
			extents, Vector3(0.3, 0.2, 0.3), seed_v + 1, true, 1.0)


static func grass_field(parent: Node3D, center: Vector3, extents: Vector3, count := 900,
		seed_v := 9, height := 0.5) -> void:
	var m := MatLib.flat(Color("6f9d47"), "grass_blade")
	m.albedo_color = Color("6f9d47")
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	scatter(parent, "quad", m, count, center + Vector3(0, height * 0.5, 0), extents,
			Vector3(0.12, height, 1.0), seed_v, true, 0.5)


# ----------------------------------------------------------- held weapons

## The service rifle: grip at the origin, barrel down -Z, sized to sit in any
## rig's chest-space `weapon` bone.
##
## Shared, because the enemies have been gripping a rifle that was never there
## in the world: the clips drive both hands onto the weapon bone, and only the
## player ever built the geometry to put in it.
static func rifle(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Rifle"
	parent.add_child(root)

	var body_mat := MatLib.painted(Color("2c3238"), "gun_body")
	var dark := MatLib.painted(Color("171b1f"), "gun_dark")
	var worn := MatLib.metal_rust()

	box(root, Vector3(0.062, 0.10, 0.44), Vector3(0, 0, -0.10), body_mat, Vector3.ZERO, false)
	box(root, Vector3(0.042, 0.042, 0.34), Vector3(0, 0.012, -0.44), dark, Vector3.ZERO, false)
	cylinder(root, 0.016, 0.10, Vector3(0, 0.012, -0.62), worn, Vector3(90, 0, 0))
	box(root, Vector3(0.05, 0.19, 0.085), Vector3(0, -0.135, -0.06), dark, Vector3.ZERO, false)
	box(root, Vector3(0.05, 0.11, 0.06), Vector3(0, -0.09, 0.07), worn, Vector3(14, 0, 0), false)
	box(root, Vector3(0.055, 0.075, 0.19), Vector3(0, -0.01, 0.20), body_mat, Vector3.ZERO, false)
	box(root, Vector3(0.048, 0.05, 0.10), Vector3(0, 0.072, -0.11), dark, Vector3.ZERO, false)
	box(root, Vector3(0.02, 0.012, 0.02), Vector3(0, 0.078, -0.17),
			MatLib.emissive(Color("66ffcc"), 3.0), Vector3.ZERO, false)
	box(root, Vector3(0.03, 0.05, 0.11), Vector3(-0.045, -0.05, -0.26), dark, Vector3.ZERO, false)
	return root


# -------------------------------------------------------------- decorations

static func sign(parent: Node3D, text: String, pos: Vector3, rot: Vector3, color: Color,
		size := 48, no_depth := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.modulate = color
	l.outline_size = 0
	l.pixel_size = 0.006
	l.shaded = false
	l.double_sided = true
	l.no_depth_test = no_depth
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.rotation_degrees = rot
	l.position = pos
	l.render_priority = 1
	parent.add_child(l)
	return l


static func billboard(parent: Node3D, size: Vector2, pos: Vector3, color: Color,
		alpha := 0.6, add := true) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if add else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh("quad")
	mi.material_override = m
	mi.transform = xform(pos, Vector3.ZERO, Vector3(size.x, size.y, 1.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func shaft(parent: Node3D, size: Vector2, pos: Vector3, rot: Vector3, color: Color,
		alpha := 0.14) -> MeshInstance3D:
	## Unshaded additive quad used to fake a volumetric light shaft.
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh("quad")
	mi.material_override = m
	mi.transform = xform(pos, rot, Vector3(size.x, size.y, 1.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func omni(parent: Node3D, pos: Vector3, color: Color, energy: float, range_m: float,
		shadows := false, volumetric := 1.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.omni_attenuation = 1.4
	l.shadow_enabled = shadows
	l.shadow_bias = 0.06
	l.light_volumetric_fog_energy = volumetric
	l.light_specular = 0.6
	parent.add_child(l)
	return l


static func spot(parent: Node3D, pos: Vector3, rot: Vector3, color: Color, energy: float,
		range_m: float, angle := 32.0, shadows := true, volumetric := 2.0) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.position = pos
	l.rotation_degrees = rot
	l.light_color = color
	l.light_energy = energy
	l.spot_range = range_m
	l.spot_angle = angle
	l.spot_angle_attenuation = 1.6
	l.spot_attenuation = 1.2
	l.shadow_enabled = shadows
	l.shadow_bias = 0.04
	l.light_volumetric_fog_energy = volumetric
	parent.add_child(l)
	return l


static func sun(parent: Node3D, rot: Vector3, color: Color, energy: float,
		angular := 3.0) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.rotation_degrees = rot
	l.light_color = color
	l.light_energy = energy
	l.light_angular_distance = angular
	l.shadow_enabled = true
	l.shadow_bias = 0.05
	l.shadow_normal_bias = 1.4
	l.directional_shadow_max_distance = 130.0
	l.directional_shadow_blend_splits = true
	l.light_volumetric_fog_energy = 1.0
	l.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	parent.add_child(l)
	return l


# ------------------------------------------------------------------- areas

static func trigger(parent: Node3D, size: Vector3, pos: Vector3, name_hint := "Trigger") -> Area3D:
	var a := Area3D.new()
	a.name = name_hint
	a.collision_layer = 16          # layer 5: trigger
	a.collision_mask = 2            # layer 2: player
	a.monitoring = true
	a.position = pos
	var cs := CollisionShape3D.new()
	cs.shape = _body_shape(size)
	a.add_child(cs)
	parent.add_child(a)
	return a


static func blocker(parent: Node3D, size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> void:
	## Invisible collision volume (walls, doors, map bounds).
	_add_shape(parent, pos, rot, _body_shape(size))
