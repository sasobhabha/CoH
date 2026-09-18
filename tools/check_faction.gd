extends Node
## Resolve every archetype's palette the way the running game does and report,
## per material, the colour that actually lands on the mesh.
##
##     godot --headless --path . res://tools/check_faction.tscn
##
## The palette map tints by material-name *prefix*, so a new material -- a
## head-wrap, say -- that no branch matches silently keeps its exported colour
## and the archetype renders in the wrong army.  This reads the override each
## surface ends up with, which is the only way to catch that without eyes on it.
##
## Run as a *scene* rather than with `--script`: Enemy compiles against the
## AudioDirector autoload, and a SceneTree script runs before autoloads exist,
## so this would not even load.

const KINDS := ["trooper", "heavy", "guard"]


func _ready() -> void:
	var bad := 0
	for kind in KINDS:
		var e := Enemy.new()
		# `kind` before the add: Enemy builds its rig in _ready(), from whatever
		# kind it has by then.
		e.kind = kind
		add_child(e)
		var pal := Enemy.palette_for(kind)
		if e.rig == null:
			print("!! %s: no rig" % kind)
			bad += 1
			continue
		print("== %s  (model=%s)" % [kind, String(pal.get("model", "?"))])

		var seen := {}
		for mi in e.rig.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			if mesh == null:
				continue
			for s in mesh.get_surface_count():
				var src := mesh.surface_get_material(s)
				if src == null:
					continue
				var mname := String((src as StandardMaterial3D).resource_name).to_lower()
				if seen.has(mname):
					continue
				seen[mname] = true
				var got: Material = (mi as MeshInstance3D).get_surface_override_material(s)
				var col := "kept its own" if got == null else \
					"#" + (got as StandardMaterial3D).albedo_color.to_html(false)
				print("   %-22s %s" % [mname, col])

		# the whole point of the makeover: the wrap has to be its own colour and
		# the mark has to be the contingent's red, not fall through to the cloth
		var cloth := _html(e.rig, "cloth_")
		var wrap := _html(e.rig, "shemagh")
		var mark := _html(e.rig, "accent")
		print("   -> cloth %s  wrap %s  mark %s" % [cloth, wrap, mark])
		if wrap == "":
			print("   !! no head-wrap material on a %s" % kind)
			bad += 1
		elif wrap == cloth:
			print("   !! wrap matches the uniform: `scarf` fell through to primary")
			bad += 1
		if mark == wrap:
			print("   !! mark matches the wrap: `accent` is not resolving")
			bad += 1
		remove_child(e)
		e.queue_free()

	print("== %d problem(s)" % bad)
	get_tree().quit(1 if bad > 0 else 0)


## The albedo the rig assigned to a surface whose material name starts with
## `prefix`, or "" if nothing matched.
func _html(rig: Node, prefix: String) -> String:
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var src := mesh.surface_get_material(s)
			if src == null:
				continue
			if not String((src as StandardMaterial3D).resource_name).to_lower().begins_with(prefix):
				continue
			var got: Material = (mi as MeshInstance3D).get_surface_override_material(s)
			if got is StandardMaterial3D:
				return "#" + (got as StandardMaterial3D).albedo_color.to_html(false)
	return ""
