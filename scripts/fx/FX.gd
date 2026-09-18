class_name FX
## Factory for particles and the small transient visuals that sell impact.
##
## Everything is pooled or pre-configured once, so combat never allocates.

static var _mats: Dictionary = {}


static func sprite_mat(key: String, color: Color, add := true, billboard := true,
		stretch := Vector2.ONE) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if add else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.no_depth_test = false
	m.vertex_color_use_as_albedo = true
	_mats[key] = m
	return m


static func _quad(w: float, h: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	return q


# -------------------------------------------------------------------- rain

static func rain(parent: Node3D, amount := 2400, streak := Vector2(0.013, 0.55),
		color := Color(0.72, 0.80, 0.88, 0.30)) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Rain"
	p.amount = amount
	p.lifetime = 1.3
	p.explosiveness = 0.0
	p.fixed_fps = 0
	p.draw_pass_1 = _quad(streak.x, streak.y)
	p.material_override = sprite_mat("rain", color, true, true)
	p.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 60, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(26, 1.0, 26)
	pm.direction = Vector3(0.16, -1.0, 0.08)
	pm.spread = 2.5
	pm.initial_velocity_min = 24.0
	pm.initial_velocity_max = 34.0
	pm.gravity = Vector3(0.6, -14.0, 0.4)
	pm.scale_min = 0.7
	pm.scale_max = 1.5
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.2
	p.process_material = pm
	parent.add_child(p)
	return p


# ------------------------------------------------------------------ embers

static func embers(parent: Node3D, amount := 70, color := Color(1.0, 0.55, 0.18, 0.55),
		extents := Vector3(24, 6, 24), size := 0.05) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Embers"
	p.amount = amount
	p.lifetime = 6.5
	p.draw_pass_1 = _quad(size, size)
	p.material_override = sprite_mat("ember", color, true, true)
	p.visibility_aabb = AABB(-extents * 2.0, extents * 4.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3(0.2, 1.0, 0.1)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0.1, 0.35, 0.05)
	pm.scale_min = 0.4
	pm.scale_max = 1.6
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_speed = Vector3(0.15, 0.05, 0.15)
	pm.color_ramp = _ramp(Color(1, 0.7, 0.3, 0.0), Color(1, 0.6, 0.2, 1.0), Color(0.6, 0.15, 0.05, 0.0))
	p.process_material = pm
	parent.add_child(p)
	return p


# -------------------------------------------------------------------- dust

static func dust(parent: Node3D, amount := 160, extents := Vector3(12, 5, 12),
		size := 0.03, color := Color(0.85, 0.88, 0.92, 0.35)) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Dust"
	p.amount = amount
	p.lifetime = 12.0
	p.draw_pass_1 = _quad(size, size)
	p.material_override = sprite_mat("dust", color, true, true)
	p.visibility_aabb = AABB(-extents * 2.0, extents * 4.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3(0.1, 0.15, 0.1)
	pm.spread = 90.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.gravity = Vector3(0, -0.02, 0)
	pm.scale_min = 0.5
	pm.scale_max = 2.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.color_ramp = _ramp(Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0))
	p.process_material = pm
	parent.add_child(p)
	return p


# ------------------------------------------------------------------- smoke

static func smoke_plume(parent: Node3D, amount := 26, size := 2.6,
		color := Color(0.16, 0.15, 0.15, 0.5)) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Smoke"
	p.amount = amount
	p.lifetime = 9.0
	p.draw_pass_1 = _quad(size, size)
	p.material_override = sprite_mat("smoke", color, false, true)
	p.visibility_aabb = AABB(Vector3(-20, -6, -20), Vector3(40, 40, 40))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.7
	pm.direction = Vector3(0.1, 1.0, 0.0)
	pm.spread = 22.0
	pm.initial_velocity_min = 0.7
	pm.initial_velocity_max = 1.8
	pm.gravity = Vector3(0.2, 0.35, 0.0)
	pm.scale_min = 0.4
	pm.scale_max = 1.5
	pm.angular_velocity_min = -18.0
	pm.angular_velocity_max = 18.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.6
	pm.color_ramp = _ramp(Color(0.2, 0.19, 0.19, 0.0), Color(0.2, 0.19, 0.19, 0.8), Color(0.05, 0.05, 0.06, 0.0))
	p.process_material = pm
	parent.add_child(p)
	return p


static func fire_glow(parent: Node3D, amount := 34) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "FireGlow"
	p.amount = amount
	p.lifetime = 1.8
	p.draw_pass_1 = _quad(1.5, 1.5)
	p.material_override = sprite_mat("fireglow", Color(1.0, 0.5, 0.15, 0.75), true, true)
	p.visibility_aabb = AABB(Vector3(-8, -4, -8), Vector3(16, 16, 16))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.6
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.4
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.35
	pm.scale_max = 1.1
	pm.color_ramp = _ramp(Color(1, 0.85, 0.4, 0.0), Color(1, 0.6, 0.2, 0.9), Color(0.5, 0.1, 0.02, 0.0))
	p.process_material = pm
	parent.add_child(p)
	return p


# ------------------------------------------------------------------ helpers

static func _ramp(a: Color, b: Color, c: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, a)
	g.set_offset(1, 0.5)
	g.set_color(1, b)
	g.add_point(1.0, c)
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 64
	return t


## A radial gradient, used as the bullet-hole decal albedo.
static func hole_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(0.02, 0.02, 0.02, 0.95))
	g.set_offset(1, 0.35)
	g.set_color(1, Color(0.05, 0.05, 0.05, 0.75))
	g.add_point(1.0, Color(0.1, 0.1, 0.1, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


## Basis that points a Decal's projection axis (-Y) along `n`.
static func decal_basis(n: Vector3) -> Basis:
	var y := -n.normalized()
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


static func align_z(dir: Vector3, up := Vector3.UP) -> Basis:
	var d := dir.normalized()
	if absf(d.dot(up)) > 0.999:
		up = Vector3.RIGHT
	return Basis.looking_at(d, up)
