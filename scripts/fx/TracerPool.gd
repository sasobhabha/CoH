class_name TracerPool
extends Node3D
## Recycled bullet tracers.
##
## A tracer is a thin box stretched from the muzzle to the impact point and
## shown for a few frames.  Nothing is allocated per shot: the pool is built
## once and each slot carries its own expiry stamp.

const LIFE := 0.06
const SLOTS := 40

var _slots: Array[MeshInstance3D] = []
var _expiry := PackedFloat32Array()
var _next := 0


func _ready() -> void:
	top_level = true
	for i in SLOTS:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.82, 0.45, 0.95)
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.disable_receive_shadows = true
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_slots.append(mi)
		_expiry.append(0.0)
	set_process(true)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for i in _slots.size():
		if _slots[i].visible and now >= _expiry[i]:
			_slots[i].visible = false


## Draw a tracer from `from` to `to`.  `width` is the visual thickness in metres.
func fire(from: Vector3, to: Vector3, width := 0.022, color := Color(1.0, 0.82, 0.45)) -> void:
	var d := to - from
	var dist := d.length()
	if dist < 0.05:
		return
	var mi := _slots[_next]
	_next = (_next + 1) % SLOTS
	mi.visible = true
	var mat := mi.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color(color.r, color.g, color.b, 0.95)
	var t := Transform3D(FX.align_z(d), from + d * 0.5)
	mi.transform = t.scaled_local(Vector3(width, width, dist))
	var idx := (_next - 1 + SLOTS) % SLOTS
	_expiry[idx] = Time.get_ticks_msec() / 1000.0 + LIFE


func clear_all() -> void:
	for mi in _slots:
		mi.visible = false
