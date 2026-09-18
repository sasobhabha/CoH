class_name RadialMenu
extends Control
## The interaction wheel: hold the key, flick the mouse, release.
##
## The mouse stays captured while the wheel is open, so selection comes from
## accumulated mouse motion rather than a cursor position.  The selection
## vector drifts back toward the centre, which means the wheel always starts
## unselected and you can cancel by returning to the middle.

signal chosen(id: String)
signal cancelled

const CENTER_DEADZONE := 24.0
const MAX_REACH := 150.0
const INNER := 38.0
const OUTER := 92.0

var _options: Array = []          # [{id, label, hint}]
var _caption := ""
var _sel := Vector2.ZERO
var _open := false
var _hover := -1
var _font: Font
var _opened_frame := -1          # process frame the wheel was opened on


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_font = UI.font(3.0, 0.3)
	set_process(true)


func open(options: Array, caption := "") -> void:
	_options = options
	_caption = caption
	_sel = Vector2.ZERO
	_hover = -1
	_open = true
	_opened_frame = Engine.get_process_frames()
	visible = true
	queue_redraw()


func close() -> void:
	_open = false
	visible = false
	_sel = Vector2.ZERO
	_hover = -1
	AudioDirector.play("ui_back", -10.0, 1.0, 0.0, "UI")


func is_open() -> bool:
	return _open


func selected_id() -> String:
	if _hover < 0 or _hover >= _options.size():
		return ""
	return String(_options[_hover].get("id", ""))


func _process(delta: float) -> void:
	if not _open:
		return
	# drift the selection back so the wheel re-centres itself
	_sel = _sel.lerp(Vector2.ZERO, minf(1.0, delta * 2.4))
	var old := _hover
	_hover = _pick()
	if _hover != old and _hover >= 0:
		AudioDirector.play("ui_hover", -18.0, 1.0, 0.05, "UI")
	queue_redraw()


func _pick() -> int:
	if _sel.length() < CENTER_DEADZONE or _options.size() == 0:
		return -1
	var ang := atan2(_sel.y, _sel.x)
	var n := _options.size()
	var step := TAU / float(n)
	# option 0 sits at the top and proceeds clockwise
	var rel := wrapf(ang + PI / 2.0, -PI, PI)
	var idx := int(round(rel / step))
	return ((idx % n) + n) % n


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseMotion:
		_sel += Vector2(event.relative.x, event.relative.y)
		if _sel.length() > MAX_REACH:
			_sel = _sel.normalized() * MAX_REACH
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadMotion and event.axis in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
		if event.axis == JOY_AXIS_RIGHT_X:
			_sel.x += event.axis_value * 9.0
		else:
			_sel.y += event.axis_value * 9.0
		if _sel.length() > MAX_REACH:
			_sel = _sel.normalized() * MAX_REACH
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("radial") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel()
	elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		# The wheel is usually opened with E, so E has to close it too.  Swallow
		# the press that opened it, though: depending on event ordering it can
		# arrive here on the very frame `open()` ran, and committing on it would
		# close the wheel before the player ever saw it.
		if Engine.get_process_frames() == _opened_frame:
			return
		get_viewport().set_input_as_handled()
		if _hover >= 0:
			confirm()
		else:
			cancel()
	elif event is InputEventJoypadButton and event.pressed \
			and event.button_index == JOY_BUTTON_B:
		# gamepad B, matching every other wheel's "back" button
		get_viewport().set_input_as_handled()
		dismiss()
	elif event is InputEventMouseButton and event.pressed:
		# The cursor is captured while the wheel is up, so a click commits the
		# wedge under the flick vector rather than under a pointer.  With
		# nothing selected a click still closes the wheel -- back out rather
		# than swallow the click and leave the player staring at a dead menu.
		get_viewport().set_input_as_handled()
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _hover >= 0:
				confirm()
			else:
				cancel()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			dismiss()


func cancel() -> void:
	var id := selected_id()
	close()
	if id.is_empty():
		cancelled.emit()
	else:
		chosen.emit(id)


## Commit the hovered wedge outright.  Kept separate from `cancel()`, which
## quietly becomes a cancel when the wheel is centred.
func confirm() -> void:
	if _hover < 0:
		return
	var id := selected_id()
	close()
	if not id.is_empty():
		chosen.emit(id)


## Back out with no choice made, whatever is hovered.
func dismiss() -> void:
	close()
	cancelled.emit()


func _draw() -> void:
	if not _open:
		return
	var c := size * 0.5
	var n := maxi(_options.size(), 1)
	var step := TAU / float(n)

	draw_circle(c, OUTER + 16.0, Color(0.02, 0.025, 0.03, 0.55))

	for i in n:
		var mid := -PI / 2.0 + step * float(i)
		var half := step * 0.42
		var selected := i == _hover
		var col := Color(0.06, 0.07, 0.085, 0.86)
		if selected:
			col = Color(UI.AMBER.r, UI.AMBER.g, UI.AMBER.b, 0.30)
		var pts := PackedVector2Array()
		pts.append(c + Vector2(cos(mid - half), sin(mid - half)) * INNER)
		for k in range(13):
			var a := mid - half + (half * 2.0) * float(k) / 12.0
			pts.append(c + Vector2(cos(a), sin(a)) * OUTER)
		pts.append(c + Vector2(cos(mid + half), sin(mid + half)) * INNER)
		draw_colored_polygon(pts, col)
		var edge := Color(1, 1, 1, 0.10)
		if selected:
			edge = Color(UI.AMBER.r, UI.AMBER.g, UI.AMBER.b, 0.95)
		draw_polyline(pts, edge, 2.0)

		# label
		var label := String(_options[i].get("label", "")).to_upper()
		var fsz := 19
		var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
		var lpos := c + Vector2(cos(mid), sin(mid)) * (OUTER + 6.0)
		var tcol := UI.TEXT if not selected else UI.AMBER
		draw_string(_font, lpos + Vector2(-tw * 0.5, 6.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, tcol)

		var hint := String(_options[i].get("hint", ""))
		if not hint.is_empty():
			var hw := _font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(_font, lpos + Vector2(-hw * 0.5, 24.0), hint,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.FAINT)

	# centre pip
	var pip := 5.0 + minf(_sel.length(), MAX_REACH) * 0.04
	if _hover < 0:
		draw_circle(c, pip, Color(0.75, 0.8, 0.85, 0.5))
	else:
		draw_circle(c, pip, UI.AMBER)
	if not _caption.is_empty():
		var cw := _font.get_string_size(_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(_font, c + Vector2(-cw * 0.5, INNER - 16.0), _caption,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.DIM)
