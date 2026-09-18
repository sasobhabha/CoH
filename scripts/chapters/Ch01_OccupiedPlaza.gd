extends Chapter
## CHAPTER I -- THE OCCUPIED PLAZA
##
## Layout, walking north to south:
##
##   z = +100 .. +40   the suburb: shattered houses, burnt yards, dead cars
##   z =  +40 .. -24   the avenue: gutted mid-rise, hung banners, a checkpoint
##   z =  -24 .. -104  the sunken expressway, 2.6 m down and bone dry
##   z = -104 .. -214  the occupied plaza: the monument, the balloon over it,
##                     the camp, the patrols, and the way out
##
## Two kinds of geometry live here, on purpose.  Everything that *repeats* --
## facades, barriers, tents, props, rubble -- is procedural (`Kit.gd`) and baked
## into a handful of merged meshes, which is why a whole district costs under a
## thousand draw calls.  The four pieces that carry the scene's identity -- the
## pale monument, the tethered portrait balloon, the checkpoints and the signage
## -- are authored in Blender (`tools/gen_env.py`) and placed through `EnvKit`,
## because a hero silhouette is the one thing a box generator cannot invent.
##
## Art direction comes from `.concept/reference/2050-shotlist.md`: the occupied
## square under a red portrait balloon, the pale monument carrying the
## occupier's banner, a burning tower on the skyline, and pontoons of dead
## traffic on the way in.  There is no water in any of it.

const ROAD_HALF := 15.0
const WALK_EDGE := 19.0
const SUNK_Y := -2.6
const SUNK_FROM := -24.0
const SUNK_TO := -104.0
const PLAZA_FROM := -104.0
const PLAZA_TO := -214.0
const MONUMENT_Z := -176.0
const GATE_Z := 18.0            ## the checkpoint in the avenue
const PLAZA_GATE_Z := -108.0    ## the checkpoint you pass to enter the plaza
const MONUMENT_HEALTH := 600.0  ## ~24 rifle hits (BODY_DAMAGE 24) to bring it down

var _monument: Node3D
var _balloon: Node3D
var _squad: Array = []
var _monument_lights: Array = []
var _gates: Array = []


func describe() -> void:
	_spawn = Vector3(0, 0.5, 96.0)
	_spawn_yaw = 0.0
	AudioDirector.music("mus_explore", 3.0, -12.0)
	AudioDirector.set_ambience(["amb_city", "amb_wind", "amb_embers"], 3.0)
	GameManager.set_objectives([
		{"id": "advance", "text": "Get through the checkpoint"},
		{"id": "clear", "text": "Clear the expressway"},
		{"id": "monument", "text": "Destroy the monument"},
	])


func build() -> void:
	_ground()
	_suburb()
	_avenue()
	_expressway()
	_plaza()
	_skyline()
	_weather_and_lights()
	_enemies()
	_triggers()


func _commit(mb: MeshBuilder, name: String, collide := true) -> void:
	if not mb.is_empty():
		mb.commit(structures(), name, collide)


# ------------------------------------------------------------------- ground

func _ground() -> void:
	# avenue deck and sidewalk aprons
	plate(Vector2(30, 150), 0.0, 47.0, MatLib.road(), 1.4)
	for side in [-1.0, 1.0]:
		var s := float(side)
		plate(Vector2(4.2, 150), 0.24, 47.0, MatLib.ground_plane("concrete_floor", 0.36), 2.6)
		Build.box(structures(), Vector3(0.5, 0.30, 150), Vector3(s * ROAD_HALF, 0.15, 47.0),
				MatLib.concrete())
	# the plaza apron, and the sunken expressway between the two
	plate(Vector2(96, PLAZA_TO * -1.0 + SUNK_TO - 4.0), 0.0, (SUNK_TO + PLAZA_TO) * 0.5,
			MatLib.ground_plane("concrete_floor", 0.31), 1.6)
	plate(Vector2(64, absf(SUNK_TO - SUNK_FROM) + 6.0), SUNK_Y, (SUNK_FROM + SUNK_TO) * 0.5,
			MatLib.ground_plane("asphalt", 0.20), 3.0)

	# ramps into and out of the cut.  They have to START on the road and END
	# past the deck edges: the road deck runs to z = -28 and the plaza apron
	# starts at z = -107, so the old short ramps floated between the two and
	# presented an unclimbable 2.6 m face at each end.  A 16 m run at the cut's
	# 2.6 m depth puts both ramp mouths flush with the surfaces they join.
	_ramp(Vector3(0, 0, -28.1), 30.0, 16.0, SUNK_Y)
	_ramp(Vector3(0, 0, -99.0), 30.0, 16.0, -SUNK_Y)

	# road markings, crosswalks, drains -- the paint is old and half worn away
	var mb := MeshBuilder.new()
	var paint := Kit.flat(Color(0.66, 0.63, 0.55), 0.7)
	var z := 110.0
	while z > SUNK_FROM + 10.0:
		mb.box_at(Vector3(0, 0.05, z), Vector3(0.22, 0.03, 3.0), paint)
		z -= 7.5
	for cz in [64.0, 20.0, -8.0]:
		for i in 9:
			mb.box_at(Vector3(-13.0 + float(i) * 3.25, 0.05, cz), Vector3(1.9, 0.03, 4.4), paint)
	for dz in [30.0, -2.0, -20.0]:
		mb.box_at(Vector3(ROAD_HALF - 0.9, 0.10, dz), Vector3(0.6, 0.06, 1.0),
				Kit.m("steel_rust"))
	_commit(mb, "RoadMarkings", false)

	_far_ground()

	# ash and soot drifted along the kerbs -- the district's version of standing
	# water, and the reason the road reads as burnt rather than merely wet
	var dust := MeshBuilder.new()
	var soot := MatLib.standard("kerb_soot", Color(0.11, 0.105, 0.10), 0.92, 0.0,
			"dirt", 5.0)
	var r := RandomNumberGenerator.new()
	r.seed = 606
	for i in 30:
		var sz := 102.0 - float(i) * 4.4
		for side in [-1.0, 1.0]:
			var s := float(side)
			dust.box_at(Vector3(s * 13.4, 0.035, sz + sin(float(i) * 2.1) * 1.4),
					Vector3(r.randf_range(1.2, 2.6), 0.02, r.randf_range(1.8, 3.4)), soot,
					Vector3(0, r.randf_range(0, 40), 0))
	_commit(dust, "SootDrifts", false)


