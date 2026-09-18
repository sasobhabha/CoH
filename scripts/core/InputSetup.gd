class_name InputSetup
## Builds the whole InputMap in code.
##
## Keeping the bindings here rather than in project.godot means the defaults
## are version-controlled next to the gameplay code that consumes them, and
## we can bind physical keycodes (so WASD works on AZERTY) plus full gamepad
## support in one pass.

const DEADZONE := 0.22


static func install() -> void:
	# --- movement ---------------------------------------------------------
	# Arrow keys as well as WASD: they are what a first-time player reaches for,
	# and nothing else in the game claims them (the menus use the engine's ui_*
	# actions, and movement is blocked while a menu is up).
	key("move_forward", [KEY_W, KEY_UP], [JOY_BUTTON_DPAD_UP])
	key("move_back", [KEY_S, KEY_DOWN], [JOY_BUTTON_DPAD_DOWN])
	key("move_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT])
	key("move_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT])
	axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	axis("move_right", JOY_AXIS_LEFT_X, 1.0)

	key("jump", [KEY_SPACE], [JOY_BUTTON_A])
	key("sprint", [KEY_SHIFT], [JOY_BUTTON_LEFT_STICK])
	key("crouch", [KEY_CTRL, KEY_C], [JOY_BUTTON_B])

	# --- camera -----------------------------------------------------------
	axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	mouse("camera_reset", [MOUSE_BUTTON_MIDDLE])

	# --- combat -----------------------------------------------------------
	mouse("fire", [MOUSE_BUTTON_LEFT])
	axis("fire", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	mouse("aim", [MOUSE_BUTTON_RIGHT])
	axis("aim", JOY_AXIS_TRIGGER_LEFT, 1.0)
	key("reload", [KEY_R], [JOY_BUTTON_X])
	key("melee", [KEY_V], [JOY_BUTTON_RIGHT_STICK])
	key("flashlight", [KEY_F], [JOY_BUTTON_DPAD_RIGHT])

	# --- interaction ------------------------------------------------------
	key("interact", [KEY_E], [JOY_BUTTON_Y])
	key("radial", [KEY_TAB, KEY_Q], [])
	key("hide", [KEY_E], [])

	# --- system -----------------------------------------------------------
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.keycode = KEY_ESCAPE
	add("pause", [esc, button(JOY_BUTTON_START)])
	key("hud_toggle", [KEY_H], [])
	key("fps_toggle", [KEY_F4], [])
	key("screenshot", [KEY_F2], [])
	key("mute_toggle", [KEY_M], [JOY_BUTTON_RIGHT_SHOULDER])
	# Undocumented cheat: blink to the crosshair.  Deliberately absent from the
	# options screen, the key hints and the input-audit tool.
	key("warp", [KEY_F3], [])


# ---------------------------------------------------------------- internals

static func add(action: String, events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, DEADZONE)
	else:
		InputMap.action_erase_events(action)
	for e in events:
		InputMap.action_add_event(action, e)


static func key(action: String, keys: Array, pads: Array) -> void:
	var events: Array = []
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		events.append(e)
	for b in pads:
		events.append(button(b))
	if events.is_empty():
		return
	if InputMap.has_action(action):
		for e in events:
			InputMap.action_add_event(action, e)
	else:
		add(action, events)


static func mouse(action: String, buttons: Array) -> void:
	var events: Array = []
	for b in buttons:
		var e := InputEventMouseButton.new()
		e.button_index = b
		events.append(e)
	add(action, events)


static func axis(action: String, joy_axis: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = joy_axis
	e.axis_value = value
	if not InputMap.has_action(action):
		InputMap.add_action(action, DEADZONE)
	InputMap.action_add_event(action, e)


static func button(b: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	return e


## Human-readable key hint for the HUD, resolved at runtime.
static func hint(action: String) -> String:
	var names := {
		"interact": "E", "reload": "R", "jump": "SPACE", "sprint": "SHIFT",
		"crouch": "CTRL", "aim": "RMB", "fire": "LMB", "radial": "TAB",
		"flashlight": "F", "melee": "V", "pause": "ESC", "hide": "E",
		"mute_toggle": "M",
	}
	return names.get(action, action.to_upper())
