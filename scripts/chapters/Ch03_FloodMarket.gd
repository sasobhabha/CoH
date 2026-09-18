extends Chapter
## CHAPTER III -- THE FLOOD MARKET
##
## The escalation.  A quayside square of stalls, container stacks and a gantry
## crane, fought in two waves: first a picket, then a counter-attack from the
## far side of the water.
##
## Everything is built from the kit and committed as a few merged meshes, so
## the density costs draw calls only once.

const SQUARE := 108.0
const DECK_Y := 0.0
const WATER_Y := 0.11
const BED_Y := -2.5               # canal bed: 2.6 m of water over it
const CANAL_X := -40.0
const CANAL_HALF := 9.0           # the cut is 18 m bank to bank
const SLIP_Z := 24.0              # where the drowned slipway crosses in

var _wave := 0
var _wave_one: Array = []
var _wave_two: Array = []
var _garrison: Array = []
var _crane: Node3D
var _hook: Node3D
var _t := 0.0


func describe() -> void:
	_spawn = Vector3(0, 0.3, 46)
	_spawn_yaw = 0.0
	AudioDirector.music("mus_explore", 3.0, -12.0)
	AudioDirector.set_ambience(["amb_rain", "amb_water", "amb_city"], 3.0)
	GameManager.set_objectives([
		{"id": "break", "text": "Break the blockade"},
		{"id": "hold", "text": "Hold the market"},
		{"id": "monument", "text": "Shoot the monument"},
	])


func build() -> void:
	_ground()
	_quays()
	_buildings()
	_container_yard()
	_market()
	_crane_rig()
	_dressing()
	_atmosphere()
	_wave = 1
	_spawn_wave_one()
	_monument_garrison(true)
	set_process(true)


func _commit(mb: MeshBuilder, name: String, collide := true) -> void:
	if not mb.is_empty():
		mb.commit(structures(), name, collide)


# ------------------------------------------------------------------- ground

func _ground() -> void:
	# The square itself, and the canal cutting down its western side.  The cut
	# is real now: the deck is poured as two fills with the water between
	# them, a bed 2.6 m down, and a drowned slipway to walk in and out on.
	var mb := MeshBuilder.new()
	var deck := MatLib.ground_plane("concrete_floor", 0.30)
	# east fill: everything right of the cut (cut east face at CANAL_X + CANAL_HALF)
	var east_w := SQUARE * 0.5 - (CANAL_X + CANAL_HALF)
	var east_x := (CANAL_X + CANAL_HALF + SQUARE * 0.5) * 0.5
	mb.slab(Vector3(east_x, -0.6, 0), east_w, SQUARE, 1.2, deck, 0.0, 3.0)
	# west fill: the strip between the cut and the district's west edge
	var west_w := CANAL_X - CANAL_HALF + SQUARE * 0.5
	var west_x := (CANAL_X - CANAL_HALF - SQUARE * 0.5) * 0.5
	mb.slab(Vector3(west_x, -0.6, 0), west_w, SQUARE, 1.2, deck, 0.0, 3.0)
	# the drowned bed, and the canal bed is a walkable/swimmable floor
	mb.slab(Vector3(CANAL_X, BED_Y - 0.6, 0), CANAL_HALF * 2.0 + 2.4, SQUARE + 2.4, 1.2,
			MatLib.ground_plane("asphalt", 0.12), 0.0, 2.0)
	# colliders: slab() only bakes the visible mesh -- without these the whole
	# square is a hole and every spawn drops out of the world until the
	# out-of-bounds net bounces it back into the same fall.
	mb.collide_at(Vector3(east_x, -0.6, 0), Vector3(east_w, 1.2, SQUARE))
	mb.collide_at(Vector3(west_x, -0.6, 0), Vector3(west_w, 1.2, SQUARE))
	mb.collide_at(Vector3(CANAL_X, BED_Y - 0.6, 0),
			Vector3(CANAL_HALF * 2.0 + 2.4, 1.2, SQUARE + 2.4))
	# close the cut under both quay aprons so the water has ends: they span
	# from the bed up past the waterline, and are collide-only (no mesh), so
	# they hide behind the map-edge blockers
	mb.collide_at(Vector3(CANAL_X, BED_Y + 1.8, -SQUARE * 0.5 - 1.2),
			Vector3(CANAL_HALF * 2.0 + 2.4, 3.6, 2.4))
	mb.collide_at(Vector3(CANAL_X, BED_Y + 1.8, SQUARE * 0.5 + 1.2),
			Vector3(CANAL_HALF * 2.0 + 2.4, 3.6, 2.4))

	# the slipway: one ramp from the east deck down into the water, flush at
	# both ends.  It descends westward (−X), so the long axis is X and the tilt
	# is about Z; the top lip sits a hair proud of the deck (0.02) so the
	# coplanar seam does not z-fight, and the foot buries itself in the bed.
	var run := 15.0
	var top_hi := 0.02
	var pitch := atan2(top_hi - BED_Y, run)
	var ramp_len := sqrt(run * run + (top_hi - BED_Y) * (top_hi - BED_Y))
	var ramp_basis := Basis.from_euler(Vector3(0, 0, pitch))
	var ramp_pos := Vector3(CANAL_X + CANAL_HALF - run * 0.5,
			(top_hi + BED_Y) * 0.5 - 0.3, SLIP_Z)
	mb.box_basis(ramp_basis, ramp_pos,
			Vector3(ramp_len, 0.6, 6.0), MatLib.ground_plane("concrete_floor", 0.22))
	mb.collide(Transform3D(ramp_basis, ramp_pos), Vector3(ramp_len, 0.6, 6.0))
	_commit(mb, "Deck", true)

	# map edges: the quay is the end of the district, not the edge of the mesh
	Build.blocker(structures(), Vector3(2.0, 16.0, SQUARE + 6.0),
			Vector3(SQUARE * 0.5 + 1.0, 7.0, 0))
	Build.blocker(structures(), Vector3(2.0, 16.0, SQUARE + 6.0),
			Vector3(-SQUARE * 0.5 - 1.0, 7.0, 0))
	Build.blocker(structures(), Vector3(SQUARE + 6.0, 16.0, 2.0),
			Vector3(0, 7.0, SQUARE * 0.5 + 1.0))
	Build.blocker(structures(), Vector3(SQUARE + 6.0, 16.0, 2.0),
			Vector3(0, 7.0, -SQUARE * 0.5 - 1.0))

	water_surface(Vector2(SQUARE, SQUARE), WATER_Y, 30.0)
	# the big flood plate stops at z = -24; without this second plate the
	# northern stretch of the cut renders as a dry trench
	water_plate(Vector2(CANAL_HALF * 2.0 + 2.4, 31.0), WATER_Y, -39.5, 26.0, CANAL_X)

	# Puddles and the flood line: every surface in this square is soaked.
	var wet := MeshBuilder.new()
	for i in 34:
		var px := sin(float(i) * 2.3) * 42.0
		var pz := cos(float(i) * 1.7) * 44.0
		wet.slab(Vector3(px, 0.02, pz), 4.0 + fmod(float(i) * 1.7, 5.0), 3.0 + fmod(float(i), 4.0),
				0.03, MatLib.asphalt_wet(), float(i) * 21.0, 6.0)
	_commit(wet, "Puddles", false)

	_jetties()