## Terrain outside the district.
##
## This has to be a *ring*, not one slab: the expressway is a cut 2.6 m below
## street level, so any plane big enough to reach the horizon would either fill
## the cut or leave the avenue standing on a plinth.
func _far_ground() -> void:
	var mb := MeshBuilder.new()
	var mat := MatLib.ground_plane("gravel", 0.15)
	var top := -0.30
	var xin := 52.0
	var ztop := 132.0
	var zbot := -224.0
	for side in [-1.0, 1.0]:
		var s := float(side)
		mb.box_at(Vector3(s * (xin + 430.0), top - 1.5, (ztop + zbot) * 0.5),
				Vector3(860.0, 3.0, 1400.0), mat)
	mb.box_at(Vector3(0, top - 1.5, ztop + 430.0),
			Vector3(xin * 2.0 + 900.0, 3.0, 860.0), mat)
	mb.box_at(Vector3(0, top - 1.5, zbot - 430.0),
			Vector3(xin * 2.0 + 900.0, 3.0, 860.0), mat)
	_commit(mb, "FarGround", false)

	# Backfill under the district.  The road, the sidewalks and the plaza apron
	# are narrow slabs; everything between them and the far-ground ring used to
	# be void, so one step off the pavement was a 40 m fall -- and the houses
	# and ruins stood over open air.  These boxes floor the whole interior up
	# to the ring, stopping only where the expressway cut has its own floor.
	# Tops sit just under the road decks so nothing pokes through them.
	var fill := MatLib.ground_plane("gravel", 0.15)
	# suburb + avenue, both sides of the road
	Build.box(structures(), Vector3(103.8, 3.0, 146.9), Vector3(0, -1.6, 58.45), fill)
	# the plaza's flanks, and the strips past the apron's ends
	Build.box(structures(), Vector3(103.8, 3.0, 119.9), Vector3(0, -1.6, -163.95), fill)
	# street-level terraces beside the cut: the byways the district never had
	Build.box(structures(), Vector3(19.9, 3.0, 92.0), Vector3(41.95, -1.6, -61.0), fill)
	Build.box(structures(), Vector3(19.9, 3.0, 92.0), Vector3(-41.95, -1.6, -61.0), fill)
	# the pockets where each ramp mouth meets street level
	Build.box(structures(), Vector3(17.0, 3.0, 6.0), Vector3(23.5, -1.6, -18.0), fill)
	Build.box(structures(), Vector3(17.0, 3.0, 6.0), Vector3(-23.5, -1.6, -18.0), fill)
	Build.box(structures(), Vector3(17.0, 3.0, 3.0), Vector3(23.5, -1.6, -105.5), fill)
	Build.box(structures(), Vector3(17.0, 3.0, 3.0), Vector3(-23.5, -1.6, -105.5), fill)


func _ramp(centre: Vector3, width: float, run: float, drop: float) -> void:
	# Both ramps span the same two levels -- street (y=0) down to the cut floor
	# (y=SUNK_Y) -- so the centre height follows the drop's *magnitude*.  The
	# sign only chooses which end is high.  Computing it from the signed value
	# left the north ramp centred 2.6 m too high: a floating slab that bridged
	# nothing and left the plaza face an unclimbable wall.
	var pitch := atan2(drop, run)
	var len := sqrt(run * run + drop * drop)
	Build.box(structures(), Vector3(width, 0.7, len),
			centre + Vector3(0, -absf(drop) * 0.5 - 0.18, 0), MatLib.asphalt(),
			Vector3(rad_to_deg(pitch), 0, 0))


# ------------------------------------------------------------------- suburb

