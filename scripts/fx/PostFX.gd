class_name PostFX
extends ColorRect
## The final image grade.  Lives on a CanvasLayer above the 3D world.
##
## Owns the damage wash and the low-health pulse, both of which decay on their
## own so gameplay code only has to push events in.

var damage := 0.0
var low_health := 0.0
var desaturate := 0.0
var vignette := 0.55
var contrast := 1.0

const DAMAGE_DECAY := 2.2

var _mat: ShaderMaterial


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(1, 1, 1, 1)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/post_process.gdshader")
	material = _mat
	Settings.changed.connect(_push)
	_push()


func _push() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("grain_enabled", 1.0 if bool(Settings.getv("film_grain")) else 0.0)
	_mat.set_shader_parameter("grain_amount", 0.028)
	_mat.set_shader_parameter("vignette_amount", vignette)
	_mat.set_shader_parameter("contrast_boost", contrast)


func _process(delta: float) -> void:
	if damage > 0.0:
		damage = maxf(0.0, damage - DAMAGE_DECAY * delta)
	if _mat == null:
		return
	_mat.set_shader_parameter("damage", damage)
	_mat.set_shader_parameter("low_health", low_health)
	_mat.set_shader_parameter("desaturate", desaturate)


func hit(amount := 1.0) -> void:
	damage = clampf(damage + amount, 0.0, 1.0)


## Flash the screen a solid colour (explosions, teleports, deaths).
func flash(color: Color, strength := 0.7, duration := 0.5) -> void:
	var layer := get_parent() as CanvasLayer
	if layer == null:
		return
	var r := ColorRect.new()
	r.color = Color(color.r, color.g, color.b, strength)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(r)
	var t := create_tween()
	t.tween_property(r, "color:a", 0.0, duration)
	t.tween_callback(r.queue_free)