func _jetties() -> void:
	var mb := MeshBuilder.new()
	var deck := MatLib.wood_dark()
	var post := MatLib.wood()
	for i in 4:
		var z := -30.0 + float(i) * 22.0
		# flush against the east bank so the pier is walk-on, and standing over
		# the water with its pilings keyed into the bed
		var x := CANAL_X + CANAL_HALF - 3.5
		mb.slab(Vector3(x, 0.55, z), 7.0, 2.6, 0.22, deck, 0.0, 2.0)
		for dx in [-3.2, 0.0, 3.2]:
			for dz in [-1.1, 1.1]:
				mb.cylinder_at(Vector3(x + dx, -0.9, z + dz), 0.16, 3.4, post, 8)
				mb.collide_at(Vector3(x + dx, -0.9, z + dz), Vector3(0.36, 3.4, 0.36))
		mb.collide_at(Vector3(x, 0.55, z), Vector3(7.0, 0.3, 2.6))
		# rope rails
		for dz in [-1.25, 1.25]:
			mb.pipe(Vector3(x - 3.2, 1.0, z + dz), Vector3(x + 3.2, 1.0, z + dz), 0.035,
					MatLib.rubber(), 6)
			for k in 3:
				mb.pipe(Vector3(x - 3.2 + float(k) * 3.2, 0.55, z + dz),
						Vector3(x - 3.2 + float(k) * 3.2, 1.05, z + dz), 0.05,
						MatLib.wood_dark(), 6)
	# the jetty colliders are authored above; committing with collide off was
	# silently discarding them, leaving the piers walk-through
	_commit(mb, "Jetties", true)


# -------------------------------------------------------------------- quays

