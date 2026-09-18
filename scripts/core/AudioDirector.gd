extends Node
## Central audio service.
##
## Owns the mixer, a pool of 2D/3D one-shot players, a two-deck music player
## for crossfades, and a set of named ambience layers that fade in and out as
## the player moves between chapters.

const DIR := "res://assets/audio/"
const POOL_FLAT := 24
const POOL_SPATIAL := 48
const BUSES := ["Music", "SFX", "Ambience", "UI", "Voice"]
const SILENT_DB := -60.0

var _cache: Dictionary = {}
var _flat: Array[AudioStreamPlayer] = []
var _spatial: Array[AudioStreamPlayer3D] = []
var _music: Array[AudioStreamPlayer] = []
var _music_deck := 0
var _music_track := ""
var _music_tween: Tween
var _ambience: Dictionary = {}
var _ambience_tweens: Array[Tween] = []
var _last_played: Dictionary = {}
var _rain: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_install_limiter()

	for i in POOL_FLAT:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_flat.append(p)

	for i in POOL_SPATIAL:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.max_distance = 70.0
		p.unit_size = 9.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.panning_strength = 1.0
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(p)
		_spatial.append(p)

	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.volume_db = SILENT_DB
		add_child(m)
		_music.append(m)

	# The rain is a permanent bed: it starts with the app and is deliberately
	# invisible to set_ambience()/stop_ambience()/stop_all(), so scene changes,
	# chapter transitions and the pause menu never interrupt it.
	_rain = AudioStreamPlayer.new()
	_rain.bus = "Ambience"
	_rain.stream = stream("amb_rain")
	_rain.volume_db = -6.0
	add_child(_rain)
	if _rain.stream != null:
		_rain.play()

	if Settings.has_signal("changed"):
		Settings.changed.connect(_on_settings_changed)


func _ensure_buses() -> void:
	for name in BUSES:
		if AudioServer.get_bus_index(name) >= 0:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, name)
		AudioServer.set_bus_send(idx, "Master")


func _install_limiter() -> void:
	## A brick-wall limiter on Master keeps layered gunfire from clipping.
	for cls in ["AudioEffectHardLimiter", "AudioEffectLimiter"]:
		if not ClassDB.class_exists(cls):
			continue
		var lim = ClassDB.instantiate(cls)
		if lim == null:
			continue
		var props := {}
		for p in lim.get_property_list():
			props[p.name] = true
		if props.has("ceiling_db"):
			lim.set("ceiling_db", -0.8)
		if props.has("threshold_db"):
			lim.set("threshold_db", -4.0)
		if props.has("pre_gain_db"):
			lim.set("pre_gain_db", 0.0)
		AudioServer.add_bus_effect(0, lim)
		return


func _on_settings_changed() -> void:
	Settings.apply_audio()
	Settings.apply_viewport()


# ------------------------------------------------------------------ streams

func stream(name: String) -> AudioStream:
	if name.is_empty():
		return null
	if _cache.has(name):
		return _cache[name]
	var s: AudioStream = null
	for ext: String in [".ogg", ".wav", ".mp3"]:
		var path: String = DIR + name + ext
		if ResourceLoader.exists(path):
			s = load(path)
			break
	if s == null:
		push_warning("AudioDirector: missing stream '%s'" % name)
		_cache[name] = null
		return null
	var loops := name.begins_with("mus_") or name.begins_with("amb_")
	if s is AudioStreamOggVorbis:
		s.loop = loops
		s.loop_offset = 0.0
	elif s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD if loops else AudioStreamWAV.LOOP_DISABLED
	_cache[name] = s
	return s


# --------------------------------------------------------------- one-shots

## Non-positional one-shot (UI, player-local sounds, music stingers).
func play(name: String, volume_db := 0.0, pitch := 1.0, jitter := 0.0, bus := "SFX") -> void:
	var s := stream(name)
	if s == null:
		return
	var p := _free_flat()
	if p == null:
		return
	p.bus = bus
	p.stream = s
	p.pitch_scale = maxf(0.05, pitch + randf_range(-jitter, jitter))
	p.volume_db = volume_db
	p.play()


