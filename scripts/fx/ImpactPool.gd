class_name ImpactPool
extends Node3D
## Bullet impacts: a projected decal plus a short spark burst.
##
## Decals are recycled in a ring buffer (oldest hole is re-used), spark
## emitters are pooled one-shot GPUParticles3D nodes that get restarted in
## place -- so a firefight costs no allocations at all.

const DECAL_SLOTS := 48
const SPARK_SLOTS := 14
const DECAL_LIFE := 24.0

var _decals: Array[Decal] = []
var _decal_expiry := PackedFloat32Array()
var _decal_next := 0

var _sparks: Array[GPUParticles3D] = []
var _spark_next := 0

var _splashes: Array[GPUParticles3D] = []
var _splash_next := 0

var _hole_tex: Texture2D


func _ready() -> void:
	top_level = true
	_hole_tex = FX.hole_texture()

	for i in DECAL_SLOTS:
		var d := Decal.new()
		d.texture_albedo = _hole_tex
		d.size = Vector3(0.28, 0.6, 0.28)
		d.modulate = Color(0.08, 0.07, 0.07, 1.0)
		d.albedo_mix = 0.85
		d.upper_fade = 0.35
		d.lower_fade = 0.35
		d.distance_fade_enabled = true
		d.distance_fade_begin = 22.0
		d.distance_fade_length = 8.0
		add_child(d)
		_decals.append(d)
		_decal_expiry.append(0.0)

	for i in SPARK_SLOTS:
		var p := _make_burst("Spark", Color(1.0, 0.72, 0.32, 0.95), 12, 0.032, 0.32,
				Vector3(0, -9.8, 0), 4.0, 11.0)
		add_child(p)
		_sparks.append(p)

	for i in 3:
		var p := _make_burst("Splash", Color(0.78, 0.88, 0.94, 0.85), 22, 0.05, 0.75,
				Vector3(0, -11.0, 0), 3.0, 8.0)
		add_child(p)
		_splashes.append(p)

	set_process(true)


func _make_burst(name_hint: String, color: Color, amount: int, size: float, life: float,
		gravity: Vector3, vmin: float, vmax: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = name_hint
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 1.0
	p.fixed_fps = 0
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	p.draw_pass_1 = q
	p.material_override = FX.sprite_mat("burst_" + name_hint, color, true, true)
	p.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.03
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.gravity = gravity
	pm.damping_min = 1.5
	pm.damping_max = 4.0
	pm.scale_min = 0.5
	pm.scale_max = 1.6
	pm.color_ramp = _ramp(Color(color.r, color.g, color.b, 0.0),
			Color(color.r, color.g, color.b, color.a),
			Color(color.r * 0.4, color.g * 0.3, color.b * 0.2, 0.0))
	p.process_material = pm
	return p


func _ramp(a: Color, b: Color, c: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, a)
	g.set_offset(1, 0.5)
	g.set_color(1, b)
	g.add_point(1.0, c)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for i in _decals.size():
		if _decals[i].visible and now >= _decal_expiry[i]:
			_decals[i].visible = false


## surface: "concrete" | "metal" | "flesh" | "water" | "dirt"
func impact(pos: Vector3, normal: Vector3, surface := "concrete") -> void:
	var n := normal.normalized()
	if surface == "water":
		var sp := _splashes[_splash_next]
		_splash_next = (_splash_next + 1) % _splashes.size()
		sp.global_position = pos
		sp.restart()
		return

	var d := _decals[_decal_next]
	_decal_next = (_decal_next + 1) % _decals.size()
	d.visible = true
	d.global_transform = Transform3D(FX.decal_basis(n), pos + n * 0.03)
	var scale := 1.0 if surface == "concrete" else 0.7
	d.size = Vector3(0.28, 0.6, 0.28) * scale
	d.modulate = Color(0.06, 0.05, 0.05) if surface != "metal" else Color(0.35, 0.33, 0.3)
	var slot := _decals.size() - 1 if _decal_next == 0 else _decal_next - 1
	_decal_expiry[slot] = Time.get_ticks_msec() / 1000.0 + DECAL_LIFE

	if surface == "flesh":
		return
	var p := _sparks[_spark_next]
	_spark_next = (_spark_next + 1) % _sparks.size()
	p.global_position = pos + n * 0.02
	var pm := p.process_material as ParticleProcessMaterial
	if pm != null:
		pm.direction = n
	p.restart()
