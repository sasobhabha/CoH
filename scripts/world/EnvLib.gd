class_name EnvLib
## Atmosphere presets, one per chapter.
##
## Each preset returns a configured Environment; the chapter supplies its own
## lights.  Quality flags (SSAO/SSR/glow/volumetric fog) are layered on
## afterwards by Settings.apply_quality(), so these stay purely art direction.
##
## Exposure note: the sky is the ambient light source everywhere outdoors, so
## the sky colours set the floor for how dark a chapter can get.  Keep the
## horizon in the 0.4-0.7 luminance band or the world goes to mud.

static func sky(top: Color, horizon: Color, ground: Color, energy := 1.0,
		sun_max := 6.0) -> Sky:
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = top
	mat.sky_horizon_color = horizon
	mat.sky_curve = 0.10
	mat.sky_energy_multiplier = energy
	mat.ground_bottom_color = ground
	mat.ground_horizon_color = horizon
	mat.ground_curve = 0.08
	mat.ground_energy_multiplier = energy * 0.8
	mat.sun_angle_max = sun_max
	mat.sun_curve = 0.06
	mat.use_debanding = true
	var s := Sky.new()
	s.sky_material = mat
	s.radiance_size = Sky.RADIANCE_SIZE_256
	s.process_mode = Sky.PROCESS_MODE_REALTIME
	return s


static func _base() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 1.0
	# Ambient is deliberately below 1.0: the sky fills the shadows, the key
	# light carves the forms.  Ambient-only lighting is what makes a scene look
	# like an untextured model in a turntable.
	e.ambient_light_energy = 0.78
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	# ACES rolls off hard above `tonemap_white`; with the sky acting as a huge
	# area light, anything above ~3.5 clips the whole frame to paper white.
	e.tonemap_white = 3.2
	e.tonemap_exposure = 0.85
	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = 1.08
	e.adjustment_saturation = 1.0
	e.glow_enabled = true
	e.glow_normalized = true
	# Glow is a garnish on emissive signage, not a lens full of vaseline.
	e.glow_intensity = 0.30
	e.glow_strength = 1.0
	e.glow_bloom = 0.015
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.glow_hdr_threshold = 1.7
	e.glow_hdr_scale = 1.4
	e.set("glow_levels/1", 0.0)
	e.set("glow_levels/2", 0.3)
	e.set("glow_levels/3", 0.9)
	e.set("glow_levels/4", 0.8)
	e.set("glow_levels/5", 0.6)
	e.set("glow_levels/6", 0.3)
	e.set("glow_levels/7", 0.0)
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_light_color = Color("5d7280")
	e.fog_light_energy = 0.75
	e.fog_sun_scatter = 0.2
	# Distance haze is part of the look, but it must not be strong enough to
	# erase the far half of a district.  Anything past ~0.007 swallows a 120 m
	# avenue, so the fog here is a tint and not a wall.
	e.fog_density = 0.0042
	e.fog_aerial_perspective = 0.28
	e.fog_sky_affect = 0.22
	e.fog_height = 6.0
	e.fog_height_density = 0.02
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = 0.0026
	e.volumetric_fog_albedo = Color("b7c8d4")
	e.volumetric_fog_emission = Color("141c22")
	e.volumetric_fog_emission_energy = 0.5
	e.volumetric_fog_gi_inject = 0.35
	e.volumetric_fog_anisotropy = 0.35
	e.volumetric_fog_length = 170.0
	e.volumetric_fog_detail_spread = 2.0
	e.volumetric_fog_ambient_inject = 0.30
	e.volumetric_fog_sky_affect = 0.18
	e.volumetric_fog_temporal_reprojection_enabled = true
	return e


# --------------------------------------------------------------- presets

## Chapter I -- rain over a city that never drained.
static func drowned_dusk() -> Environment:
	var e := _base()
	e.sky = sky(Color("2b3f55"), Color("9c6f4e"), Color("252a2e"), 0.95, 4.0)
	e.ambient_light_energy = 0.62
	e.tonemap_exposure = 0.82
	e.fog_light_color = Color("48596a")
	e.fog_density = 0.0021
	e.fog_light_energy = 0.30
	e.fog_aerial_perspective = 0.22
	e.fog_sky_affect = 0.20
	e.volumetric_fog_density = 0.0012
	e.volumetric_fog_albedo = Color("bccdd8")
	e.glow_intensity = 0.8
	e.adjustment_saturation = 0.97
	e.adjustment_contrast = 1.07
	e.adjustment_brightness = 1.04
	return e


## Chapter I -- the occupied plaza.
##
## A century of ash rather than forty years of rain: the same low sun as the
## original dusk, but the haze is smoke and the ground bounce is warm, because
## this district burns instead of flooding.  `drowned_dusk` is kept for the
## chapters that are still underwater.
static func occupied_square() -> Environment:
	var e := _base()
	e.sky = sky(Color("3d4a52"), Color("b07a4e"), Color("2a2622"), 0.92, 4.4)
	e.ambient_light_energy = 0.55
	e.tonemap_exposure = 0.86
	e.fog_light_color = Color("6a5a4c")
	e.fog_density = 0.0034
	e.fog_light_energy = 0.34
	e.fog_aerial_perspective = 0.34
	e.fog_sky_affect = 0.28
	e.volumetric_fog_density = 0.0030
	e.volumetric_fog_albedo = Color("cbb8a6")
	e.glow_intensity = 0.94
	e.adjustment_saturation = 0.94
	e.adjustment_contrast = 1.09
	e.adjustment_brightness = 1.02
	return e


