extends SceneTree
## Does the HUD's font actually have the glyphs the HUD wants to draw?
##
##     godot --headless --path . --script res://tools/check_glyph.gd
##
## The HUD draws with Godot's fallback font, not a shipped one, so a character
## that looks fine in an editor can come out as a tofu box on screen.  This has
## no autoload dependency, so it can run as a plain script.

const WANTED := {
	0x221E: "infinity, for an unlimited reserve",
	0x00D7: "multiplication sign",
	0x2014: "em dash",
	0x00B7: "middle dot",
}


func _initialize() -> void:
	var f := ThemeDB.fallback_font
	if f == null:
		print("no fallback font")
		quit(1)
		return
	print("fallback font: %s (%d chars mapped)" % [f.get_font_name(), f.get_supported_chars().length()])
	for cp in WANTED:
		print("   U+%04X  %-32s %s" % [cp, String.chr(cp), "yes" if f.has_char(cp) else "NO"])
	quit()