func _suburb() -> void:
	var mb := MeshBuilder.new()
	var r := RandomNumberGenerator.new()
	r.seed = 8811
	var z := 122.0
	var i := 0
	while z > 44.0:
		for side in [-1.0, 1.0]:
			var s := float(side)
			var d := r.randf_range(7.5, 11.5)
			var x: float = s * (WALK_EDGE + 5.4 + d * 0.5)
			var yaw := 90.0 if s < 0.0 else -90.0
			var gutted := r.randf() < 0.30
			Kit.house(mb, Vector3(x, 0.24, z), yaw, 500 + i * 13 + int(s), {
				"storeys": 2 if r.randf() < 0.7 else 1,
				"yard": r.randf_range(5.0, 9.0),
				"roof_height": 0.4 if gutted else 1.0,
				"wall": Kit.m("concrete_dark" if gutted else "plaster",
						Color(0.20, 0.19, 0.18) if gutted
						else Kit._pick(r, [Color("d6cbb8"), Color("b6c4c6"),
								Color("c8b6a0"), Color("a7b0b4"), Color("c2c8bd")])),
			})
			var front := WALK_EDGE + 0.4
			mb.box_at(Vector3(s * (front + 2.6), 0.02, z + r.randf_range(-1, 1)),
					Vector3(5.2, 0.3, 3.0), Kit.m("gravel"))
			# dead cars in the drives, half of them burnt out
			if r.randf() < 0.55:
				Kit.car(mb, Vector3(s * (front + 3.4), 0.24, z + r.randf_range(-2.5, 2.5)),
						90.0 if s < 0.0 else -90.0, i % 6, 900 + i, r.randf() < 0.7)
			if r.randf() < 0.6:
				Kit.fence(mb, Vector3(s * front, 0.24, z), 90.0, 8.0, 1.1)
			# fewer trees than there were: the yards are mostly gone
			if r.randf() < 0.28:
				Kit.tree(mb, Vector3(s * (front + r.randf_range(1.5, 4.0)), 0.24,
						z + r.randf_range(-3, 3)), 700 + i, r.randf_range(0.7, 1.1))
			if r.randf() < 0.5:
				Kit.rubble(mb, Vector3(s * (front + r.randf_range(1.0, 4.0)), 0.24,
						z + r.randf_range(-3, 3)), Vector3(4, 0.5, 4), 22,
						1500 + i * 7 + int(s), 1.1)
			if gutted:
				# a burnt shell: the roof is gone and the walls are down to two
				Kit.debris_pile(mb, Vector3(x, 0.24, z + r.randf_range(-6, 6)),
						r.randf_range(3.0, 5.5), 1700 + i)
			z -= r.randf_range(11.0, 13.5)
		i += 1
	_commit(mb, "Suburb")

	# the house that is still burning, off the first corner: the opening shot's
	# warm anchor and the reason the sky has smoke in it
	_tower_fire(Vector3(-31.0, 5.6, 66.0), 26, 7.5)


# ------------------------------------------------------------------- avenue

