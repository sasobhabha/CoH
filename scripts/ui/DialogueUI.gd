class_name DialogueUI
extends Control
## Bottom-screen dialogue with a typewriter reveal.
##
## `play()` takes an array of {speaker, text, hold} beats and walks through
## them, emitting `finished` at the end.  Input advance / skip is handled here
## so callers can simply await the signal.

signal finished

const CPS := 52.0

var _panel: PanelContainer
var _speaker: Label
var _body: RichTextLabel
var _hint: Label
var _lines: Array = []
var _index := 0
var _reveal := 0.0
var _open := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.position = Vector2(-480, -276)
	_panel.custom_minimum_size = Vector2(960, 0)
	_panel.add_theme_stylebox_override("panel",
			UI.panel(Color(0.015, 0.02, 0.026, 0.86), 2, 1, Color(1, 1, 1, 0.10)))
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)

	_speaker = UI.label("", UI.SIZE_SMALL, UI.AMBER, 5.0, 0.35)
	box.add_child(_speaker)
	box.add_child(UI.hrule(900, Color(1, 1, 1, 0.14)))

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = false
	_body.scroll_active = false
	_body.custom_minimum_size = Vector2(920, 104)
	_body.add_theme_font_override("normal_font", UI.font(0.4))
	_body.add_theme_font_size_override("normal_font_size", 20)
	_body.add_theme_color_override("default_color", UI.TEXT)
	box.add_child(_body)

	_hint = UI.label("[E] continue", UI.SIZE_SMALL, UI.FAINT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_hint)

	set_process(true)


func is_open() -> bool:
	return _open


func play(lines: Array) -> void:
	_lines = lines
	_index = 0
	_open = true
	visible = true
	AudioDirector.duck_music(-16.0, 0.4)
	_show_line()


func _show_line() -> void:
	if _index >= _lines.size():
		_close()
		return
	var line: Dictionary = _lines[_index]
	_speaker.text = String(line.get("speaker", "")).to_upper()
	_body.text = String(line.get("text", ""))
	_body.visible_characters = 0
	_reveal = 0.0


func _close() -> void:
	_open = false
	visible = false
	AudioDirector.unduck_music(0.9)
	finished.emit()


func skip_or_advance() -> void:
	if not _open:
		return
	var line: Dictionary = _lines[_index]
	var full := String(line.get("text", ""))
	if _body.visible_characters < full.length() and _body.visible_characters >= 0:
		_body.visible_characters = -1
		return
	_index += 1
	AudioDirector.play("ui_click", -12.0, 1.0, 0.05, "UI")
	_show_line()


func _process(delta: float) -> void:
	if not _open:
		return
	var line: Dictionary = _lines[_index] if _index < _lines.size() else {}
	var full := String(line.get("text", ""))
	if _body.visible_characters < 0 or _body.visible_characters >= full.length():
		_hint.text = "[E] continue  %d/%d" % [_index + 1, _lines.size()]
		return
	var before := _body.visible_characters
	_reveal += delta * CPS
	_body.visible_characters = mini(int(_reveal), full.length())
	if int(_reveal) > before and int(_reveal) % 3 == 0:
		AudioDirector.play("ui_hover", -24.0, 1.35, 0.20, "Voice")


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
			or event.is_action_pressed("fire"):
		get_viewport().set_input_as_handled()
		skip_or_advance()
