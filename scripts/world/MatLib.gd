class_name MatLib
## Named surfaces.
##
## Everything here resolves to a texture set built by tools/gen_textures.py and
## loaded through TexLib, which applies world-space triplanar projection so a
## surface's detail never stretches with the geometry it is on.  This class is
## the vocabulary: chapters ask for "wet concrete" or "rusted steel", not for a
## material configuration.

static var _cache: Dictionary = {}
static var _ripple: NoiseTexture2D


static func _surf(key: String, set_name: String, tint: Color, tile := -1.0,
		rough := 1.0, emit := Color.BLACK, energy := 0.0) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var m := TexLib.mat(set_name, tint, tile, rough, emit, energy)
	_cache[key] = m
	return m


# --- structural -------------------------------------------------------------

static func concrete() -> StandardMaterial3D:
	return _surf("concrete", "concrete", Color.WHITE)


static func concrete_dark() -> StandardMaterial3D:
	return _surf("concrete_dark", "concrete_dark", Color.WHITE)


static func concrete_floor() -> StandardMaterial3D:
	return _surf("concrete_floor", "concrete_floor", Color.WHITE)


## Soaked concrete: the same surface with its roughness knocked right down.
static func concrete_wet() -> StandardMaterial3D:
	return _surf("concrete_wet", "concrete_floor", Color(0.46, 0.50, 0.55), 2.5, 0.30)


static func plaster(faded := false) -> StandardMaterial3D:
	if faded:
		return _surf("plaster_faded", "plaster", Color(1.18, 1.14, 1.06), 2.4, 1.0)
	return _surf("plaster", "plaster", Color.WHITE)


static func brick() -> StandardMaterial3D:
	return _surf("brick", "brick", Color.WHITE)


static func asphalt() -> StandardMaterial3D:
	return _surf("asphalt", "asphalt", Color.WHITE)


## Ground planes need their own treatment.
##
## A road is seen at grazing angles for hundreds of metres, and at those angles
## a tangent-space normal map stops being detail and becomes lengthwise
## smearing -- the whole street turns into a bright streaked mirror.  So the
## ground drops the normal map entirely and reads through albedo alone, kept
## deliberately dark: an up-facing surface under an open sky is the brightest
## thing in the frame otherwise.
static func road(darken := 0.24) -> StandardMaterial3D:
	var key := "road_%.2f" % darken
	if _cache.has(key):
		return _cache[key]
	var m := TexLib.mat("asphalt", Color(darken, darken, darken), 9.0, 1.0,
			Color.BLACK, 0.0, 1.0, false)
	m.roughness = 1.0
	m.metallic = 0.0
	_cache[key] = m
	return m


static func ground_plane(set_name: String, darken := 0.22) -> StandardMaterial3D:
	var key := "ground_%s_%.2f" % [set_name, darken]
	if _cache.has(key):
		return _cache[key]
	var m := TexLib.mat(set_name, Color(darken, darken, darken), -1.0, 1.0,
			Color.BLACK, 0.0, 1.0, false)
	m.roughness = 1.0
	_cache[key] = m
	return m


## Asphalt after a week of rain -- a wet road reads as a mirror at grazing
## angles, which is most of the atmosphere in a flooded district.
static func asphalt_wet() -> StandardMaterial3D:
	return _surf("asphalt_wet", "asphalt", Color(0.60, 0.64, 0.70), 6.0, 0.16)


static func dirt() -> StandardMaterial3D:
	return _surf("dirt", "dirt", Color.WHITE)


static func gravel() -> StandardMaterial3D:
	return _surf("gravel", "gravel", Color.WHITE)


static func grass() -> StandardMaterial3D:
	return _surf("grass", "grass", Color.WHITE)


static func meadow() -> StandardMaterial3D:
	return _surf("meadow", "grass", Color(1.15, 1.22, 0.9), 4.0, 1.0)


static func rock() -> StandardMaterial3D:
	return _surf("rock", "rock", Color.WHITE)