## Chapter II -- the one warm room left.
static func tavern() -> Environment:
	var e := _base()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("0d0a07")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("4a3826")
	# A firelit room is dark except where the lamps are.  High ambient here
	# flattens every surface into the same orange.
	e.ambient_light_energy = 0.24
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_exposure = 0.92
	e.fog_light_color = Color("241a12")
	e.fog_density = 0.006
	e.fog_aerial_perspective = 0.0
	e.fog_height_density = 0.25
	e.volumetric_fog_density = 0.0055
	e.volumetric_fog_albedo = Color("ffc489")
	e.volumetric_fog_emission = Color("22110a")
	e.volumetric_fog_emission_energy = 0.9
	e.volumetric_fog_anisotropy = 0.55
	e.volumetric_fog_length = 30.0
	e.glow_intensity = 0.34
	e.glow_bloom = 0.02
	e.glow_hdr_threshold = 1.6
	e.adjustment_saturation = 1.08
	e.adjustment_contrast = 1.10
	e.adjustment_brightness = 1.0
	return e


## Chapter III -- the market, held by force.
static func flood_market() -> Environment:
	var e := drowned_dusk()
	e.sky = sky(Color("2b3f55"), Color("94664a"), Color("272d31"), 0.78, 4.0)
	e.fog_density = 0.0034
	e.fog_aerial_perspective = 0.26
	e.volumetric_fog_density = 0.0022
	e.tonemap_exposure = 0.70
	e.glow_intensity = 1.05
	e.adjustment_contrast = 1.11
	e.adjustment_saturation = 0.98
	return e


## Chapter IV -- no light, no rifle.
static func the_dark() -> Environment:
	var e := _base()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("080b10")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("33465a")
	e.ambient_light_energy = 0.26
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_exposure = 1.15
	e.fog_light_color = Color("26333f")
	e.fog_density = 0.014
	e.fog_aerial_perspective = 0.0
	e.fog_height_density = 0.08
	e.volumetric_fog_density = 0.010
	e.volumetric_fog_albedo = Color("8fa6b6")
	e.volumetric_fog_emission = Color("0a1016")
	e.volumetric_fog_emission_energy = 0.3
	e.volumetric_fog_length = 44.0
	e.glow_intensity = 1.0
	e.glow_hdr_threshold = 0.95
	e.adjustment_saturation = 0.85
	e.adjustment_contrast = 1.16
	e.adjustment_brightness = 1.0
	return e


## Chapter V -- sunlight after the ash.
static func meadow_day() -> Environment:
	var e := _base()
	e.sky = sky(Color("2d6ab8"), Color("c3ddf0"), Color("6d9448"), 1.25, 2.0)
	e.ambient_light_sky_contribution = 1.0
	e.ambient_light_energy = 0.60
	e.tonemap_exposure = 0.80
	e.fog_light_color = Color("dceaf6")
	e.fog_light_energy = 1.2
	e.fog_sun_scatter = 0.5
	e.fog_density = 0.0032
	e.fog_aerial_perspective = 1.0
	e.fog_sky_affect = 0.25
	e.fog_height = 9.0
	e.fog_height_density = 0.02
	e.volumetric_fog_density = 0.005
	e.volumetric_fog_albedo = Color("ffffff")
	e.volumetric_fog_emission = Color("26303c")
	e.volumetric_fog_emission_energy = 0.7
	e.volumetric_fog_anisotropy = 0.62
	e.volumetric_fog_length = 150.0
	e.volumetric_fog_sky_affect = 0.15
	e.glow_intensity = 0.5
	e.glow_bloom = 0.03
	e.glow_hdr_threshold = 1.5
	e.adjustment_saturation = 1.08
	e.adjustment_contrast = 0.99
	e.adjustment_brightness = 1.04
	return e


## The main menu -- the monolith under a burning sky.
static func menu_dusk() -> Environment:
	var e := _base()
	e.sky = sky(Color("1b2c3e"), Color("b8753f"), Color("15181c"), 0.95, 3.0)
	e.ambient_light_sky_contribution = 1.0
	e.ambient_light_energy = 0.58
	e.tonemap_exposure = 0.82
	e.fog_light_color = Color("54626e")
	e.fog_density = 0.0055
	e.fog_sun_scatter = 0.4
	e.fog_aerial_perspective = 0.38
	e.fog_sky_affect = 0.34
	e.volumetric_fog_density = 0.0050
	e.volumetric_fog_albedo = Color("ffc79a")
	e.volumetric_fog_emission = Color("241305")
	e.volumetric_fog_emission_energy = 0.9
	e.volumetric_fog_anisotropy = 0.5
	e.glow_intensity = 1.15
	e.glow_bloom = 0.12
	e.glow_hdr_threshold = 1.0
	e.adjustment_saturation = 1.04
	e.adjustment_contrast = 1.10
	e.adjustment_brightness = 1.06
	return e


static func for_chapter(index: int) -> Environment:
	match index:
		0: return occupied_square()
		1: return tavern()
		2: return flood_market()
		3: return the_dark()
		4: return meadow_day()
	return drowned_dusk()