func _avenue() -> void:
	var mb := MeshBuilder.new()
	var r := RandomNumberGenerator.new()
	r.seed = 4477
	var styles := ["plaster", "brick", "tower", "office", "brick", "plaster", "tower"]
	for side in [-1.0, 1.0]:
		var s := float(side)
		var z := 40.0
		var i := 0
		while z > SUNK_FROM + 4.0:
			var w := r.randf_range(9.0, 16.0)
			var d := r.randf_range(11.0, 17.0)
			var h := r.randf_range(13.0, 30.0)
			if i % 5 == 3:
				h = r.randf_range(28.0, 42.0)
			var yaw := 90.0 if s < 0.0 else -90.0
			var x: float = s * (WALK_EDGE + d * 0.5)
			var style_name: String = styles[i % styles.size()]
			Kit.building(mb, Vector3(x, 0.24, z - w * 0.5), yaw, {
				"size": Vector3(w, h, d),
				"style": style_name,
				"seed": 1000 + i * 17 + (0 if s < 0.0 else 7),
				"ruin": 0.42,
				"lit": 0.20,
				"detail": 2,
			})
			var front: float = s * WALK_EDGE
			var heading := Vector3(s, 0, 0)
			if r.randf() < 0.55:
				var aw := r.randf_range(0.4, 0.62) * w
				Kit.awning(mb, Basis.from_euler(Vector3(0, deg_to_rad(yaw), 0)),
						Vector3(front, 3.5, z - w * 0.5 + r.randf_range(-1.5, 1.5)),
						heading, aw, r.randf_range(1.8, 2.8),
						Kit._pick(r, [Color("7a3a2e"), Color("3f5a52"), Color("6a5a34")]))
			if r.randf() < 0.4:
				Kit.scaffold(mb, Basis.from_euler(Vector3(0, deg_to_rad(yaw), 0)),
						Vector3(front, 0.24, z - w * 0.5), heading, w * 0.7,
						r.randf_range(6.0, 11.0), 3)
			if r.randf() < 0.45:
				Kit.fire_escape(mb, Basis.from_euler(Vector3(0, deg_to_rad(yaw), 0)),
						Vector3(front + s * 0.1, 0, z - w * 0.5 + r.randf_range(-2, 2)),
						heading, r.randf_range(10.0, 20.0), 3, 3.4,
						r.randf_range(2.2, 3.4))
			if i % 3 == 1:
				Kit.wires(mb, Vector3(-WALK_EDGE + 0.4, 9.0 + r.randf_range(0, 3), z - w * 0.5),
						Vector3(WALK_EDGE - 0.4, 9.0 + r.randf_range(0, 3), z - w * 0.5),
						r.randf_range(0.5, 1.4))
			if i % 4 == 0:
				Kit.laundry(mb, Vector3(-WALK_EDGE + 1.2, 5.4, z - w * 0.5),
						Vector3(-WALK_EDGE + 6.0, 5.0, z - w * 0.5), 300 + i)
			z -= w + r.randf_range(0.2, 1.6)
			i += 1

	# street furniture, and the checkpoint that stops you at the far end
	var z2 := 92.0
	while z2 > SUNK_FROM + 5.0:
		for side in [-1.0, 1.0]:
			var s := float(side)
			var x: float = s * (ROAD_HALF + 2.4)
			var hpos := Kit.streetlamp(mb, Vector3(x, 0.24, z2), 0.0, -s, true)
			var lamp := Build.omni(props(), hpos, Color("ffab5c"), 4.2, 17.0, false, 1.0)
			if int(z2) % 3 == 0:
				var tw: Tween = lamp.create_tween().set_loops()
				tw.tween_property(lamp, "light_energy", 3.0, 0.08)
				tw.tween_property(lamp, "light_energy", 7.6, 0.35)
		if int(z2) % 24 == 0:
			Kit.traffic_light(mb, Vector3(ROAD_HALF + 2.0, 0.24, z2 - 8.0), 0.0)
		z2 -= 12.0
	var bx := -WALK_EDGE + 1.0
	while bx < WALK_EDGE - 1.0:
		Kit.bollard(mb, Vector3(bx, 0.24, -18.0))
		bx += 2.6
	_commit(mb, "Avenue")

	# hung banners on the avenue walls, and the gate itself
	_hang_banner(Vector3(-WALK_EDGE + 0.35, 0.24, 26.0), -90.0)
	_hang_banner(Vector3(WALK_EDGE - 0.35, 0.24, 4.0), 90.0)
	_hang_banner(Vector3(-WALK_EDGE + 0.35, 0.24, -14.0), -90.0)
	# the gate is authored facing -Z, and the player arrives from +Z, so it
	# takes a 180 for its markings to face up the avenue
	_gate(Vector3(0, 0.24, GATE_Z), 180.0, "B")


# -------------------------------------------------------------- expressway

## The cut, drained: everything that was in it when the city stopped, still
## there, rusted where it stood.
func _expressway() -> void:
	var mb := MeshBuilder.new()
	var r := RandomNumberGenerator.new()
	r.seed = 3131
	var c := (SUNK_FROM + SUNK_TO) * 0.5
	for i in 11:
		var p := Vector3(r.randf_range(-17, 17), SUNK_Y + 0.2, c + r.randf_range(-34, 34))
		Kit.car(mb, p, r.randf_range(-40, 40), i % 6, 1200 + i, true)
		mb.box_at(p + Vector3(0, 0.35, 0), Vector3(2.2, 0.12, 4.8),
				MatLib.asphalt_wet(), Vector3(0, r.randf_range(0, 90), 0))
	Kit.bus(mb, Vector3(7.0, SUNK_Y + 0.35, c - 6.0), 24.0, Color("3a4a52"))
	Kit.bus(mb, Vector3(-8.0, SUNK_Y + 0.3, c + 26.0), -152.0, Color("4a4038"))

	# retaining walls, ladders and the flood marks of a cut that used to drain
	for side in [-1.0, 1.0]:
		var s := float(side)
		mb.box_at(Vector3(s * 31.0, SUNK_Y + 2.2, c), Vector3(1.4, 4.4, 82.0),
				Kit.m("concrete_dark"))
		for k in 3:
			var pz := c + r.randf_range(-30, 30)
			for i in 5:
				mb.box_at(Vector3(s * 30.2, SUNK_Y + 0.8 + float(i) * 0.4, pz),
						Vector3(0.5, 0.06, 0.5), Kit.m("steel_rust"))

	# a collapsed overhead gantry across the cut, and wreckage under it
	var gy := SUNK_Y + 6.4
	mb.box_at(Vector3(-9.0, gy, c + 4.0), Vector3(26.0, 0.5, 0.5), Kit.m("steel_rust"),
			Vector3(0, 0, -9.0))
	mb.box_at(Vector3(12.0, gy - 2.4, c + 4.0), Vector3(0.5, 5.0, 0.5), Kit.m("steel_rust"),
			Vector3(0, 0, 6.0))
	for i in 4:
		Build.billboard(props(), Vector2(4.6, 1.6),
				Vector3(-11.0 + float(i) * 7.6, gy + 0.3, c + 4.0),
				Kit._pick(r, [Color("5a4a34"), Color("3a4a44"), Color("6a5a3a")]))

	Kit.rubble(mb, Vector3(0, SUNK_Y + 0.4, c + 6.0), Vector3(20, 0.6, 22), 90, 4242, 1.3)
	Kit.rubble(mb, Vector3(0, SUNK_Y + 0.3, c - 22.0), Vector3(18, 0.5, 18), 70, 4343, 1.2)
	Kit.debris_pile(mb, Vector3(-16.0, SUNK_Y, c - 4.0), 5.0, 55)
	for i in 34:
		var p := Vector3(r.randf_range(-24, 24), SUNK_Y + 0.02, c + r.randf_range(-38, 38))
		mb.box_at(p, Vector3(r.randf_range(0.4, 1.2), 0.12, r.randf_range(0.4, 1.2)),
				Kit.m("wood", Color("40342a"), 0.8),
				Vector3(0, r.randf_range(0, 360), 0))
	# a couple of cars pushed against the far wall and set alight
	Kit.car(mb, Vector3(-24.0, SUNK_Y + 0.85, c - 30.0), 96.0, 3, 1350, true)
	Kit.car(mb, Vector3(25.0, SUNK_Y + 0.9, c + 18.0), -84.0, 5, 1351, true)
	_commit(mb, "Expressway")