func _quays() -> void:
	var mb := MeshBuilder.new()
	var wall := MatLib.concrete_dark()
	var cap := MatLib.concrete()
	var canopy := MatLib.ground_plane("concrete", 0.34)

	# the canal wall: alternating blocks, capstone, and a stepped coping
	var z := -SQUARE * 0.5
	while z < SQUARE * 0.5:
		mb.box_at(Vector3(CANAL_X - CANAL_HALF - 0.6, BED_Y + 1.8, z + 1.5),
				Vector3(1.2, 4.0, 3.0), wall, Vector3.ZERO, 2.0)
		z += 3.0
	mb.box_at(Vector3(CANAL_X - CANAL_HALF - 0.4, 0.32, 0), Vector3(1.8, 0.5, SQUARE + 2.0), cap)
	mb.collide_at(Vector3(CANAL_X - CANAL_HALF - 0.6, BED_Y + 1.8, 0),
			Vector3(1.2, 4.0, SQUARE + 2.0))

	# mooring bollards, fenders and ladders down to the water.  All of it
	# stands on the west quay: the cut is 18 m bank to bank, so anything at
	# the old offsets now hangs over open water.
	for i in 12:
		var bz := -46.0 + float(i) * 8.4
		mb.cylinder_at(Vector3(CANAL_X - CANAL_HALF - 1.0, 0.9, bz), 0.20, 0.9,
				MatLib.metal_rust(), 10)
		mb.cylinder_at(Vector3(CANAL_X - CANAL_HALF - 1.0, 1.42, bz), 0.30, 0.16,
				MatLib.metal_rust(), 10)
		Kit.tyre(mb, Vector3(CANAL_X - CANAL_HALF - 0.35, -0.6, bz + 2.0), 0.0, 1.1)
	# ladders hang flush on the canal face of the quay wall, rungs reaching
	# from above the cap down under the waterline
	for i in 3:
		var lz := -28.0 + float(i) * 26.0
		mb.box_at(Vector3(CANAL_X - CANAL_HALF - 0.05, -1.0, lz), Vector3(0.10, 2.6, 0.7),
				MatLib.metal_dark())
		for k in 5:
			mb.box_at(Vector3(CANAL_X - CANAL_HALF - 0.05, 0.7 - float(k) * 0.55, lz + 0.35),
					Vector3(0.10, 0.06, 0.7), MatLib.metal_dark())

	# the northern quay: a raised apron with kerbs and a row of lamps
	mb.slab(Vector3(0, 0.16, -46.0), SQUARE + 12.0, 10.0, 0.34, canopy, 0.0, 3.0)
	mb.box_at(Vector3(0, 0.34, -41.2), Vector3(SQUARE + 12.0, 0.16, 0.4), MatLib.concrete())
	mb.collide_at(Vector3(0, 0.16, -46.0), Vector3(SQUARE + 12.0, 0.34, 10.0))

	# stacks of fish crates and coiled line along the quay edge
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	# keep the stacks east of the cut: a crate floating mid-canal reads as a bug
	for i in 22:
		var cx := -28.0 + r.randf_range(0.0, 70.0)
		var cz := -43.0 + r.randf_range(-2.0, 3.0)
		var h := r.randi_range(1, 3)
		for k in h:
			mb.box_at(Vector3(cx, 0.52 + float(k) * 0.42, cz),
					Vector3(0.72, 0.40, 0.52), MatLib.wood_pale(),
					Vector3(0, r.randf_range(-14.0, 14.0), 0))
		mb.collide_at(Vector3(cx, 0.9, cz), Vector3(0.9, 1.4, 0.8))
	for i in 5:
		var cz2 := -40.0 + float(i) * 6.0
		mb.cylinder_at(Vector3(-SQUARE * 0.5 + 2.4, 0.14, cz2), 0.55, 0.28,
				MatLib.plastic(Color("3b5a4a")), 12)
	_commit(mb, "Quays")


# ----------------------------------------------------------------- buildings

func _buildings() -> void:
	var mb := MeshBuilder.new()

	# West bank: the fish warehouse, dockside doors and roof plant.
	Kit.building(mb, Vector3(CANAL_X - 22.0, 0.0, -14.0), 90.0, {
		"size": Vector3(30, 11, 44), "style": "office", "ruin": 0.25, "lit": 0.30,
		"collide": true, "seed": 311, "detail": 1,
	})
	Kit.building(mb, Vector3(CANAL_X - 24.0, 0.0, 34.0), 90.0, {
		"size": Vector3(26, 17, 28), "style": "tower", "ruin": 0.35, "lit": 0.26,
		"collide": true, "seed": 312, "detail": 1,
	})

	# East and south: the blocks that frame the square, blown open.
	Kit.building(mb, Vector3(SQUARE * 0.5 + 14.0, 0.0, 18.0), -90.0, {
		"size": Vector3(26, 21, 40), "style": "brick", "ruin": 0.45, "lit": 0.22,
		"collide": true, "seed": 313, "detail": 2,
	})
	Kit.building(mb, Vector3(SQUARE * 0.5 + 12.0, 0.0, -34.0), -90.0, {
		"size": Vector3(24, 13, 28), "style": "shack", "ruin": 0.6, "lit": 0.18,
		"collide": true, "seed": 314, "detail": 1,
	})
	Kit.building(mb, Vector3(-14.0, 0.0, SQUARE * 0.5 + 13.0), 180.0, {
		"size": Vector3(38, 14, 22), "style": "plaster", "ruin": 0.4, "lit": 0.24,
		"collide": true, "seed": 315, "detail": 2,
	})
	Kit.building(mb, Vector3(26.0, 0.0, SQUARE * 0.5 + 16.0), 180.0, {
		"size": Vector3(24, 10, 24), "style": "brick", "ruin": 0.55, "lit": 0.20,
		"collide": true, "seed": 316, "detail": 1,
	})

	# the loading dock awning along the warehouse face
	var b := Kit.basis_yaw(90.0)
	var heading := -b.z
	Kit.awning(mb, b, Vector3(CANAL_X - 8.0, 4.4, -22.0), heading, 16.0)
	Kit.awning(mb, b, Vector3(CANAL_X - 8.0, 4.4, -4.0), heading, 16.0)
	Kit.scaffold(mb, Kit.basis_yaw(-90.0), Vector3(SQUARE * 0.5 + 1.0, 0.0, 6.0),
			Vector3(-1, 0, 0), 10.0, 13.0)
	_commit(mb, "Buildings")


