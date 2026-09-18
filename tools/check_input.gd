extends SceneTree
## Prints what InputSetup actually installed.
##
## Bindings are built in code rather than declared in project.godot, which
## means a typo is invisible until someone presses the key.  This makes the
## whole map checkable from the terminal:
##
##   godot --headless --path . --script res://tools/check_input.gd

func _init() -> void:
	InputSetup.install()
	for a in ["move_forward", "move_back", "move_left", "move_right", "jump",
			"sprint", "crouch", "fire", "aim", "reload", "melee", "flashlight",
			"interact", "radial", "pause", "mute_toggle", "hud_toggle",
			"fps_toggle", "screenshot"]:
		var names: Array = []
		for e in InputMap.action_get_events(a):
			if e is InputEventKey:
				names.append(OS.get_keycode_string(e.physical_keycode))
			elif e is InputEventMouseButton:
				names.append("mouse%d" % e.button_index)
			elif e is InputEventJoypadButton:
				names.append("pad%d" % e.button_index)
			elif e is InputEventJoypadMotion:
				names.append("axis%d%+.0f" % [e.axis, e.axis_value])
		print("%-14s %s" % [a, ", ".join(names) if names else "(unbound)"])
	quit()