static func roof() -> StandardMaterial3D:
	return _surf("roof", "roof", Color.WHITE)


static func plaster_blue() -> StandardMaterial3D:
	return _surf("plaster_blue", "plaster_blue", Color.WHITE)


# --- metal ------------------------------------------------------------------

static func metal() -> StandardMaterial3D:
	return _surf("metal", "steel_paint", Color(0.92, 0.94, 0.98), 2.0, 0.9)


static func metal_rust() -> StandardMaterial3D:
	return _surf("metal_rust", "steel_rust", Color.WHITE)


static func metal_dark() -> StandardMaterial3D:
	return _surf("metal_dark", "steel_paint", Color(0.30, 0.32, 0.36), 2.0, 0.55)


static func grating() -> StandardMaterial3D:
	return _surf("grating", "steel_rust", Color(0.55, 0.56, 0.58), 1.0, 0.85)


static func painted(color: Color, key := "") -> StandardMaterial3D:
	return _surf("paint_" + (key if key != "" else color.to_html()), "steel_paint",
			color, 2.0, 0.85)


static func steel(color: Color) -> StandardMaterial3D:
	return painted(color)


# --- wood / fabric / misc ---------------------------------------------------

static func wood() -> StandardMaterial3D:
	return _surf("wood", "wood", Color.WHITE)


static func wood_dark() -> StandardMaterial3D:
	return _surf("wood_dark", "wood", Color(0.6, 0.55, 0.5), 1.6, 1.0)


static func wood_pale() -> StandardMaterial3D:
	return _surf("wood_pale", "wood_pale", Color.WHITE)


static func fabric(color: Color) -> StandardMaterial3D:
	return _surf("fabric_" + color.to_html(), "canvas", color, 1.6, 1.0)


static func plastic(color: Color) -> StandardMaterial3D:
	return _surf("plastic_" + color.to_html(), "steel_paint", color, 1.0, 0.30)


static func rubber() -> StandardMaterial3D:
	return _surf("rubber", "steel_rust", Color(0.22, 0.22, 0.23), 1.0, 1.0)


static func glass(tint := Color(0.30, 0.37, 0.40)) -> StandardMaterial3D:
	var key := "glass_" + tint.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := TexLib.glass(tint, 0.5)
	_cache[key] = m
	return m


static func emissive(color: Color, energy := 2.5) -> StandardMaterial3D:
	var key := "emit_%s_%.2f" % [color.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r * 0.3, color.g * 0.3, color.b * 0.3)
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	_cache[key] = m
	return m


## Flat unshaded material for signage, decals and light shafts.
static func flat(color: Color, key := "", alpha := 1.0) -> StandardMaterial3D:
	return TexLib.flat(color, alpha, key != "grass_blade")


## Generic escape hatch: a tinted surface from any generated texture set.
static func standard(key: String, albedo: Color, roughness := 0.85, metallic := 0.0,
		tex := "", uv := 1.0, emission := Color(0, 0, 0), emission_energy := 0.0,
		normal_tex := "", _normal_strength := 0.6) -> StandardMaterial3D:
	var ck := "std_" + key
	if _cache.has(ck):
		return _cache[ck]
	var set_name := tex if tex != "" else "concrete"
	var m := TexLib.mat(set_name, albedo, uv, roughness / maxf(roughness, 0.35),
			emission, emission_energy)
	m.roughness = clampf(roughness, 0.03, 1.0)
	m.metallic = metallic
	_cache[ck] = m
	return m


# --- water ------------------------------------------------------------------

static func water(ripple: NoiseTexture2D) -> ShaderMaterial:
	if _cache.has("water_shader"):
		return _cache["water_shader"]
	var sh := load("res://shaders/water.gdshader") as Shader
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("ripple_normal", ripple)
	_cache["water_shader"] = m
	return m


static func ripple_texture() -> NoiseTexture2D:
	if _ripple != null:
		return _ripple
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = 77
	n.frequency = 0.06
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 3
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 256
	t.height = 256
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = 14.0
	_ripple = t
	return t