# --------------------------------------------------------------- containers

## A shipping container: corrugated body, door end, corner castings.
static func _container(mb: MeshBuilder, pos: Vector3, yaw: float, col: Color,
		len := 6.1, double_door := true) -> void:
	var body := MatLib.painted(col, "cont_" + col.to_html())
	var trim := MatLib.metal_rust()
	var rib := MatLib.painted(col.darkened(0.22), "cont_rib_" + col.to_html())
	var b := Basis.from_euler(Vector3(0, deg_to_rad(yaw), 0))
	mb.box_basis(b, pos, Vector3(2.5, 2.6, len), body, 1.0)
	# corrugation on both long faces
	var n := int(len / 0.32)
	var fwd := b.z
	for i in n:
		var off := (float(i) - float(n - 1) * 0.5) * 0.32
		for side in [-1.0, 1.0]:
			mb.box_basis(b, pos + b.x * (side * 1.26) + fwd * off,
					Vector3(0.06, 2.5, 0.20), rib, 1.0)
	# corner castings and a door frame at each end
	for dz in [-len * 0.5 + 0.06, len * 0.5 - 0.06]:
		for dx in [-1.18, 1.18]:
			for dy in [-1.22, 1.22]:
				mb.box_basis(b, pos + b.x * dx + b.y * dy + fwd * dz,
						Vector3(0.30, 0.28, 0.30), MatLib.metal_dark())
		mb.box_basis(b, pos + fwd * dz, Vector3(2.44, 2.44, 0.10), trim)
		if double_door:
			for dx in [-0.61, 0.61]:
				mb.box_basis(b, pos + b.x * dx + fwd * (dz + signf(dz) * 0.06),
						Vector3(1.18, 2.30, 0.08), MatLib.painted(col.lightened(0.10),
								"door_" + col.to_html()))
	mb.collide_at(pos, Vector3(2.5, 2.6, len), yaw)


func _container_yard() -> void:
	var mb := MeshBuilder.new()
	var r := RandomNumberGenerator.new()
	r.seed = 9001
	var paints := [Color("8a3a2a"), Color("2a5a8a"), Color("4a5a3a"), Color("7a6a2a"),
			Color("5a4a6a"), Color("8a6a2a")]
	# two lanes of stacked containers: cover the player can read at a glance
	# `lane` needs to be typed: `var lx := 8.0 * lane` cannot infer through an
	# untyped loop variable and the whole chapter fails to parse.
	for lane: float in [-1.0, 1.0]:
		var lx := 8.0 * lane
		for i in 4:
			var z := -30.0 + float(i) * 15.0
			var stack := r.randi_range(1, 2)
			for k in stack:
				var col: Color = paints[r.randi() % paints.size()]
				_container(mb, Vector3(lx + r.randf_range(-1.4, 1.4), 1.35 + float(k) * 2.62, z),
						r.randf_range(-8.0, 8.0) + (0.0 if lane < 0.0 else 4.0), col)
			if stack > 1 and r.randf() < 0.7:
				mb.box_at(Vector3(lx, 2.75 + float(stack - 1) * 2.62, z + 3.4),
						Vector3(2.2, 2.2, 2.4), MatLib.painted(Color("3f5a52"), "cont_end"))
				mb.collide_at(Vector3(lx, 2.75 + float(stack - 1) * 2.62, z + 3.4),
						Vector3(2.2, 2.2, 2.4))
			# hazard stripes and a tag on the ground
			mb.slab(Vector3(lx, 0.03, z + 4.6), 3.2, 1.2, 0.04,
					MatLib.flat(Color(0.62, 0.52, 0.16), "hazard", 0.8), 0.0, 1.0)
	_commit(mb, "ContainerYard")


# ------------------------------------------------------------------- market

