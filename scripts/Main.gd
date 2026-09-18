extends Node
## Boot and top-level routing.
##
## Owns exactly one scene at a time: either the main menu or a run of the
## campaign.  Swapping always happens behind a fade so there is never a frame
## where two environments are competing for the same viewport.

const MENU_SCRIPT := "res://scripts/menu/MenuScene.gd"
const GAME_SCRIPT := "res://scripts/game/GameScene.gd"

var _current: Node = null


func _ready() -> void:
	randomize()
	Transition.set_black(true)
	Settings.apply_viewport()
	Settings.apply_audio()
	await get_tree().process_frame
	if GameManager.is_first_run() and not FileAccess.file_exists(Settings.PATH):
		Settings.save_settings()
	# developer shortcuts:  godot -- --chapter=3   |   -- --chapter=3 --capture
	var args := OS.get_cmdline_user_args()
	var capture := "--capture" in args
	var intro := "--intro" in args
	if capture:
		# automated runs must be silent, and must not persist that mute
		Settings.set_runtime_mute(true)
	for a in args:
		if a.begins_with("--chapter="):
			var idx := clampi(a.get_slice("=", 1).to_int(), 0, GameManager.CHAPTER_COUNT - 1)
			GameManager.start_new_game()
			GameManager.chapter = idx
			await _launch_run(capture, capture and intro)
			return
	await open_menu()
	await Transition.from_black(1.6)


func open_menu() -> void:
	await _swap(MENU_SCRIPT)
	var menu := _current as Node3D
	if menu == null:
		return
	menu.start_requested.connect(_on_start_requested)
	menu.quit_requested.connect(_on_quit)
	GameManager.set_state(GameManager.State.MENU)


func _on_start_requested(new_game: bool) -> void:
	GameManager.set_state(GameManager.State.CINEMATIC)
	await Transition.to_black(1.1)
	if new_game:
		GameManager.start_new_game()
	elif not GameManager.load_game():
		GameManager.start_new_game()
	await _launch_run()


func _launch_run(capture := false, force_intro := false) -> void:
	await _swap(GAME_SCRIPT)
	var game := _current
	if game == null:
		return
	game.to_menu_requested.connect(_on_to_menu)
	game.run_finished.connect(_on_run_finished)
	if force_intro:
		game.capture_intro = true
	await game.begin(GameManager.chapter, capture, force_intro)
	if capture:
		if force_intro:
			# let the intro frames land before the vantage pass overwrites them
			await get_tree().create_timer(0.5).timeout
		game.capture_views(8)
		return
	if GameManager.chapter == 0:
		await Transition.from_black(1.6)


func _on_to_menu() -> void:
	AudioDirector.stop_all()
	GameManager.set_state(GameManager.State.MENU)
	await open_menu()
	await Transition.from_black(1.2)


func _on_run_finished() -> void:
	AudioDirector.stop_all()
	GameManager.delete_save()
	GameManager.set_state(GameManager.State.MENU)
	await open_menu()
	await Transition.from_black(1.8)


func _on_quit() -> void:
	Settings.save_settings()
	AudioDirector.stop_all()
	await Transition.to_black(0.7)
	get_tree().quit()


@warning_ignore("REDUNDANT_AWAIT")
func _swap(script_path: String) -> void:
	if _current != null:
		remove_child(_current)
		_current.queue_free()
		_current = null
		AudioDirector.music("", 0.5)
		AudioDirector.stop_ambience(0.5)
		await get_tree().process_frame
	_current = load(script_path).new()
	add_child(_current)
	await get_tree().process_frame


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Settings.save_settings()
		GameManager.save_game()