# -------------------------------------------------------------------- plaza

func _plaza() -> void:
	var mb := MeshBuilder.new()
	var r := RandomNumberGenerator.new()
	r.seed = 6060

	# --- the monument, and the balloon over it -----------------------------
	# The GLB is authored standing on y = 0 facing -Z, and the player arrives
	# from +Z, so the piece takes a 180 to show its banner down the approach.
	_arm_monument()
	_monument = _monument_node
	# The balloon floats 46 m short of the monument, on the approach, where the
	# whole plaza sees it; its two portraits face along the avenue either way.
	# Only the mooring rig is solid: the envelope hangs at 52 m and its tethers
	# are 3 cm cables, so colliding them is thousands of triangles of nothing a
	# player can ever touch.
	_balloon = EnvKit.place(structures(), "balloon",
			Vector3(0, 0, MONUMENT_Z + 46.0), 0.0, {"below": 4.0})
	if _balloon != null:
		_balloon.name = "Balloon"

	# plaza floor detail: paving joints and the steps the balloon hangs over
	for i in 18:
		mb.box_at(Vector3(-44.0 + float(i) * 5.2, 0.03, MONUMENT_Z),
				Vector3(0.14, 0.03, 96.0), Kit.m("concrete"))
	for k in 4:
		mb.box_at(Vector3(0, 0.16 + float(k) * 0.03, MONUMENT_Z - 24.0 - float(k) * 3.0),
				Vector3(30.0 - float(k) * 6.0, 0.24, 3.0), Kit.m("concrete_dark"))

	# --- the camp: the occupation lives in the square it took -------------
	for i in 9:
		var a := r.randf_range(0.0, TAU)
		var rad := r.randf_range(24.0, 44.0)
		var p := Vector3(cos(a) * rad, 0.0, MONUMENT_Z + sin(a) * rad * 0.7)
		Kit.tent(mb, p, rad_to_deg(a), 2200 + i,
				Kit._pick(r, [Color("556040"), Color("6a5a3a"), Color("4a4a52")]))
	for i in 5:
		var a := r.randf_range(0.0, TAU)
		var p := Vector3(cos(a) * 34.0, 0.0, MONUMENT_Z + sin(a) * 26.0)
		Kit.sandbag_wall(mb, p, p + Vector3(r.randf_range(-6, 6), 0, r.randf_range(-6, 6)),
				r.randf_range(0.8, 1.4), 2400 + i)
	Kit.barrier(mb, Vector3(-9.0, 0, MONUMENT_Z + 30.0), 8.0)
	Kit.barrier(mb, Vector3(9.0, 0, MONUMENT_Z + 30.0), -8.0)
	Kit.flagpole(mb, Vector3(-15.0, 0, MONUMENT_Z + 26.0), 0.0, 8.0, Color("a8322a"))
	Kit.flagpole(mb, Vector3(16.0, 0, MONUMENT_Z + 24.0), 0.0, 7.0, Color("a8322a"))
	for i in 14:
		var p := Vector3(r.randf_range(-42, 42), 0.0, MONUMENT_Z + r.randf_range(-40, 40))
		if r.randf() < 0.4:
			Kit.crate(mb, p, Vector3(r.randf_range(0.8, 1.3), 0.9, r.randf_range(0.8, 1.3)),
					r.randf_range(0, 360), r.randf() < 0.5)
		elif r.randf() < 0.6:
			Kit.barrel(mb, p, 0.0, Kit._pick(r, [Color("44523a"), Color("5a3a2a"),
					Color("3a4a5a")]))
		else:
			Kit.dumpster(mb, p, r.randf_range(0, 360))
	# a cordon of vehicles and concrete around the monument's own fence ring
	for i in 8:
		var a := TAU * float(i) / 8.0 + 0.3
		var rad := r.randf_range(19.0, 23.0)
		Kit.car(mb, Vector3(cos(a) * rad, 0.0, MONUMENT_Z + sin(a) * rad),
				rad_to_deg(a) + 90.0, i % 6, 2600 + i, true)
	Kit.rubble(mb, Vector3(-34.0, 0.0, MONUMENT_Z + 34.0), Vector3(12, 0.8, 12), 60, 777, 1.4)
	Kit.rubble(mb, Vector3(34.0, 0.0, MONUMENT_Z - 26.0), Vector3(12, 0.8, 12), 60, 778, 1.4)

	# --- the ring of ruins that encloses the plaza -------------------------
	# with a gap where the avenue arrives, so the approach is open and the
	# monument is framed on entry
	var styles := ["tower", "office", "plaster", "brick"]
	for i in 18:
		var a := TAU * float(i) / 18.0
		if absf(angle_difference(a, PI * 0.5)) < deg_to_rad(36.0):
			continue
		var rad := r.randf_range(48.0, 64.0)
		var p := Vector3(cos(a) * rad, 0.0, MONUMENT_Z + sin(a) * rad)
		var w := r.randf_range(10.0, 18.0)
		var d := r.randf_range(10.0, 18.0)
		Kit.building(mb, p, rad_to_deg(atan2(-cos(a), -sin(a))), {
			"size": Vector3(w, r.randf_range(18.0, 46.0), d),
			"style": styles[i % styles.size()],
			"seed": 3000 + i * 23,
			"ruin": 0.55,
			"lit": 0.14,
			"detail": 1,
			"shop": false,
		})
	_commit(mb, "Plaza")

	# --- the tower that is on fire, just past the ring ---------------------
	# the video's own opening image: a tall building burning against a pale sky,
	# placed off the approach axis so it frames the square without hiding it
	var fire_mb := MeshBuilder.new()
	Kit.building(fire_mb, Vector3(56.0, 0.0, MONUMENT_Z + 62.0), -32.0, {
		"size": Vector3(24.0, 64.0, 22.0),
		"style": "tower",
		"seed": 8801,
		"ruin": 0.85,
		"lit": 0.0,
		"detail": 1,
		"shop": false,
	})
	_commit(fire_mb, "BurntTower")
	_tower_fire(Vector3(52.0, 40.0, MONUMENT_Z + 58.0), 54, 14.0)
	_tower_fire(Vector3(59.0, 26.0, MONUMENT_Z + 66.0), 30, 9.0)

	# --- signage and the gate into the square -----------------------------
	_gate(Vector3(0, 0.0, PLAZA_GATE_Z), 180.0, "P")
	EnvKit.place(structures(), "billboard", Vector3(-30.0, 0.0, MONUMENT_Z + 44.0),
			168.0)
	EnvKit.place(structures(), "billboard", Vector3(32.0, 0.0, MONUMENT_Z + 18.0),
			-196.0)