func _market() -> void:
	var mb := MeshBuilder.new()
	var r := RandomNumberGenerator.new()
	r.seed = 771
	# two rows of stalls flanking a lane through the middle of the square
	for row in 2:
		var z := -8.0 + float(row) * 22.0
		for i in 6:
			var x := -20.0 + float(i) * 8.2
			var yaw := 0.0 if row == 1 else 180.0
			Kit.stall(mb, Vector3(x, 0.0, z), yaw, 100 + i * 7 + row * 3)
			# stock: crates, sacks, bottles, hanging bulbs
			for k in 4:
				var sx := x + r.randf_range(-1.7, 1.7)
				mb.box_at(Vector3(sx, 1.14, z + r.randf_range(-0.4, 0.4)),
						Vector3(0.52, 0.34, 0.52), MatLib.wood_dark(),
						Vector3(0, r.randf_range(0.0, 40.0), 0))
				mb.collide_at(Vector3(sx, 1.0, z), Vector3(0.6, 0.8, 0.6))
			mb.box_at(Vector3(x + r.randf_range(-1.6, 1.6), 1.30, z + 0.55),
					Vector3(0.80, 0.44, 0.60), MatLib.wood_pale(),
					Vector3(0, r.randf_range(-12.0, 12.0), 0))
			if i % 2 == 0:
				mb.cylinder_at(Vector3(x - 2.1, 1.32, z + 1.1), 0.34, 0.42,
						MatLib.plastic(Color("6a3030")), 12)
	# string lights down the lane between the stall rows
	var bulb := Kit.emissive(Color("ffc98a"), 2.6)
	for i in 13:
		var x2 := -26.0 + float(i) * 4.4
		var sag := 2.35 - 0.28 * sin(PI * fmod(float(i), 4.0) / 4.0)
		mb.pipe(Vector3(x2, sag, -8.0), Vector3(x2 + 4.4, 2.35 - 0.28 * sin(PI * fmod(float(i) + 1.0, 4.0) / 4.0), -8.0),
				0.02, MatLib.metal_dark(), 5)
		mb.pipe(Vector3(x2, sag, 14.0), Vector3(x2 + 4.4, 2.35 - 0.28 * sin(PI * fmod(float(i) + 1.0, 4.0) / 4.0), 14.0),
				0.02, MatLib.metal_dark(), 5)
		if i < 12:
			mb.box_at(Vector3(x2 + 2.2, 2.12, -8.0), Vector3(0.06, 0.14, 0.06), bulb)
			mb.box_at(Vector3(x2 + 2.2, 2.12, 14.0), Vector3(0.06, 0.14, 0.06), bulb)
	_commit(mb, "Market")

	# warm stalls need their own light or the square reads as a car park
	for spec in [
		Vector3(-16.0, 2.3, -8.0), Vector3(0.0, 2.3, -8.0), Vector3(16.0, 2.3, -8.0),
		Vector3(-16.0, 2.3, 14.0), Vector3(0.0, 2.3, 14.0), Vector3(16.0, 2.3, 14.0),
	]:
		Build.omni(props(), spec, Color("ffb877"), 2.6, 11.0, false, 1.3)


# --------------------------------------------------------------- crane rig

func _crane_rig() -> void:
	_crane = Node3D.new()
	_crane.position = Vector3(30, 0, -34)
	props().add_child(_crane)
	var mb := MeshBuilder.new()
	var steel := MatLib.metal_rust()
	# two legs on bogies, a lattice girder spanning them, and a trolley
	for dx in [-13.0, 13.0]:
		for dz in [-2.2, 2.2]:
			mb.cylinder_at(Vector3(dx, 9.0, dz), 0.26, 18.0, steel, 10)
			mb.box_at(Vector3(dx, 0.35, dz), Vector3(1.6, 0.6, 1.6), MatLib.metal_dark())
			Kit.tyre(mb, Vector3(dx, 0.45, dz - 0.9), 0.0, 1.6)
			Kit.tyre(mb, Vector3(dx, 0.45, dz + 0.9), 0.0, 1.6)
		# cross bracing
		for k in 5:
			var y := 2.0 + float(k) * 3.2
			mb.pipe(Vector3(dx, y, -2.2), Vector3(dx, y + 3.2, 2.2), 0.10, steel, 6)
			mb.pipe(Vector3(dx, y, 2.2), Vector3(dx, y + 3.2, -2.2), 0.10, steel, 6)
		mb.collide_at(Vector3(dx, 9.0, 0), Vector3(0.9, 18.0, 5.0))
	for k in 22:
		var x := -13.0 + float(k) * 1.24
		mb.box_at(Vector3(x, 18.4, -2.2), Vector3(0.16, 1.1, 0.16), steel)
		mb.box_at(Vector3(x, 18.4, 2.2), Vector3(0.16, 1.1, 0.16), steel)
		mb.box_at(Vector3(x, 18.4, 0.0), Vector3(0.14, 0.14, 4.3), steel)
	mb.box_at(Vector3(0, 17.6, -2.2), Vector3(27.0, 0.22, 0.22), steel)
	mb.box_at(Vector3(0, 17.6, 2.2), Vector3(27.0, 0.22, 0.22), steel)
	mb.box_at(Vector3(0, 19.3, 0.0), Vector3(1.0, 0.10, 4.6), steel)
	mb.collide_at(Vector3(0, 18.4, 0.0), Vector3(27.0, 2.6, 4.6))
	mb.commit(props(), "CraneFrame", true)

	# the trolley hangs a container over the lane, swaying
	_hook = Node3D.new()
	_hook.position = Vector3(-4.0, 17.6, 0.0)
	_crane.add_child(_hook)
	var hm := MeshBuilder.new()
	hm.box_at(Vector3(0, 0.0, 0.0), Vector3(1.3, 0.9, 1.6), MatLib.metal_dark())
	hm.box_at(Vector3(0, -0.6, 0.0), Vector3(0.7, 0.4, 0.7), MatLib.metal_rust())
	for dx in [-0.6, 0.6]:
		hm.pipe(Vector3(dx, -0.6, 0), Vector3(dx * 2.2, -11.4, 0), 0.045, MatLib.metal_dark(), 5)
	_container(hm, Vector3(0, -13.4, 0), 6.0, Color("8a3a2a"))
	hm.commit(_hook, "CraneHook", true)
	Build.omni(_hook, Vector3(0, -12.0, 0), Color("ffb070"), 2.0, 12.0, false, 1.0)


