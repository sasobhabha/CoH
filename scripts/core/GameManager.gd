extends Node
## Run state: which chapter we are in, what the player is being asked to do,
## progress statistics and persistence.

signal objectives_changed
signal objective_completed(id: String)
signal toast(text: String)
signal chapter_completed(index: int)

enum State { BOOT, MENU, PLAYING, PAUSED, CINEMATIC, DEAD, COMPLETE }

const SAVE_PATH := "user://monolith_save.json"
const SAVE_VERSION := 1
const CHAPTER_COUNT := 5

const CHAPTERS := [
	{
		"title": "CHAPTER I",
		"name": "THE OCCUPIED PLAZA",
		"music": "mus_explore",
		"ambience": ["amb_city", "amb_wind", "amb_embers"],
		"brief": "They took the square and hung their face over it.",
	},
	{
		"title": "CHAPTER II",
		"name": "THE TAVERN AT KILOMETER NINE",
		"music": "mus_menu",
		"ambience": ["amb_interior", "amb_wind"],
		"brief": "The only warm room left on this side of the water.",
	},
	{
		"title": "CHAPTER III",
		"name": "THE FLOOD MARKET",
		"music": "mus_combat",
		"ambience": ["amb_rain", "amb_water"],
		"brief": "They hold the market. They are not going to share it.",
	},
	{
		"title": "CHAPTER IV",
		"name": "THE DARK",
		"music": "mus_stealth",
		"ambience": ["amb_interior", "amb_embers"],
		"brief": "No rifle. No light. Somewhere above, the archive.",
	},
	{
		"title": "CHAPTER V",
		"name": "THE MEADOW",
		"music": "mus_meadow",
		"ambience": ["amb_meadow"],
		"brief": "Off the concrete, into the open.",
	},
]

const DEFAULT_STATS := {
	"shots_fired": 0,
	"shots_hit": 0,
	"kills": 0,
	"deaths": 0,
	"damage_taken": 0.0,
	"playtime": 0.0,
	"started": "",
}

var state: State = State.BOOT
var chapter := 0
var objectives: Array = []          # [{id, text, done}]
var stats: Dictionary = {}
var difficulty := 1

var _first_run := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InputSetup.install()
	stats = DEFAULT_STATS.duplicate(true)


func _process(delta: float) -> void:
	if state == State.PLAYING:
		stats["playtime"] = float(stats.get("playtime", 0.0)) + delta


# ---------------------------------------------------------------- new / load

func start_new_game() -> void:
	stats = DEFAULT_STATS.duplicate(true)
	stats["started"] = Time.get_datetime_string_from_system()
	chapter = 0
	objectives = []
	_first_run = false
	state = State.PLAYING


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> bool:
	var payload := {
		"version": SAVE_VERSION,
		"chapter": chapter,
		"objectives": objectives,
		"stats": stats,
		"saved_at": Time.get_datetime_string_from_system(),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("GameManager: could not write save")
		return false
	f.store_string(JSON.stringify(payload, "\t"))
	toast_message("PROGRESS SAVED")
	return true


func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	if int(parsed.get("version", 0)) != SAVE_VERSION:
		return false
	chapter = clampi(int(parsed.get("chapter", 0)), 0, CHAPTER_COUNT - 1)
	objectives = parsed.get("objectives", [])
	var loaded: Dictionary = parsed.get("stats", {})
	stats = DEFAULT_STATS.duplicate(true)
	for k in loaded:
		stats[k] = loaded[k]
	_first_run = false
	state = State.PLAYING
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func is_first_run() -> bool:
	return _first_run


# ---------------------------------------------------------------- objectives

func set_objectives(list: Array) -> void:
	objectives = []
	for entry in list:
		objectives.append({
			"id": String(entry.get("id", "")),
			"text": String(entry.get("text", "")),
			"done": bool(entry.get("done", false)),
		})
	objectives_changed.emit()


func push_objective(id: String, text: String) -> void:
	if find_objective(id) != null:
		return
	objectives.append({"id": id, "text": text, "done": false})
	objectives_changed.emit()
	toast_message(text)


func find_objective(id: String) -> Variant:
	for o in objectives:
		if o.get("id") == id:
			return o
	return null


func is_done(id: String) -> bool:
	var o = find_objective(id)
	return o != null and bool(o.get("done", false))


func complete_objective(id: String) -> void:
	var o = find_objective(id)
	if o == null or bool(o.get("done", false)):
		return
	o["done"] = true
	objectives_changed.emit()
	objective_completed.emit(id)
	AudioDirector.play("objective", -4.0, 1.0, 0.0, "UI")


## Next unfinished objective, or an empty string when the list is clear.
func active_objective() -> String:
	for o in objectives:
		if not bool(o.get("done", false)):
			return String(o.get("text", ""))
	return ""


func objective_progress() -> Vector2:
	var done := 0
	for o in objectives:
		if bool(o.get("done", false)):
			done += 1
	return Vector2(done, objectives.size())


# ------------------------------------------------------------------- state

func set_state(s: State) -> void:
	state = s


func set_paused(paused: bool) -> void:
	get_tree().paused = paused
	state = State.PAUSED if paused else State.PLAYING
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED


func chapter_info(index: int) -> Dictionary:
	return CHAPTERS[clampi(index, 0, CHAPTERS.size() - 1)]


func toast_message(text: String) -> void:
	toast.emit(text)


func add_stat(key: String, amount: float) -> void:
	stats[key] = float(stats.get(key, 0.0)) + amount


func accuracy() -> float:
	var shots := float(stats.get("shots_fired", 0.0))
	if shots <= 0.0:
		return 0.0
	return clampf(float(stats.get("shots_hit", 0.0)) / shots, 0.0, 1.0)