## A checkpoint gate, aimed so its markings face the direction you arrive from.
func _gate(pos: Vector3, yaw: float, tag: String) -> void:
	var g := EnvKit.place(structures(), "checkpoint", pos, yaw,
			{"name": "Checkpoint" + tag})
	if g == null:
		return
	_gates.append(g)


## A hung facade banner, mounted on the wall at `pos` and facing `yaw`.
func _hang_banner(pos: Vector3, yaw: float) -> void:
	# The piece is authored facing -Z with its bar 9.5 m up, so its own origin
	# is the mount point and the wall does the rest.
	EnvKit.place(structures(), "banner", pos, yaw, {"collide": false})


## Fire and smoke on a structure, for the burning skyline.
func _tower_fire(pos: Vector3, glow: int, plume: float) -> void:
	var holder := Node3D.new()
	holder.position = pos
	_props.add_child(holder)
	Build.omni(holder, Vector3.ZERO, Color("ff8a34"), 12.0 * plume * 0.14, 60.0, false, 3.0)
	FX.fire_glow(holder, glow)
	FX.smoke_plume(holder, int(plume * 3.0), plume, Color(0.10, 0.095, 0.095, 0.55))


func _skyline() -> void:
	var mb := MeshBuilder.new()
	var r := RandomNumberGenerator.new()
	r.seed = 9090
	for i in 54:
		var a := r.randf_range(0.0, TAU)
		var rad := r.randf_range(120.0, 260.0)
		var p := Vector3(cos(a) * rad, 0.0, MONUMENT_Z + 40.0 + sin(a) * rad)
		var w := r.randf_range(14.0, 30.0)
		var h := r.randf_range(26.0, 90.0)
		Kit.building(mb, p, r.randf_range(0, 360), {
			"size": Vector3(w, h, r.randf_range(14.0, 30.0)),
			"style": "office" if i % 3 else "tower",
			"seed": 5000 + i * 11,
			"ruin": 0.7,
			"lit": 0.10,
			"detail": 0 if i % 2 else 1,
			"collide": false,
			"shop": false,
		})
	_commit(mb, "Skyline", false)


# ------------------------------------------------------------------ lighting