func _process(delta: float) -> void:
	super._process(delta)
	## The hook drifts, which is what sells the thing as suspended weight.
	if _hook == null:
		return
	_t += delta
	_hook.position.x = -4.0 + sin(_t * 0.31) * 2.6
	_hook.position.z = cos(_t * 0.24) * 1.8
	_hook.rotation.y = sin(_t * 0.19) * 0.08


# ----------------------------------------------------------------- dressing

func _dressing() -> void:
	var mb := MeshBuilder.new()
	var r := RandomNumberGenerator.new()
	r.seed = 515

	# boats riding the canal, lashed up against the west bank.  Berths are
	# explicit: clear of the slipway (z 21..27) and of the pipe-rack legs at
	# z -6 and 16, and the hulls ride high enough to pass under the pipes.
	for bz in [-36.0, -14.0, 8.0, 34.0]:
		# riding at -0.3 the hulls break the surface but still duck under the
		# pipe rack, and their keels hang clear of the bed
		Kit.boat(mb, Vector3(CANAL_X - 2.5 + r.randf_range(-2.0, 2.0), -0.3, bz),
				90.0 + r.randf_range(-7.0, 7.0), r.randf_range(7.0, 12.0))

	# fish market clutter: barrels, pallets, tyres, cones, nets on the ground
	for i in 26:
		var px := r.randf_range(-28.0, 44.0)   # east of the cut
		var pz := r.randf_range(-36.0, 40.0)
		var pick := r.randi() % 5
		match pick:
			0: Kit.barrel(mb, Vector3(px, 0.0, pz), r.randf_range(0.0, 90.0),
					Color("7a6a4a") if r.randf() < 0.5 else Color("44523a"))
			1: Kit.pallet(mb, Vector3(px, 0.0, pz), r.randf_range(0.0, 90.0))
			2: Kit.tyre(mb, Vector3(px, 0.0, pz), r.randf_range(0.0, 90.0))
			3: Kit.traffic_cone(mb, Vector3(px, 0.0, pz), r.randf_range(0.0, 90.0))
			4: Kit.crate(mb, Vector3(px, 0.0, pz), Vector3(0.9, 0.8, 0.9),
					r.randf_range(0.0, 90.0), r.randf() < 0.5)

	# a perimeter of barricades and wire that the picket is holding
	for i in 5:
		var bx := -22.0 + float(i) * 11.0
		Kit.barrier(mb, Vector3(bx, 0.0, -38.0), 0.0)
		Kit.barrier(mb, Vector3(bx + 5.5, 0.0, -38.0), 0.0)
	Kit.sandbag_wall(mb, Vector3(-26.0, 0.0, 30.0), Vector3(-6.0, 0.0, 30.0), 1.05, 9)
	Kit.sandbag_wall(mb, Vector3(4.0, 0.0, 30.0), Vector3(24.0, 0.0, 30.0), 1.05, 8)

	# debris where the shelling came through
	Kit.debris_pile(mb, Vector3(38.0, 0.0, 30.0), 6.0, 12)
	Kit.rubble(mb, Vector3(-22.0, 0.0, 42.0), Vector3(14.0, 2.4, 10.0), 90, 13)
	Kit.rubble(mb, Vector3(40.0, 0.0, -14.0), Vector3(10.0, 2.0, 16.0), 70, 14)
	Kit.debris_pile(mb, Vector3(-14.0, 0.0, -30.0), 4.5, 15)

	# overhead cables and laundry strung between the blocks
	Kit.wires(mb, Vector3(-14.0, 9.0, 42.0), Vector3(14.0, 12.0, 40.0), 1.4, 5)
	Kit.wires(mb, Vector3(SQUARE * 0.5 + 1.0, 12.0, 6.0), Vector3(SQUARE * 0.5 + 1.0, 12.0, 34.0), 1.1, 4)
	Kit.laundry(mb, Vector3(-22.0, 4.4, -22.0), Vector3(-22.0, 4.2, -2.0), 21)
	# the pipeline runs the canal on a rack stood in the water: the four
	# stanchion legs are the only mid-channel cover a swimmer gets.  The span
	# (z -6..16) keeps the legs clear of every boat berth and of the slipway,
	# and the pipes ride at 1.3-1.55 m -- above hull height, so the boats
	# moor underneath.
	Kit.pipe_run(mb, Vector3(CANAL_X - 3.0, 0.0, -6.0), Vector3(CANAL_X - 3.0, 0.0, 16.0), 1.55, 2, 0.22, 4)
	Kit.pipe_run(mb, Vector3(CANAL_X + 3.0, 0.0, 16.0), Vector3(CANAL_X + 3.0, 0.0, -6.0), 1.3, 3, 0.13, 5)
	_stanchion(mb, Vector3(CANAL_X - 3.0, 0.0, -6.0))
	_stanchion(mb, Vector3(CANAL_X - 3.0, 0.0, 16.0))
	_stanchion(mb, Vector3(CANAL_X + 3.0, 0.0, -6.0))
	_stanchion(mb, Vector3(CANAL_X + 3.0, 0.0, 16.0))

	# market signage boards
	for i in 4:
		var sx := -18.0 + float(i) * 12.0
		mb.box_at(Vector3(sx, 3.4, 22.6), Vector3(3.2, 1.1, 0.10),
				MatLib.fabric(Color("7a3230")))
		mb.box_at(Vector3(sx, 3.4, -16.6), Vector3(3.2, 1.1, 0.10),
				MatLib.fabric(Color("2f4a5a")))
	_commit(mb, "MarketDressing")

	add_pickup(Vector3(-11, 0, 14), "ammo", 120)
	add_pickup(Vector3(21, 0, -10), "ammo", 120)
	add_pickup(Vector3(0, 0, -28), "health", 55)