## Positional one-shot.
func play_at(name: String, pos: Vector3, volume_db := 0.0, pitch := 1.0, jitter := 0.0,
		max_dist := 70.0) -> void:
	var s := stream(name)
	if s == null:
		return
	var p := _free_spatial()
	if p == null:
		return
	p.global_position = pos
	p.stream = s
	p.max_distance = max_dist
	p.pitch_scale = maxf(0.05, pitch + randf_range(-jitter, jitter))
	p.volume_db = volume_db
	p.play()


## Variation helper: picks `name_1..name_n` if those exist, else `name`.
func play_variant(base: String, count: int, volume_db := 0.0, jitter := 0.06,
		bus := "SFX") -> void:
	play("%s_%d" % [base, randi_range(1, count)], volume_db, 1.0, jitter, bus)


func play_variant_at(base: String, count: int, pos: Vector3, volume_db := 0.0,
		max_dist := 70.0) -> void:
	play_at("%s_%d" % [base, randi_range(1, count)], pos, volume_db, 1.0, 0.06, max_dist)


func _free_flat() -> AudioStreamPlayer:
	for p in _flat:
		if not p.playing:
			return p
	var victim := _flat[0]
	victim.stop()
	return victim


func _free_spatial() -> AudioStreamPlayer3D:
	for p in _spatial:
		if not p.playing:
			return p
	var victim := _spatial[0]
	victim.stop()
	return victim


# ------------------------------------------------------------------- music

func music(track: String, fade := 3.0, volume_db := 0.0) -> void:
	if track == _music_track and not track.is_empty():
		return
	_music_track = track
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	var outgoing := _music[_music_deck]
	_music_deck = 1 - _music_deck
	var incoming := _music[_music_deck]

	if track.is_empty():
		_music_tween = create_tween()
		_music_tween.tween_property(outgoing, "volume_db", SILENT_DB, fade)
		_music_tween.tween_callback(outgoing.stop)
		return

	var s := stream(track)
	if s == null:
		return
	incoming.stream = s
	incoming.volume_db = SILENT_DB
	incoming.play()
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(outgoing, "volume_db", SILENT_DB, fade)
	_music_tween.tween_property(incoming, "volume_db", volume_db, fade)
	_music_tween.chain().tween_callback(outgoing.stop)


func music_track() -> String:
	return _music_track


func duck_music(to_db := -14.0, duration := 0.4) -> void:
	var p := _music[_music_deck]
	if p.playing:
		create_tween().tween_property(p, "volume_db", to_db, duration)


func unduck_music(duration := 0.8) -> void:
	var p := _music[_music_deck]
	if p.playing:
		create_tween().tween_property(p, "volume_db", 0.0, duration)


# ---------------------------------------------------------------- ambience

func set_ambience(layers: Array, fade := 2.5) -> void:
	# "amb_rain" is owned by the permanent rain player in _ready(); chapters
	# that list it would otherwise stack a second rain layer on top of it.
	layers = layers.duplicate()
	layers.erase("amb_rain")
	for name in _ambience.keys():
		if layers.has(name):
			continue
		_release_ambience(name, fade)
	for name in layers:
		if _ambience.has(name):
			continue
		var s := stream(String(name))
		if s == null:
			continue
		var p := AudioStreamPlayer.new()
		p.bus = "Ambience"
		p.stream = s
		p.volume_db = SILENT_DB
		add_child(p)
		p.play()
		var t := create_tween()
		t.tween_property(p, "volume_db", 0.0, fade)
		_ambience[name] = p


func _release_ambience(name: String, fade: float) -> void:
	var p: AudioStreamPlayer = _ambience.get(name)
	_ambience.erase(name)
	if p == null:
		return
	var t := create_tween()
	t.tween_property(p, "volume_db", SILENT_DB, fade)
	t.tween_callback(p.stop)
	t.tween_callback(p.queue_free)


func stop_ambience(fade := 2.0) -> void:
	for name in _ambience.keys():
		_release_ambience(name, fade)


func stop_all() -> void:
	music("", 0.6)
	stop_ambience(0.6)
	for p in _flat:
		p.stop()
	for p in _spatial:
		p.stop()
