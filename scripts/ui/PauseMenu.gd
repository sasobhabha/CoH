class_name PauseMenu
extends Control
## Pause screen: mission status, options, save, and a way out.

signal resumed
signal quit_to_menu

var options: OptionsPanel
var _stats_box: VBoxContainer
var _resume_button: Button


func _ready() -> void:
	# UI must keep processing while the tree is paused -- that is the whole job
	# of a pause menu.  Set here so the class cannot be broken by a parent
	# forgetting to override its process mode.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.02, 0.026, 0.86)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 150)
	margin.add_theme_constant_override("margin_right", 150)
	margin.add_theme_constant_override("margin_top", 110)
	margin.add_theme_constant_override("margin_bottom", 90)
	add_child(margin)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 90)
	margin.add_child(cols)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size = Vector2(420, 0)
	cols.add_child(left)
	left.add_child(UI.title("PAUSED", 58))
	left.add_child(UI.hrule(360, Color(UI.AMBER.r, UI.AMBER.g, UI.AMBER.b, 0.5)))
	left.add_child(UI.hsep(18))

	_resume_button = UI.button("RESUME", 24)
	_resume_button.pressed.connect(func(): AudioDirector.play("ui_confirm", -5.0, 1.0, 0.0, "UI"); resumed.emit())
	left.add_child(_resume_button)
	var opt := UI.button("OPTIONS", 24)
	opt.pressed.connect(func():
		AudioDirector.play("ui_click", -8.0, 1.0, 0.0, "UI")
		options.open())
	left.add_child(opt)
	var save := UI.button("SAVE PROGRESS", 24)
	save.pressed.connect(func():
		AudioDirector.play("ui_confirm", -5.0, 1.0, 0.0, "UI")
		GameManager.save_game()
		_refresh_stats())
	left.add_child(save)
	var quit := UI.button("QUIT TO MENU", 24, UI.BLOOD)
	quit.pressed.connect(func():
		AudioDirector.play("ui_back", -5.0, 1.0, 0.0, "UI")
		quit_to_menu.emit())
	left.add_child(quit)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size = Vector2(420, 0)
	cols.add_child(right)
	right.add_child(UI.section("mission status"))
	_stats_box = VBoxContainer.new()
	_stats_box.add_theme_constant_override("separation", 6)
	right.add_child(_stats_box)
	right.add_child(UI.hsep(10))
	right.add_child(UI.label("ESC  resume          TAB  radial menu", UI.SIZE_SMALL, UI.FAINT))

	options = OptionsPanel.new()
	options.closed.connect(func():
		if visible:
			_resume_button.call_deferred("grab_focus"))
	add_child(options)


func open() -> void:
	visible = true
	_refresh_stats()
	_resume_button.call_deferred("grab_focus")
	AudioDirector.play("ui_tab", -8.0, 1.0, 0.0, "UI")


func close() -> void:
	visible = false


func _refresh_stats() -> void:
	for c in _stats_box.get_children():
		_stats_box.remove_child(c)
		c.queue_free()
	var info := GameManager.chapter_info(GameManager.chapter)
	var rows := [
		["CHAPTER", "%s — %s" % [info.get("title", ""), info.get("name", "")]],
		["OBJECTIVE", GameManager.active_objective() if not GameManager.active_objective().is_empty() else "complete"],
		["TIME", UI.format_time(float(GameManager.stats.get("playtime", 0.0)))],
		["KILLS", str(int(GameManager.stats.get("kills", 0)))],
		["ACCURACY", "%d%%" % roundi(GameManager.accuracy() * 100.0)],
		["DEATHS", str(int(GameManager.stats.get("deaths", 0)))],
	]
	for r in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var k := UI.label(String(r[0]), UI.SIZE_SMALL, UI.FAINT, 3.0, 0.3)
		k.custom_minimum_size = Vector2(130, 0)
		row.add_child(k)
		var v := UI.label(String(r[1]), 18, UI.TEXT)
		row.add_child(v)
		_stats_box.add_child(row)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or options.visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		resumed.emit()