## A pipe stanchion stood in the canal: keyed into the bed, topped by the
## cross beams the pipeline rests on.
func _stanchion(mb: MeshBuilder, base: Vector3) -> void:
	var steel := MatLib.metal_dark()
	var rust := MatLib.metal_rust()
	for dz in [-0.45, 0.45]:
		mb.cylinder_at(base + Vector3(0, -0.1, dz), 0.14, 5.0, steel, 8)
		mb.collide_at(base + Vector3(0, -0.1, dz), Vector3(0.3, 5.0, 0.3))
	mb.box_at(base + Vector3(0, 1.42, 0), Vector3(0.18, 0.16, 2.0), rust)
	mb.box_at(base + Vector3(0, 1.62, 0), Vector3(0.16, 0.14, 2.0), rust)


# ---------------------------------------------------------------- atmosphere

func _atmosphere() -> void:
	rain(2400)
	embers(60, Vector3(46, 6, 46))
	Build.sun(self, Vector3(-11, 148, 0), Color("ff9c52"), 0.85, 3.2)
	fire_barrel(Vector3(-20, 0, 26))
	fire_barrel(Vector3(24, 0, -30))
	fire_barrel(Vector3(-4, 0, 40))
	# floods on the quay and the warehouse face
	for i in 4:
		Build.spot(props(), Vector3(-30.0 + float(i) * 20.0, 8.0, -40.0), Vector3(-26, 180, 0),
				Color("ffd0a0"), 3.0, 40.0, 34.0, true, 2.0)
	# streetlamp() fills a MeshBuilder and returns the lamp head, which is where
	# its light goes -- the props() container is not a builder, and passing one
	# was a parse error that stopped this chapter loading at all.
	var lamps := MeshBuilder.new()
	var heads := [Vector3(-30.0, 0.0, -30.0), Vector3(-30.0, 0.0, 30.0),
			Vector3(38.0, 0.0, -6.0), Vector3(38.0, 0.0, 26.0)]
	var arms := [1.0, -1.0, -1.0, 1.0]
	for i in heads.size():
		var head := Kit.streetlamp(lamps, heads[i], 0.0, float(arms[i]), true)
		Build.omni(props(), head, Color("ffab5c"), 4.0, 17.0, false, 1.0)
	_commit(lamps, "QuayLamps")
	FX.dust(self, 180, Vector3(40, 8, 60), 0.04, Color(0.86, 0.84, 0.80, 0.12))


# ------------------------------------------------------------------- enemies

func _spawn_wave_one() -> void:
	_wave_one = [
		spawn_enemy(Vector3(-18, 0, -4), "trooper", ring_patrol(Vector3(-18, 0, -4), 8.0, 3)),
		spawn_enemy(Vector3(16, 0, -4), "trooper", ring_patrol(Vector3(16, 0, -4), 8.0, 3, 1.0)),
		spawn_enemy(Vector3(0, 0, -20), "trooper", line_patrol(Vector3(-10, 0, -20), Vector3(10, 0, -20), 3)),
		spawn_enemy(Vector3(0, 0, 12), "heavy", line_patrol(Vector3(-6, 0, 12), Vector3(6, 0, 12), 2)),
	]
	for e in _wave_one:
		e.died.connect(_on_enemy_died)


func _spawn_wave_two() -> void:
	# the counter-attack lands on the east pier, south of the north quay.
	# The old set straddled the canal cut: a third of the wave spawned over
	# open water, where swimmers cannot follow the fight.
	var entries := [
		Vector3(-28, 0, -39), Vector3(34, 0, -30), Vector3(-14, 0, -38),
		Vector3(24, 0, -38), Vector3(0, 0, -40),
	]
	var kinds := ["trooper", "trooper", "trooper", "trooper", "heavy"]
	for i in entries.size():
		var e := spawn_enemy(entries[i], kinds[i], [])
		e.died.connect(_on_enemy_died)
		_wave_two.append(e)
	# they know roughly where the player is
	if game != null and game.player != null:
		for e in _wave_two:
			e.receive_alert(game.player.global_position)
	AudioDirector.play("enemy_alert", -4.0, 0.9, 0.0, "Voice")
	GameManager.toast_message("CONTACT FROM THE EAST PIER")


