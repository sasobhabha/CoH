extends Node
## Drive a real Player through firing and reloading, and read what the HUD puts
## on screen, to prove unlimited ammo actually behaves.
##
##     godot --headless --path . res://tools/check_ammo.tscn
##
## "The reserve is never spent" is one branch inside a 700-line character, so
## reading it is not evidence.  This fires the weapon, empties the magazine,
## reloads, and repeats for a few hundred rounds -- then checks the reserve has
## not moved and the magazine refilled, and that the HUD is honest about it.
##
## A scene rather than `--script`, because Player compiles against the Settings
## and AudioDirector autoloads.

const FIRINGS := 300


func _ready() -> void:
	var bad := 0
	var p := Player.new()
	add_child(p)

	print("== unlimited=%s  mag=%d  reserve=%d"
			% [Player.UNLIMITED_AMMO, p.mag, p.reserve])
	if not Player.UNLIMITED_AMMO:
		print("!! this check assumes UNLIMITED_AMMO is on")
		get_tree().quit(1)
		return

	var start_reserve := p.reserve
	var shots := 0
	var reloads := 0
	# Fire the magazine dry, reload, and repeat well past any finite reserve.
	while shots < FIRINGS:
		if p.mag <= 0:
			p.start_reload()
			if not p._reloading:
				print("!! could not start a reload with the magazine empty")
				bad += 1
				break
			# push the reload past its duration; _update_weapon returns once it
			# completes, which is the path the real game runs every frame
			p._update_weapon(Player.RELOAD_TIME + 0.05)
			reloads += 1
			if p.mag != Player.MAG_SIZE:
				print("!! reload left the magazine at %d, not %d" % [p.mag, Player.MAG_SIZE])
				bad += 1
				break
			continue
		p._fire()
		shots += 1

	print("   fired %d rounds in %d reloads  -> mag=%d reserve=%d (started %d)"
			% [shots, reloads, p.mag, p.reserve, start_reserve])
	if p.reserve != start_reserve:
		print("!! the reserve moved: %d -> %d" % [start_reserve, p.reserve])
		bad += 1
	if reloads < FIRINGS / Player.MAG_SIZE - 1:
		print("!! only %d reloads for %d rounds" % [reloads, shots])
		bad += 1

	# A crate should still do something worth walking to.
	p.mag = 4
	p.give_ammo(90)
	print("   crate -> mag=%d" % p.mag)
	if p.mag != Player.MAG_SIZE:
		print("!! a crate no longer tops the magazine up")
		bad += 1

	# And the HUD has to say so, not print a number that never changes.
	var hud := HUD.new()
	add_child(hud)
	hud._on_ammo(12, start_reserve)
	var shown: String = hud._reserve_label.text
	print("   hud reserve reads %s" % shown)
	if not Player.UNLIMITED_AMMO and not shown.contains("%d" % start_reserve):
		print("!! finite reserve not shown: %s" % shown)
		bad += 1
	if Player.UNLIMITED_AMMO and shown.contains("%d" % start_reserve):
		print("!! HUD still prints a finite reserve while the reserve is unlimited")
		bad += 1

	print("== %d problem(s)" % bad)
	get_tree().quit(1 if bad > 0 else 0)