func _weather_and_lights() -> void:
	# no rain and no water: this district burns instead of flooding, so the
	# weather is haze and fallout rather than precipitation
	embers(120, Vector3(48, 10, 100))
	Build.sun(self, Vector3(-34, 150, 12), Color("f2d9b4"), 1.28, 2.6)
	FX.dust(self, 190, Vector3(34, 11, 96), 0.06, Color(0.80, 0.79, 0.76, 0.20))

	# fires: one per beat, so the eye always has a warm anchor
	fire_barrel(Vector3(-9.5, 0.24, 30.0))
	fire_barrel(Vector3(11.0, 0.24, -6.0))
	fire_barrel(Vector3(-13.0, SUNK_Y + 0.4, -66.0), 1.1)
	fire_barrel(Vector3(14.0, 0.0, MONUMENT_Z + 30.0), 1.2)
	fire_barrel(Vector3(-16.0, 0.0, MONUMENT_Z + 16.0), 1.0)
	fire_barrel(Vector3(22.0, 0.0, -118.0), 1.3)

	# the monument's own floodlights, aimed up the faces of it
	if _monument != null:
		var h := EnvKit.height("monument")
		for i in 6:
			var a := TAU * float(i) / 6.0
			var off := Vector3(cos(a) * 9.0, 0.6, sin(a) * 8.0)
			var sp := Build.spot(_monument, off, Vector3(-64, rad_to_deg(a) + 180, 0),
					Color("ffd9a8"), 30.0, 120.0, 36.0, true, 5.0)
			_monument_lights.append(sp)
		var core := Build.omni(_monument, Vector3(0, 2.4, 6.0), Color("ffd9a8"), 18.0,
				60.0, true, 4.5)
		_monument_lights.append(core)
		# a nav light on the balloon, so the thing overhead reads at night too
		# (the envelope's centre is 52 m up, where gen_env places it)
		if _balloon != null:
			Build.omni(_balloon, Vector3(0, 52.0, 0), Color("ff6a6a"), 6.0,
					90.0, false, 2.0)


# ------------------------------------------------------------------- enemies

func _enemies() -> void:
	_squad.append(spawn_enemy(Vector3(-6.0, 0.3, 40.0), "trooper",
			line_patrol(Vector3(-6.0, 0.3, 40.0), Vector3(6.0, 0.3, 26.0), 2)))
	_squad.append(spawn_enemy(Vector3(9.0, 0.3, 8.0), "trooper",
			line_patrol(Vector3(9.0, 0.3, 8.0), Vector3(-8.0, 0.3, -6.0), 3)))
	# the checkpoint crew
	_squad.append(spawn_enemy(Vector3(-7.0, 0.3, GATE_Z - 3.0), "trooper",
			line_patrol(Vector3(-7.0, 0.3, GATE_Z - 3.0), Vector3(7.0, 0.3, GATE_Z - 3.0), 3)))
	_squad.append(spawn_enemy(Vector3(-10.0, SUNK_Y + 0.3, -44.0), "trooper",
			line_patrol(Vector3(-10.0, SUNK_Y + 0.3, -44.0), Vector3(9.0, SUNK_Y + 0.3, -70.0), 3)))
	_squad.append(spawn_enemy(Vector3(11.0, SUNK_Y + 0.3, -78.0), "trooper",
			ring_patrol(Vector3(0.0, SUNK_Y + 0.3, -70.0), 9.0, 3, 0.6)))
	# the plaza gate and the monument itself
	_squad.append(spawn_enemy(Vector3(-4.0, 0.3, PLAZA_GATE_Z - 5.0), "heavy",
			line_patrol(Vector3(-8.0, 0.3, PLAZA_GATE_Z - 5.0),
					Vector3(8.0, 0.3, PLAZA_GATE_Z - 5.0), 2)))
	_squad.append(spawn_enemy(Vector3(-14.0, 0.3, MONUMENT_Z + 30.0), "trooper",
			line_patrol(Vector3(-14.0, 0.3, MONUMENT_Z + 30.0),
					Vector3(14.0, 0.3, MONUMENT_Z + 30.0), 3), true))
	_squad.append(spawn_enemy(Vector3(0.0, 0.3, MONUMENT_Z + 14.0), "guard",
			ring_patrol(Vector3(0.0, 0.3, MONUMENT_Z), 15.0, 3, 0.4), true))
	for e in _squad:
		e.died.connect(_on_enemy_died)

	add_pickup(Vector3(4.0, 0.3, 52.0), "ammo", 90)
	add_pickup(Vector3(-5.0, 0.3, -12.0), "health", 45)
	add_pickup(Vector3(0.0, 0.3, 84.0), "ammo", 90)
	add_locker(Vector3(-17.4, 0.24, 60.0), 90.0)
	add_locker(Vector3(17.4, 0.24, 5.0), -90.0)


func _on_enemy_died(_e: Node) -> void:
	if enemies_alive() > 0:
		return
	complete("clear")
	objective("monument", "Destroy the monument")
	notify("The expressway is quiet. Move up.")
	for l in _monument_lights:
		if is_instance_valid(l):
			var light := l as Light3D
			var tw: Tween = light.create_tween()
			tw.tween_property(light, "light_energy", light.light_energy * 1.9, 3.0)


# ------------------------------------------------------------------ triggers