## Alive count within one wave, so the permanent monument garrison does not
## stall the wave progression.
func _wave_alive(list: Array) -> int:
	var n := 0
	for e in list:
		if is_instance_valid(e) and e.alive:
			n += 1
	return n


func _on_enemy_died(_e: Node) -> void:
	if _wave == 1:
		if _wave_alive(_wave_one) > 0:
			return
		_wave = 2
		complete("break")
		objective("hold", "Hold the market")
		notify("That was the picket. The rest are coming.")
		await get_tree().create_timer(3.0).timeout
		_spawn_wave_two()
	elif _wave == 2 and not done("hold"):
		if _wave_alive(_wave_two) > 0:
			return
		complete("hold")
		objective("monument", "Shoot the monument")
		notify("The market is yours. Their monument is not.")
		await get_tree().create_timer(2.0).timeout
		_monument_garrison(false)


# ---------------------------------------------------------------- monument

## The occupiers have raised their monument on the far quay.  A pair of guards
## circles it from the start; once the market is held, the rest of the garrison
## doubles down around it.
func _monument_garrison(initial: bool) -> void:
	if initial:
		var body := place_monument(Vector3(10.0, 0.0, -46.0), 180.0, 0.22, 360.0)
		monument_on_down(body, _on_monument_down)
		_garrison = [
			spawn_enemy(Vector3(4.0, 0, -46.0), "guard",
					ring_patrol(Vector3(10.0, 0, -46.0), 6.0, 4)),
			spawn_enemy(Vector3(16.0, 0, -46.0), "guard",
					ring_patrol(Vector3(10.0, 0, -46.0), 6.0, 4, PI)),
		]
		body.damaged.connect(func(_amount: float, point: Vector3) -> void:
			for g in _garrison:
				if is_instance_valid(g) and g.alive:
					g.receive_alert(point))
		# a floodlight so the pale stone reads across the water
		Build.spot(props(), Vector3(10.0, 7.0, -38.0), Vector3(-24, 0, 0),
				Color("ffd9a8"), 12.0, 40.0, 30.0, true, 2.0)
		add_pickup(Vector3(10.0, 0.0, -38.0), "ammo", 90)
	else:
		for spec in [[Vector3(-2.0, 0, -50.0), "guard"],
				[Vector3(22.0, 0, -50.0), "guard"],
				[Vector3(10.0, 0, -40.0), "heavy"]]:
			var e := spawn_enemy(spec[0], spec[1], [])
			_garrison.append(e)
			e.receive_alert(Vector3(10.0, 0, -46.0))
		notify("THE GARRISON CLOSES ON THE MONUMENT")


func _on_monument_down() -> void:
	complete("monument")
	notify("THE MONUMENT IS DOWN")
	for e in _garrison:
		if is_instance_valid(e) and e.alive:
			e.queue_free()
	_garrison.clear()
	await get_tree().create_timer(2.6).timeout
	finish()


func surface_at(pos: Vector3) -> String:
	# below the canal bed's shoulder: the deck stands at y=0 and the water at
	# 0.11, so only bodies actually down in the cut are "in" water
	if pos.y < -1.2:
		return "water"
	return "concrete"


## Camera vantages for automated look review (`--capture`).
func review_vantages() -> Array:
	return [
		{"name": "approach", "pos": Vector3(0, 0.6, 50.0), "yaw": 0.0, "pitch": -0.02},
		{"name": "canal", "pos": Vector3(-30.0, 0.6, 20.0), "yaw": -1.4, "pitch": 0.0},
		{"name": "boats", "pos": Vector3(-26.0, 0.6, -10.0), "yaw": -1.2, "pitch": -0.05},
		{"name": "stalls", "pos": Vector3(0, 0.6, 22.0), "yaw": 0.0, "pitch": 0.04},
		{"name": "lane", "pos": Vector3(-24.0, 0.6, 3.0), "yaw": 1.55, "pitch": 0.02},
		{"name": "containers", "pos": Vector3(-8.0, 0.6, -12.0), "yaw": 2.0, "pitch": 0.06},
		{"name": "crane", "pos": Vector3(22.0, 0.6, -10.0), "yaw": -1.9, "pitch": 0.45},
		{"name": "quay", "pos": Vector3(0, 0.6, -30.0), "yaw": 0.0, "pitch": 0.10},
		{"name": "warehouse", "pos": Vector3(-14.0, 0.6, -14.0), "yaw": -1.5, "pitch": 0.14},
		{"name": "square", "pos": Vector3(10.0, 0.6, 34.0), "yaw": 0.25, "pitch": 0.06},
	]
