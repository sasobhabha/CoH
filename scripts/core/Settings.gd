extends Node
## Player-facing options: graphics, audio, display, controls.
##
## Persisted to `user://settings.cfg` as JSON.  Anything that affects the
## renderer is pushed out through the `changed` signal so live scenes can
## re-apply quality to their own WorldEnvironment.

signal changed
signal display_changed

const PATH := "user://settings.cfg"

const DEFAULTS := {
	# audio
	"master_volume": 0.85,
	"music_volume": 0.62,
	"sfx_volume": 0.95,
	"ambience_volume": 0.55,
	"voice_volume": 0.9,
	"muted": false,
	# controls
	"mouse_sensitivity": 0.0021,
	"invert_y": false,
	"gamepad_sensitivity": 2.4,
	"fov": 74.0,
	"camera_shake": 1.0,
	# graphics
	"preset": 2,
	"shadows": true,
	"ssao": true,
	"ssr": true,
	"ssil": true,
	"glow": true,
	"volumetric_fog": true,
	"render_scale": 1.0,
	"msaa": 1,
	"film_grain": true,
	"motion_blur": true,
	# display
	"fullscreen": false,
	"max_fps": 0,
	"vsync": true,
	"subtitles": true,
	"show_fps": false,
}

const PRESETS := [
	# Low
	{"shadows": false, "ssao": false, "ssr": false, "ssil": false, "glow": true,
	 "volumetric_fog": false, "render_scale": 0.75, "msaa": 0, "film_grain": false, "motion_blur": false},
	# Medium
	{"shadows": true, "ssao": false, "ssr": false, "ssil": false, "glow": true,
	 "volumetric_fog": false, "render_scale": 1.0, "msaa": 0, "film_grain": true, "motion_blur": false},
	# High
	{"shadows": true, "ssao": true, "ssr": true, "ssil": false, "glow": true,
	 "volumetric_fog": true, "render_scale": 1.0, "msaa": 1, "film_grain": true, "motion_blur": true},
	# Ultra
	{"shadows": true, "ssao": true, "ssr": true, "ssil": true, "glow": true,
	 "volumetric_fog": true, "render_scale": 1.0, "msaa": 2, "film_grain": true, "motion_blur": false},
]

const PRESET_NAMES := ["LOW", "MEDIUM", "HIGH", "ULTRA"]

var data: Dictionary = {}


func _ready() -> void:
	data = DEFAULTS.duplicate(true)
	_load()
	apply_audio()
	apply_display()
	apply_viewport()


# ---------------------------------------------------------------- accessors

func getv(key: String):
	return data.get(key, DEFAULTS.get(key))


## Keys that must reach the mixer the moment they change, whether they were set
## from the options panel, a hotkey or a headless dev flag.
const AUDIO_KEYS := ["master_volume", "music_volume", "sfx_volume",
		"ambience_volume", "voice_volume", "muted"]


func setv(key: String, value) -> void:
	if data.get(key) == value:
		return
	data[key] = value
	changed.emit()
	if key in AUDIO_KEYS:
		apply_audio()


func set_preset(index: int) -> void:
	index = clampi(index, 0, PRESETS.size() - 1)
	data["preset"] = index
	for k in PRESETS[index]:
		data[k] = PRESETS[index][k]
	changed.emit()


func preset_name() -> String:
	var p := int(getv("preset"))
	if p < 0 or p >= PRESET_NAMES.size():
		return "CUSTOM"
	return PRESET_NAMES[p]


# ------------------------------------------------------------------ saving

func save_settings() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("could not write settings")
		return
	f.store_string(JSON.stringify(data, "\t"))


func _load() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for k in parsed:
		if DEFAULTS.has(k):
			data[k] = parsed[k]


func reset_to_defaults() -> void:
	data = DEFAULTS.duplicate(true)
	apply_audio()
	apply_display()
	apply_viewport()
	changed.emit()


# ----------------------------------------------------------------- applying

## Mute for this process only.  Kept out of `data` on purpose so a headless
## capture run cannot write "muted" into the player's saved settings -- the
## settings file is written on quit, which is exactly when a capture ends.
var runtime_mute := false


func set_runtime_mute(on: bool) -> void:
	runtime_mute = on
	apply_audio()


func apply_audio() -> void:
	# A global mute has to silence every bus, not just Master: an unmuted
	# sub-bus would still feed through and the toggle would appear to do nothing.
	var muted := bool(getv("muted")) or runtime_mute
	for bus_name in ["Master", "Music", "SFX", "Ambience", "UI", "Voice"]:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx < 0:
			continue
		var v := 1.0
		match bus_name:
			"Master": v = float(getv("master_volume"))
			"Music": v = float(getv("music_volume"))
			"SFX": v = float(getv("sfx_volume"))
			"Ambience": v = float(getv("ambience_volume"))
			"UI": v = float(getv("sfx_volume"))
			"Voice": v = float(getv("voice_volume"))
		AudioServer.set_bus_mute(idx, muted or v <= 0.001)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))


## Flip the global mute and report the new state.
func toggle_mute() -> bool:
	var on := not bool(getv("muted"))
	setv("muted", on)
	return on


func apply_display() -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(getv("fullscreen")) \
			else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
	Engine.max_fps = int(getv("max_fps"))
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if bool(getv("vsync")) else DisplayServer.VSYNC_DISABLED)
	display_changed.emit()


func apply_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	vp.scaling_3d_scale = float(getv("render_scale"))
	var msaa := int(getv("msaa"))
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][clampi(msaa, 0, 3)]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if msaa == 0 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_debanding = true


## Push the quality flags into a scene's Environment.  Called by each scene
## when it builds its WorldEnvironment and again whenever settings change.
func apply_quality(env: Environment) -> void:
	if env == null:
		return
	env.ssao_enabled = bool(getv("ssao"))
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.8
	env.ssao_power = 1.6
	env.ssao_detail = 0.7
	env.ssil_enabled = bool(getv("ssil"))
	env.ssr_enabled = bool(getv("ssr"))
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.2
	env.ssr_fade_out = 1.6
	env.glow_enabled = bool(getv("glow"))
	env.volumetric_fog_enabled = bool(getv("volumetric_fog"))
	env.sdfgi_enabled = false