func _triggers() -> void:
	var gate := TriggerZone.make(self, Vector3(0, 1.2, GATE_Z - 9.0),
			Vector3(34, 5, 3), "gate")
	gate.entered.connect(func(_p):
		complete("advance")
		objective("clear", "Clear the expressway")
		if game != null:
			game.call("notify", "They are watching this road. Keep low.")
		AudioDirector.play("whoosh", -10.0, 0.8, 0.05))

	var plaza := TriggerZone.make(self, Vector3(0, 1.2, PLAZA_GATE_Z - 12.0),
			Vector3(56, 5, 3), "plaza")
	plaza.entered.connect(func(_p):
		if enemies_alive() > 0:
			GameManager.toast_message("HOSTILES IN THE PLAZA")
			return
		objective("monument", "Shoot the monument. Bring it down.")
		notify("Give them back their silence. Shoot it.")
		AudioDirector.play("checkpoint", -6.0))


## The finale.  A thick hitbox wrapped around the monument soaks bullets;
## enough fire brings the whole piece down and ends the run.
func _arm_monument() -> void:
	# Sized to the authored GLB (26 m square, 17 m tall) plus a hand's width so
	# hitscan meets the box before the static collision underneath it.
	_monument_body = place_monument(Vector3(0, 0, MONUMENT_Z), 180.0, 1.0,
			MONUMENT_HEALTH, Vector3(26.6, 17.0, 26.6))
	monument_on_down(_monument_body, _on_monument_down)


func _on_monument_down() -> void:
	complete("monument")
	_explode_monument()
	_finish_run()


## The monument's last seconds: fireball, shockwave, collapse and the run.
func _explode_monument() -> void:
	# The shared blast handles flash, fireball, shockwave and rubble.
	_monument_blast()


func _shake(amount: float) -> void:
	if game != null and game.player != null:
		game.player.cam_rig.add_trauma(amount)


## The chapter ends here: the monument is down, the square is taken.  The
## campaign moves on to Chapter II.
func _finish_run() -> void:
	await get_tree().create_timer(2.6).timeout
	finish()


## Opening camera path.  Each shot is a camera position and a point to aim at,
## both in the real level, so the drift can never disagree with the geometry.
## `text` and `title` fire when the shot is reached.
func intro_shots() -> Array:
	return [
		{
			"pos": Vector3(30.0, 26.0, 104.0),
			"look": Vector3(0.0, 10.0, 4.0),
			"text": "Smoke on the skyline, all the way down to the square.",
		},
		{
			"pos": Vector3(-3.0, SUNK_Y + 1.1, SUNK_FROM - 8.0),
			"look": Vector3(4.0, SUNK_Y + 2.0, -88.0),
			"text": "Nothing has moved on the expressway since the day it was taken.",
		},
		{
			"pos": Vector3(0.0, 2.2, MONUMENT_Z + 86.0),
			"look": Vector3(0.0, 34.0, MONUMENT_Z + 46.0),
			"title": "CENTURY OF HUMILIATION",
		},
		{
			"pos": Vector3(-12.0, 1.4, MONUMENT_Z + 30.0),
			"look": Vector3(0.0, 9.0, MONUMENT_Z),
			"text": "Their banner over our stone.",
		},
		{
			"pos": Vector3(12.0, 14.0, 44.0),
			"look": Vector3(0.0, 2.0, 96.0),
		},
	]


## Camera vantages for automated look review (`--capture`).
func review_vantages() -> Array:
	return [
		{"name": "approach", "pos": Vector3(0, 0.6, 88.0), "yaw": 0.0, "pitch": -0.05},
		{"name": "suburb", "pos": Vector3(0, 0.6, 62.0), "yaw": 1.35, "pitch": 0.02},
		{"name": "banner", "pos": Vector3(6.0, 0.6, 30.0), "yaw": -1.25, "pitch": 0.34},
		{"name": "gate", "pos": Vector3(0, 0.9, 34.0), "yaw": 0.0, "pitch": 0.04},
		{"name": "avenue", "pos": Vector3(-3.0, 0.6, 2.0), "yaw": 0.0, "pitch": 0.02},
		{"name": "cut", "pos": Vector3(0, SUNK_Y + 1.0, -30.0), "yaw": 0.0, "pitch": -0.02},
		{"name": "wrecks", "pos": Vector3(-6.0, SUNK_Y + 1.4, -40.0), "yaw": 0.45, "pitch": -0.10},
		{"name": "gate2", "pos": Vector3(0, 0.9, -96.0), "yaw": 0.0, "pitch": 0.03},
		{"name": "balloon", "pos": Vector3(0, 0.6, MONUMENT_Z + 78.0), "yaw": 0.0, "pitch": 0.62},
		{"name": "plaza", "pos": Vector3(0, 0.6, MONUMENT_Z + 54.0), "yaw": 0.0, "pitch": 0.06},
		{"name": "camp", "pos": Vector3(-20.0, 0.6, MONUMENT_Z + 30.0), "yaw": 0.6, "pitch": 0.0},
		{"name": "monument", "pos": Vector3(0, 0.6, MONUMENT_Z + 34.0), "yaw": 0.0, "pitch": 0.26},
		{"name": "tower", "pos": Vector3(20.0, 1.2, MONUMENT_Z + 54.0), "yaw": -0.62, "pitch": 0.34},
	]


func surface_at(_pos: Vector3) -> String:
	# the district is dry: no water anywhere in it any more
	return "concrete"
