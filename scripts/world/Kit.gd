class_name Kit
## The architecture and prop kit.
##
## Chapters never place boxes directly; they place *things*.  A building here is
## a perforated facade with reveals, sills, floor bands, a plinth, a cornice, a
## parapet and rooftop plant; a car has a body, a cabin, glass, lamps, wheels and
## a grille.  All of it is baked into shared merged meshes by MeshBuilder, so the
## detail costs triangles and nothing else.
##
## Everything is deterministic: a `seed` reproduces a street exactly, which is
## what makes the look reviewable and regressions visible.

const STREET_Y := 0.0

static var _derived: Dictionary = {}


# ------------------------------------------------------------------ materials

static func m(set_name: String, tint := Color.WHITE, tile := -1.0) -> Material:
	return TexLib.mat(set_name, tint, tile)


static func interior(level := 0.05) -> Material:
	if level >= 0.09:
		return TexLib.interior(0.085)
	return TexLib.interior(level)


static func glass(dark := false) -> Material:
	if dark:
		return TexLib.glass(Color(0.055, 0.065, 0.075), 0.72)
	return TexLib.glass(Color(0.30, 0.37, 0.40), 0.5)


## A window that has someone living behind it.
static func lit_window(color := Color("ffc074"), energy := 1.3) -> Material:
	var key := "lit_%s_%.1f" % [color.to_html(true), energy]
	if _derived.has(key):
		return _derived[key]
	var mm := TexLib.mat("canvas", color, 1.1, 1.0, color, energy)
	mm.roughness = 1.0
	_derived[key] = mm
	return mm


static func curtain(color := Color("b9c4cc")) -> Material:
	var key := "curtain_%s" % color.to_html(true)
	if _derived.has(key):
		return _derived[key]
	var mm := TexLib.mat("canvas", color, 1.3)
	mm.roughness = 1.0
	mm.albedo_color = color
	_derived[key] = mm
	return mm


static func grunge_decal() -> Material:
	return TexLib.grunge()


static func emissive(color: Color, energy := 3.0) -> Material:
	var key := "emit_%s_%.2f" % [color.to_html(true), energy]
	if _derived.has(key):
		return _derived[key]
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(color.r * 0.3, color.g * 0.3, color.b * 0.3)
	mm.roughness = 0.45
	mm.emission_enabled = true
	mm.emission = color
	mm.emission_energy_multiplier = energy
	_derived[key] = mm
	return mm


static func flat(color: Color, alpha := 1.0) -> Material:
	return TexLib.flat(color, alpha)


# ------------------------------------------------------------------- helpers

static func basis_yaw(yaw_deg: float) -> Basis:
	return Basis.from_euler(Vector3(0, deg_to_rad(yaw_deg), 0))


static func _pick(r: RandomNumberGenerator, a: Array):
	return a[r.randi() % a.size()]


static func rand_range_list(r: RandomNumberGenerator, a: Array) -> float:
	return r.randf_range(float(a[0]), float(a[1]))


# ==================================================================== BUILDINGS

## Facade styles.  Each entry is a set of material names plus the character of
## the detail: a brick tenement has small windows and ironwork, a concrete block
## has wide bays and recessed aluminium frames.
static func style(name: String) -> Dictionary:
	match name:
		"brick":
			return {
				"wall": "brick", "wall_dark": "brick", "trim": "concrete",
				"band": "concrete", "frame": "wood_pale", "plinth": "rock",
				"floor_h": 3.3, "bays_per_m": 0.24, "win_ratio": 0.42,
				"balcony": true, "ironwork": true,
			}
		"plaster":
			return {
				"wall": "plaster", "wall_dark": "plaster_blue", "trim": "concrete",
				"band": "concrete", "frame": "wood_pale", "plinth": "rock",
				"floor_h": 3.6, "bays_per_m": 0.20, "win_ratio": 0.46,
				"balcony": true, "ironwork": true,
			}
		"tower":
			return {
				"wall": "concrete", "wall_dark": "concrete_dark", "trim": "concrete",
				"band": "concrete_dark", "frame": "steel_paint", "plinth": "concrete_dark",
				"floor_h": 3.9, "bays_per_m": 0.14, "win_ratio": 0.62,
				"balcony": false, "ironwork": false,
			}
		"office":
			return {
				"wall": "concrete_dark", "wall_dark": "concrete_dark", "trim": "concrete",
				"band": "steel_paint", "frame": "steel_paint", "plinth": "concrete_dark",
				"floor_h": 3.8, "bays_per_m": 0.20, "win_ratio": 0.70,
				"balcony": false, "ironwork": false,
			}
		"shack":
			return {
				"wall": "wood", "wall_dark": "wood", "trim": "wood", "band": "wood",
				"frame": "wood_pale", "plinth": "rock", "floor_h": 2.9,
				"bays_per_m": 0.30, "win_ratio": 0.30, "balcony": false,
				"ironwork": false,
			}
	return style("plaster")


## One perforated facade wall.
##
## `w` runs along the wall's local X, `h` up its Y.  The wall is assembled from
## piers and horizontal bands, which leaves real openings we can then dress with
## a reveal, glazing, a sill and a lintel.
static func facade(mb: MeshBuilder, b: Basis, origin: Vector3, heading: Vector3,
		w: float, h: float, thickness: float, st: Dictionary, seed: int,
		floors: int, bays: int, ruin_cut := 999, ground_shop := false,
		detail := 2, lit := 0.22) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	# `heading` is the outward normal; local X runs along the wall
	var along := heading.cross(Vector3.UP).normalized()
	if along.length_squared() < 0.5:
		along = Vector3.RIGHT
	var wall := m(String(st["wall"]))
	var band_m := m(String(st["band"]))
	var frame := m(String(st["frame"]))
	var floor_h: float = float(st["floor_h"])
	bays = maxi(bays, 1)
	var bay_w := w / float(bays)
	var pier_w := minf(0.72, bay_w * 0.30)
	var win_w := maxf(0.7, bay_w - pier_w * 2.0 - 0.10)

	var t := thickness

	# --- plinth: everything sits on a slightly proud base
	mb.box_basis(b, origin + Vector3(0, 0.7, 0) - heading * 0.06,
			Vector3(w, 1.4, t + 0.24), m("concrete_dark"))
	# grime where the wall meets the ground
	if detail >= 1:
		mb.quad(origin + heading * (t * 0.5 + 0.02) + Vector3(0, 0.02, 0),
				along, Vector3.UP, Vector2(w, 2.6), grunge_decal(), 0.25)

	for f in floors:
		var y0 := 1.4 + float(f) * floor_h
		var gh := floor_h
		var sill_h := 0.95
		var head_h := 0.62
		var win_h := maxf(0.8, gh - sill_h - head_h)
		var broken := f >= ruin_cut

		# floor band: the slab edge, which is what makes a stack of windows
		# read as storeys rather than as a grid
		mb.box_basis(b, origin + Vector3(0, y0 - 0.11, 0) + heading * 0.05,
				Vector3(w, 0.30, t + 0.34), band_m)

		for i in bays:
			var bx := -w * 0.5 + (float(i) + 0.5) * bay_w
			var bay_origin := origin + along * bx
			# a wrecked bay: no glazing, jagged stubs, still an opening
			var wrecked: bool = broken or (detail >= 1
					and bool(st.get("ironwork", false)) and r.randf() < 0.045)

			# piers
			var pw := pier_w
			var pier_mat := wall if f % 2 == 0 else m(String(st["wall_dark"]))
			mb.box_basis(b, bay_origin - along * (bay_w * 0.5 - pw * 0.5)
					+ Vector3(0, y0 + gh * 0.5, 0), Vector3(pw, gh, t), pier_mat)
			mb.box_basis(b, bay_origin + along * (bay_w * 0.5 - pw * 0.5)
					+ Vector3(0, y0 + gh * 0.5, 0), Vector3(pw, gh, t), pier_mat)

			if wrecked:
				# stub of wall above and below the blown-out opening
				mb.box_basis(b, bay_origin + Vector3(0, y0 + 0.16, 0),
						Vector3(win_w + 0.3, 0.32, t), band_m)
				mb.box_basis(b, bay_origin + Vector3(0, y0 + gh - 0.18, 0),
						Vector3(win_w + 0.3, 0.36, t), band_m)
				mb.box_basis(b, bay_origin + heading * (-0.45)
						+ Vector3(0, y0 + gh * 0.5, 0),
						Vector3(win_w + 0.4, win_h, 0.5), interior(0.045))
				if detail >= 2 and r.randf() < 0.6:
					# rebar clawing out of the empty frame
					for k in 3:
						var rp := bay_origin + along * r.randf_range(-win_w * 0.4, win_w * 0.4) \
								+ heading * (t * 0.4) \
								+ Vector3(0, y0 + gh + 0.15 + float(k) * 0.05, 0)
						mb.cylinder_at(rp, 0.035, r.randf_range(0.3, 0.75), m("steel_rust"), 5)
				continue

			# spandrel below the window and head above it
			mb.box_basis(b, bay_origin + Vector3(0, y0 + sill_h * 0.5, 0),
					Vector3(bay_w, sill_h, t), wall)
			mb.box_basis(b, bay_origin + Vector3(0, y0 + sill_h + win_h + head_h * 0.5, 0),
					Vector3(bay_w, head_h, t), wall)

			# the reveal: dark interior so the opening has depth
			mb.box_basis(b, bay_origin + heading * (-0.42)
					+ Vector3(0, y0 + sill_h + win_h * 0.5, 0),
					Vector3(win_w + 0.26, win_h + 0.2, 0.55), interior(0.05))

			# glazing
			var wx := bay_origin + heading * (-t * 0.35) \
					+ Vector3(0, y0 + sill_h + win_h * 0.5, 0)
			var roll := r.randf()
			if roll < lit:
				var warm := Color("ffc074") if r.randf() < 0.72 else Color("cfe4ff")
				mb.quad(wx, along, Vector3.UP, Vector2(win_w, win_h),
						lit_window(warm, r.randf_range(0.45, 1.05)))
			elif roll < lit + 0.16:
				mb.quad(wx - heading * 0.18, along, Vector3.UP, Vector2(win_w, win_h),
						curtain(_pick(r, [Color("b7c0c8"), Color("c8bda6"),
								Color("9fb0b8")])))
			else:
				mb.quad(wx, along, Vector3.UP, Vector2(win_w, win_h), glass())

			if detail >= 2:
				# sash frames and a central mullion
				mb.box_basis(b, wx + heading * 0.03, Vector3(win_w, 0.10, 0.10), frame)
				var mull := maxi(1, int(win_w / 0.9))
				for k in mull:
					var mx := -win_w * 0.5 + (float(k) + 0.5) * (win_w / float(mull))
					mb.box_basis(b, wx + along * mx + heading * 0.02,
							Vector3(0.085, win_h, 0.09), frame)

			# sill, lintel, and something left on the ledge
			mb.box_basis(b, bay_origin + heading * 0.16
					+ Vector3(0, y0 + sill_h - 0.05, 0),
					Vector3(bay_w - pier_w * 0.6, 0.14, 0.42), m(String(st["trim"])))
			mb.box_basis(b, bay_origin + heading * 0.10
					+ Vector3(0, y0 + sill_h + win_h + 0.10, 0),
					Vector3(win_w + 0.34, 0.20, 0.30), m(String(st["trim"])))
			if detail >= 2 and r.randf() < 0.16:
				var px := bay_origin + heading * 0.34 \
						+ Vector3(0, y0 + sill_h + 0.28, 0)
				mb.box_at(px, Vector3(0.62, 0.42, 0.36), m("steel_paint"), Vector3(0, -90, 0))
				mb.box_at(px + heading * 0.20, Vector3(0.44, 0.30, 0.05),
						m("steel_rust"), Vector3(0, -90, 0))
			elif detail >= 2 and r.randf() < 0.10:
				# a planter gone feral
				mb.box_at(bay_origin + heading * 0.30
						+ Vector3(0, y0 + sill_h + 0.20, 0),
						Vector3(0.5, 0.28, 0.3), m("steel_rust"))
				mb.box_at(bay_origin + heading * 0.30
						+ Vector3(0, y0 + sill_h + 0.42, 0),
						Vector3(0.46, 0.24, 0.26), m("grass"))

		# --- per-floor extras -------------------------------------------------
		if detail >= 2 and bool(st.get("balcony", false)) and f > 0 and r.randf() < 0.22:
			var bx2 := -w * 0.5 + (float(r.randi() % bays) + 0.5) * bay_w
			_balcony(mb, b, origin + along * bx2, heading, floor_h, y0, bay_w)

	# --- top of the wall ------------------------------------------------------
	var built := mini(floors, ruin_cut)
	var ytop := 1.4 + float(built) * floor_h
	if ruin_cut < floors:
		# sheared off: a broken lip of slab, jagged stubs, clawing rebar
		mb.box_basis(b, origin + Vector3(0, ytop, 0),
				Vector3(w, 0.34, t + 0.3), m("concrete_dark"))
		if detail >= 1:
			var n := maxi(2, int(w / 1.4))
			for i in n:
				var px := -w * 0.5 + (float(i) + 0.5) * (w / float(n))
				var hh := r.randf_range(0.25, 1.15)
				mb.box_basis(b, origin + along * px + Vector3(0, ytop + hh * 0.5 + 0.1, 0),
						Vector3(w / float(n) * r.randf_range(0.5, 0.98), hh, t),
						band_m)
				if r.randf() < 0.35:
					mb.cylinder_at(origin + along * px + Vector3(0, ytop + hh + 0.35, 0),
							0.03, 0.7, m("steel_rust"), 5)
	else:
		# crown wall filling up to the cornice, then cornice, parapet, coping
		var crown_h := maxf(0.34, h - 0.52 - ytop)
		mb.box_basis(b, origin + Vector3(0, ytop + crown_h * 0.5, 0),
				Vector3(w, crown_h, t), wall)
		mb.box_basis(b, origin + Vector3(0, h - 0.30, 0) + heading * 0.12,
				Vector3(w + 0.44, 0.42, t + 0.5), m(String(st["trim"])))
		mb.box_basis(b, origin + Vector3(0, h + 0.36, 0),
				Vector3(w, 0.74, t * 0.9), wall)
		mb.box_basis(b, origin + heading * (t * 0.5), Vector3(w, 0.14, t + 0.16),
				m("concrete_dark"))

	# --- rain goods down the wall --------------------------------------------
	if detail >= 2:
		var n_pipes := 1 + int(w / 14.0)
		for i in n_pipes:
			var px2 := -w * 0.5 + (float(i) + 0.5) * (w / float(n_pipes))
			var ppx := origin + along * px2 + heading * (t * 0.5 + 0.13)
			var ph := float(ruin_cut if ruin_cut < floors else floors) * floor_h + 1.4
			mb.cylinder_at(ppx + Vector3(0, ph * 0.5, 0), 0.10, ph, m("steel_rust"), 7)
			for k in int(ph / 4.0):
				mb.box_at(ppx + Vector3(0, 1.6 + float(k) * 4.0, 0) - heading * 0.13,
						Vector3(0.34, 0.10, 0.16), m("steel_rust"))
			if r.randf() < 0.5:
				mb.box_at(ppx + heading * 0.10 + Vector3(0, 2.0, 0),
						Vector3(0.3, 0.5, 0.3), m("steel_rust"))

	# --- ground floor treatment ----------------------------------------------
	if ground_shop:
		_shopfront(mb, b, origin, heading, w, t, st, r, detail)


static func _balcony(mb: MeshBuilder, b: Basis, at: Vector3, heading: Vector3,
		floor_h: float, y0: float, bay_w: float) -> void:
	var w := bay_w * 0.92
	var rail := Vector3.UP * 1.02
	var floor := at + heading * 0.62 + Vector3(0, y0 + 0.06, 0)
	mb.box_basis(b, floor, Vector3(w, 0.16, 1.24), m("concrete_dark"))
	# railings
	var along := heading.cross(Vector3.UP).normalized()
	mb.box_basis(b, floor + heading * 0.58 + rail, Vector3(w, 0.07, 0.07), m("steel_rust"))
	mb.box_basis(b, floor + heading * 0.02 + rail, Vector3(w, 0.07, 0.07), m("steel_rust"))
	for i in int(w / 0.28) + 1:
		var px := -w * 0.5 + float(i) * (w / float(maxi(1, int(w / 0.28))))
		if absf(px) > w * 0.5 + 0.01:
			continue
		mb.box_basis(b, floor + heading * 0.30 + along * px + Vector3(0, 0.55, 0),
				Vector3(0.05, 1.0, 0.05), m("steel_rust"))
	for s in [-1.0, 1.0]:
		mb.box_basis(b, floor + heading * 0.30 + along * (s * w * 0.5)
				+ Vector3(0, 0.55, 0), Vector3(0.05, 1.0, 1.18), m("steel_rust"))


static func _shopfront(mb: MeshBuilder, b: Basis, origin: Vector3, heading: Vector3,
		w: float, t: float, st: Dictionary, r: RandomNumberGenerator,
		detail: int) -> void:
	# recessed dark glazing with a stall riser, a door and a sign cabinet
	var glass_h := 2.6
	mb.box_basis(b, origin + heading * (-1.1) + Vector3(0, 1.7, 0),
			Vector3(w * 0.82, 3.4, 0.4), interior(0.045))
	mb.box_basis(b, origin + heading * (-0.55) + Vector3(0, 1.6, 0),
			Vector3(w * 0.8, glass_h, 0.10), glass(true))
	mb.box_basis(b, origin + heading * (-0.5) + Vector3(0, 0.28, 0),
			Vector3(w * 0.84, 0.56, 0.4), m("concrete_dark"))
	# jambs and head
	for s in [-1.0, 1.0]:
		mb.box_basis(b, origin + heading * (-0.5) + Vector3(0, 1.9, 0)
				+ heading.cross(Vector3.UP).normalized() * (s * w * 0.42),
				Vector3(0.5, 3.8, t + 0.2), m(String(st["trim"])))
	mb.box_basis(b, origin + heading * (-0.4) + Vector3(0, 3.62, 0),
			Vector3(w, 0.44, t + 0.3), m(String(st["trim"])))
	if detail >= 2:
		# mullions and a door
		var along := heading.cross(Vector3.UP).normalized()
		for i in 3:
			var px := -w * 0.4 + (float(i) + 1.0) * (w * 0.8 / 4.0)
			mb.box_basis(b, origin + heading * (-0.45) + along * px \
					+ Vector3(0, 1.7, 0), Vector3(0.10, glass_h, 0.14),
					m(String(st["trim"])))
		mb.box_basis(b, origin + heading * (-0.42) + along * (w * 0.30) \
				+ Vector3(0, 1.05, 0), Vector3(1.0, 2.1, 0.12), m("wood"))
		# sign cabinet
		var col: Color = _pick(r, [Color("ff7a4a"), Color("6fd0ff"), Color("ffd166"),
				Color("8ef0b8")])
		mb.box_basis(b, origin + heading * 0.35 + Vector3(0, 4.35, 0),
				Vector3(w * 0.72, 0.95, 0.34), m("steel_paint"))
		mb.box_basis(b, origin + heading * 0.53 + Vector3(0, 4.35, 0),
				Vector3(w * 0.64, 0.72, 0.06), emissive(col, 3.4))


## A whole building: four facades, a roof deck and rooftop plant.
##
## opts:
##   size     Vector3 (width, height, depth)
##   style    style name
##   seed     int
##   ruin     0..1 -- probability mass for shearing the top floors off
##   lit      0..1 -- chance a window is lit
##   detail   0..2
##   collide  bool
##   faces    array of bool [front, back, left, right] for full detail
static func building(mb: MeshBuilder, pos: Vector3, yaw_deg: float, opts := {}) -> Dictionary:
	var size: Vector3 = opts.get("size", Vector3(12, 22, 12))
	var st := style(String(opts.get("style", "plaster")))
	var seed := int(opts.get("seed", 1))
	var ruin := float(opts.get("ruin", 0.5))
	var lit := float(opts.get("lit", 0.22))
	var detail := int(opts.get("detail", 2))
	var r := RandomNumberGenerator.new()
	r.seed = seed

	var b := basis_yaw(yaw_deg)
	var w := size.x
	var d := size.z
	var h := size.y
	var floor_h: float = float(st["floor_h"])
	var floors := maxi(2, int((h - 1.4) / floor_h))
	# the real height is whatever the floors add up to, so bands line up
	h = 1.4 + float(floors) * floor_h + 0.9

	var ruin_cut := 999
	if r.randf() < ruin:
		ruin_cut = clampi(floors - r.randi_range(1, maxi(1, int(floors * 0.55))), 2, floors)
	var active_floors := mini(floors, ruin_cut)
	var top := 1.4 + float(active_floors) * floor_h

	var bays_front := maxi(2, int(w * float(st["bays_per_m"])))
	var bays_side := maxi(2, int(d * float(st["bays_per_m"])))
	var t := 0.40
	var half := Vector3(w * 0.5, 0, d * 0.5)

	# --- one collision volume for the whole footprint; the interior is a shell
	#     so that light actually falls off behind the windows
	if bool(opts.get("collide", true)):
		mb.collide(Transform3D(b, pos + Vector3(0, (top + 9.0) * 0.5, 0)),
				Vector3(w, top + 9.0, d))
	# interior floor slabs, which is what keeps the inside black
	for f in range(1, active_floors + 1):
		mb.box(Transform3D(b, pos + Vector3(0, 1.4 + float(f) * floor_h - 0.18, 0)),
				Vector3(w - 0.3, 0.36, d - 0.3), m("concrete_dark"))

	# --- the four facades
	var specs := [
		{"nrm": Vector3(0, 0, 1), "off": Vector3(0, 0, half.z), "w": w,
			"bays": bays_front, "shop": true},
		{"nrm": Vector3(0, 0, -1), "off": Vector3(0, 0, -half.z), "w": w,
			"bays": bays_front, "shop": false},
		{"nrm": Vector3(1, 0, 0), "off": Vector3(half.x, 0, 0), "w": d,
			"bays": bays_side, "shop": false},
		{"nrm": Vector3(-1, 0, 0), "off": Vector3(-half.x, 0, 0), "w": d,
			"bays": bays_side, "shop": false},
	]
	var faces: Array = opts.get("faces", [true, true, true, true])
	for i in specs.size():
		var s: Dictionary = specs[i]
		if not bool(faces[i]):
			continue
		var nrm: Vector3 = b * (s["nrm"] as Vector3)
		var off: Vector3 = b * (s["off"] as Vector3)
		var fd := detail
		if i >= 2:
			fd = mini(detail, 1)
		var cut := 999
		# only the front facade and one side are allowed to be the taller face
		if i < 2:
			cut = ruin_cut
		elif i == 2 and ruin_cut < floors:
			cut = ruin_cut
		facade(mb, b, pos + off, nrm, float(s["w"]), h, t, st,
				seed * 31 + i * 7, floors, int(s["bays"]), cut,
				bool(s["shop"]) and bool(opts.get("shop", true)), fd, lit)

	# --- ground slab so the interior has a floor to stand on
	mb.box(Transform3D(b, pos + Vector3(0, 0.06, 0)),
			Vector3(w - 0.3, 0.4, d - 0.3), m("concrete_floor"))
	# --- roof deck and plant
	_roof(mb, b, pos, size, top, st, r, detail, ruin_cut < floors)
	# --- sign / antenna mast
	if detail >= 2 and r.randf() < 0.5:
		_mast(mb, b, pos, top, r)

	return {"height": top, "floors": floors, "bays": bays_front}


static func _roof(mb: MeshBuilder, b: Basis, pos: Vector3, size: Vector3, top: float,
		st: Dictionary, r: RandomNumberGenerator, detail: int, broken: bool) -> void:
	var w := size.x
	var d := size.z
	# deck: full footprint, so nothing can see down between the walls
	mb.box(Transform3D(b, pos + Vector3(0, top + 0.16, 0)),
			Vector3(w + 0.1, 0.34, d + 0.1), m("roof"))
	if detail < 1:
		return
	# parapet ring + coping
	for s in [[Vector3(0, 0, d * 0.5), Vector3(w, 0.9, 0.3)],
			[Vector3(0, 0, -d * 0.5), Vector3(w, 0.9, 0.3)],
			[Vector3(w * 0.5, 0, 0), Vector3(0.3, 0.9, d)],
			[Vector3(-w * 0.5, 0, 0), Vector3(0.3, 0.9, d)]]:
		var off: Vector3 = s[0]
		var sz: Vector3 = s[1]
		var hh := 0.9 if not broken else r.randf_range(0.4, 1.0)
		mb.box(Transform3D(b, pos + off + Vector3(0, top + 0.74, 0)),
				Vector3(sz.x, hh, sz.z), m(String(st["wall"])))
		if r.randf() < 0.7:
			mb.box(Transform3D(b, pos + off + Vector3(0, top + 1.2, 0)),
					Vector3(sz.x + 0.14, 0.14, sz.z + 0.14), m("concrete_dark"))
	if detail < 2:
		return

	var inner := Vector3(maxf(1.0, w - 1.6), 0, maxf(1.0, d - 1.6))
	# stair bulkhead with a door and its own little roof
	if r.randf() < 0.85:
		var bp := pos + b * Vector3(r.randf_range(-inner.x * 0.28, inner.x * 0.28), 0,
				r.randf_range(-inner.z * 0.28, inner.z * 0.28))
		mb.box(Transform3D(b, bp + Vector3(0, top + 1.9, 0)),
				Vector3(3.4, 2.9, 3.0), m(String(st["wall_dark"])))
		mb.box(Transform3D(b, bp + Vector3(0, top + 3.5, 0)),
				Vector3(3.9, 0.3, 3.5), m("concrete_dark"))
		mb.box(Transform3D(b, bp + b * Vector3(0, 0, 1.52) + Vector3(0, top + 1.25, 0)),
				Vector3(1.1, 2.2, 0.14), m("steel_paint"))

	# plant: chillers, tanks, ducts, vents
	var n := r.randi_range(3, 7)
	for i in n:
		var p := pos + b * Vector3(r.randf_range(-inner.x * 0.45, inner.x * 0.45), 0,
				r.randf_range(-inner.z * 0.45, inner.z * 0.45))
		var kind := r.randi() % 4
		match kind:
			0:  # chiller
				mb.box(Transform3D(b, p + Vector3(0, top + 1.05, 0)),
						Vector3(2.0, 1.4, 1.4), m("steel_paint"))
				mb.cylinder_at(p + b * Vector3(0.62, 0, 0) + Vector3(0, top + 1.95, 0),
						0.42, 0.3, m("steel_rust"), 10)
				mb.box(Transform3D(b, p + Vector3(0, top + 0.55, 0.73)),
						Vector3(1.6, 0.8, 0.06), m("steel_rust"))
			1:  # duct run
				var q := p + b * Vector3(r.randf_range(1.5, 4.0), 0, 0)
				mb.box(Transform3D(b, (p + q) * 0.5 + Vector3(0, top + 0.85, 0)),
						Vector3((q - p).length(), 0.8, 0.8), m("steel_paint"))
				mb.cylinder_at(q + Vector3(0, top + 1.5, 0), 0.35, 0.9,
						m("steel_rust"), 10)
			2:  # water tank on legs
				var legs := 1.1
				for s in [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1),
						Vector3(-1, 0, -1)]:
					mb.box(Transform3D(b, p + s * 0.7 + Vector3(0, top + legs * 0.5, 0)),
							Vector3(0.16, legs, 0.16), m("steel_rust"))
				mb.cylinder_at(p + Vector3(0, top + legs + 1.05, 0), 1.05, 2.1,
						m("wood"), 12)
				mb.cylinder_at(p + Vector3(0, top + legs + 2.20, 0), 1.15, 0.25,
						m("steel_rust"), 12, Vector3(0, 0, 0))
			3:  # vents and a fan
				for k in r.randi_range(1, 3):
					var vp := p + b * Vector3(r.randf_range(-1.0, 1.0), 0,
							r.randf_range(-1.0, 1.0))
					mb.cylinder_at(vp + Vector3(0, top + 0.75, 0), 0.28, 0.9,
							m("steel_rust"), 9)
					mb.cylinder_at(vp + Vector3(0, top + 1.28, 0), 0.40, 0.14,
							m("steel_paint"), 9)

	# a few satellite dishes and aerials for silhouette
	for i in r.randi_range(1, 4):
		var p2 := pos + b * Vector3(r.randf_range(-inner.x * 0.45, inner.x * 0.45), 0,
				r.randf_range(-inner.z * 0.45, inner.z * 0.45))
		if r.randf() < 0.55:
			mb.cylinder_at(p2 + Vector3(0, top + 1.4, 0), 0.05, 2.6, m("steel_rust"), 6)
			mb.box(Transform3D(b, p2 + Vector3(0, top + 2.7, 0)),
					Vector3(1.1, 0.05, 0.05), m("steel_rust"))
			mb.box(Transform3D(b, p2 + Vector3(0, top + 2.7, 0)),
					Vector3(0.05, 0.05, 0.9), m("steel_rust"))
		else:
			mb.cylinder_at(p2 + Vector3(0, top + 0.25, 0), 0.05, 0.5, m("steel_rust"), 6)
			mb.prism(Transform3D(b * Basis.from_euler(Vector3(deg_to_rad(70), 0, 0)),
					p2 + Vector3(0, top + 0.78, 0)), 0.52, 0.12, 12, m("steel_paint"), 0.7)


static func _mast(mb: MeshBuilder, b: Basis, pos: Vector3, top: float,
		r: RandomNumberGenerator) -> void:
	var hp := r.randf_range(3.5, 11.0)
	var p := pos + b * Vector3(r.randf_range(-2, 2), 0, r.randf_range(-2, 2))
	mb.cylinder_at(p + Vector3(0, top + hp * 0.5, 0), 0.14, hp, m("steel_rust"), 7)
	for i in int(hp / 2.2):
		mb.box(Transform3D(b, p + Vector3(0, top + 1.6 + float(i) * 2.2, 0)),
				Vector3(1.2, 0.06, 0.06), m("steel_rust"))
	var col: Color = _pick(r, [Color("ff5a4a"), Color("ffc46a")])
	mb.box(Transform3D(b, p + Vector3(0, top + hp + 0.3, 0)),
			Vector3(0.3, 0.3, 0.3), emissive(col, 6.0))


# ------------------------------------------------------------- fire escapes

static func fire_escape(mb: MeshBuilder, b: Basis, origin: Vector3, heading: Vector3,
		top: float, floors: int, floor_h: float, width := 2.6) -> void:
	var along := heading.cross(Vector3.UP).normalized()
	var frame := m("steel_rust")
	for f in range(0, floors):
		var y := 3.4 + float(f) * floor_h
		# landing
		mb.box(Transform3D(b, origin + heading * 0.72 + Vector3(0, y, 0)),
				Vector3(width, 0.10, 1.5), frame)
		# grating streaks
		for k in int(width / 0.24):
			mb.box(Transform3D(b, origin + heading * 0.95
					+ along * (-width * 0.5 + (float(k) + 0.5) * 0.24)
					+ Vector3(0, y + 0.06, 0)), Vector3(0.06, 0.03, 1.3), frame)
		# railings
		for s in [-1.0, 1.0]:
			mb.box(Transform3D(b, origin + heading * 0.72
					+ along * (s * width * 0.5) + Vector3(0, y + 0.55, 0)),
					Vector3(0.06, 1.05, 1.5), frame)
		mb.box(Transform3D(b, origin + heading * 1.44 + Vector3(0, y + 1.05, 0)),
				Vector3(width, 0.07, 0.07), frame)
		mb.box(Transform3D(b, origin + heading * 0.04 + Vector3(0, y + 1.05, 0)),
				Vector3(width, 0.07, 0.07), frame)
		for k in int(width / 0.34):
			mb.box(Transform3D(b, origin + heading * 1.44
					+ along * (-width * 0.5 + (float(k) + 0.5) * 0.34)
					+ Vector3(0, y + 0.52, 0)), Vector3(0.05, 1.0, 0.05), frame)
		# stair to the landing below
		if f > 0:
			var steps := 9
			for k in steps:
				var yy := y - float(k + 1) * (floor_h / float(steps))
				mb.box(Transform3D(b, origin + heading * 1.1
						+ along * (-width * 0.42 + float(k) * (width * 0.9
						/ float(steps))) + Vector3(0, yy + 0.6, 0)),
						Vector3(0.34, 0.07, 0.9), frame)
	# stringers
	mb.box(Transform3D(b, origin + heading * 0.72 + Vector3(0, top * 0.5, 0)),
			Vector3(0.08, top, 0.08), frame)
	for s in [-1.0, 1.0]:
		mb.box(Transform3D(b, origin + heading * 0.72 + along * (s * width * 0.5)
				+ Vector3(0, top * 0.5, 0)), Vector3(0.07, top, 0.07), frame)


# ===================================================================== HOUSES

## A two-storey house with a gable roof, porch, chimney and a fenced yard.
## The residential beat needs a completely different silhouette from the
## mid-rise avenue, and nothing changes a skyline like a pitched roof.
static func house(mb: MeshBuilder, pos: Vector3, yaw_deg: float, seed := 1,
		opts := {}) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var b := basis_yaw(yaw_deg)
	var w := float(opts.get("width", r.randf_range(7.5, 11.0)))
	var d := float(opts.get("depth", r.randf_range(7.0, 10.0)))
	var storeys := int(opts.get("storeys", 2))
	var fh := 2.9
	var wall_h := float(storeys) * fh + 0.5
	var body_m: Material = opts.get("wall", m("plaster", _pick(r, [
			Color("d8cfc0"), Color("b9c6c0"), Color("c9b49c"), Color("a9b6bd")]))) 
	var trim_m := m("wood_pale")
	var roof_col: Color = _pick(r, [Color("3b3733"), Color("4a3b33"), Color("2f3a3c")])
	var roof_m := m("wood", roof_col, 1.6)

	# body
	mb.box(Transform3D(b, pos + Vector3(0, wall_h * 0.5, 0)),
			Vector3(w, wall_h, d), body_m)
	mb.collide(Transform3D(b, pos + Vector3(0, wall_h * 0.5 + 3.0, 0)),
			Vector3(w, wall_h + 6.0, d))
	# weatherboard shadow lines
	for i in int(wall_h / 0.55):
		var y := 0.3 + float(i) * 0.55
		mb.box(Transform3D(b, pos + Vector3(0, y, d * 0.5 + 0.01)),
				Vector3(w, 0.03, 0.04), m("wood", Color("241d16")))
		mb.box(Transform3D(b, pos + Vector3(0, y, -d * 0.5 - 0.01)),
				Vector3(w, 0.03, 0.04), m("wood", Color("241d16")))

	# windows: two per storey on the front, one on each side
	for s in storeys:
		var y0 := 0.85 + float(s) * fh
		for k in [-0.26, 0.26]:
			var wx := pos + b * Vector3(w * k, y0 + 0.95, d * 0.5 + 0.05)
			mb.box(Transform3D(b, wx - b * Vector3(0, 0, 0.22)), Vector3(1.35, 1.6, 0.42),
					interior(0.05))
			mb.quad(wx, b.x, Vector3.UP, Vector2(1.15, 1.4),
					glass() if r.randf() > 0.28 else lit_window(Color("ffc074"), 2.0))
			mb.box(Transform3D(b, wx + b * Vector3(-0.60, 0, 0.0)), Vector3(0.12, 1.5, 0.14), trim_m)
			mb.box(Transform3D(b, wx + b * Vector3(0.60, 0, 0.0)), Vector3(0.12, 1.5, 0.14), trim_m)
			mb.box(Transform3D(b, wx + b * Vector3(0, 0.78, 0.0)), Vector3(1.5, 0.12, 0.14), trim_m)
			mb.box(Transform3D(b, wx + b * Vector3(0, -0.78, 0.0)), Vector3(1.5, 0.12, 0.14), trim_m)
			mb.box(Transform3D(b, wx + b * Vector3(0, -0.86, 0.10)), Vector3(1.7, 0.14, 0.36), trim_m)
			if s == 1 and r.randf() < 0.35:
				mb.box(Transform3D(b, wx + b * Vector3(0, -0.55, 0.30)), Vector3(1.0, 0.5, 0.3),
						m("steel_rust"))

	# door with a small porch and steps
	var dx := pos + b * Vector3(-w * 0.26, 0, d * 0.5 + 0.05)
	mb.box(Transform3D(b, dx), Vector3(1.05, 2.15, 0.18), m("wood", Color("3a2b1e")))
	mb.box(Transform3D(b, dx + b * Vector3(0, 2.35, 0)), Vector3(1.6, 0.3, 0.6), trim_m)
	for s in [-1.0, 1.0]:
		mb.box(Transform3D(b, dx + b * Vector3(s * 0.85, 1.2, 0.6)), Vector3(0.14, 2.4, 0.14), trim_m)
	mb.box(Transform3D(b, dx + b * Vector3(0, 2.5, 0.55)), Vector3(2.1, 0.16, 1.4), roof_m)
	mb.box(Transform3D(b, dx + b * Vector3(0, 0.14, 0.6)), Vector3(1.7, 0.28, 1.1), m("concrete"))

	# gable roof
	var rh := float(opts.get("roof_height", r.randf_range(1.8, 3.1)))
	var overhang := 0.42
	var rw := w + overhang * 2.0
	var rd := d + overhang * 2.0
	var pitch := atan2(rh, rd * 0.5)
	var slab_len := sqrt(rh * rh + rd * rd * 0.25) + 0.1
	var t := 0.20
	for s in [-1.0, 1.0]:
		var mid := pos + b * Vector3(0, wall_h + rh * 0.5, s * rd * 0.25)
		mb.box(Transform3D(b * Basis.from_euler(Vector3(s * pitch, 0, 0)), mid),
				Vector3(rw, t, slab_len), roof_m)
	# gable ends
	for s in [-1.0, 1.0]:
		var zz := pos + b * Vector3(0, wall_h, s * (d * 0.5 - 0.02))
		mb.tri2(zz + b * Vector3(-w * 0.5, 0, 0), zz + b * Vector3(w * 0.5, 0, 0),
				zz + b * Vector3(0, rh, 0), body_m)
		mb.box(Transform3D(b, zz + Vector3(0, rh * 0.5, 0)), Vector3(0.2, rh, 0.2), body_m)
	# ridge cap
	mb.box(Transform3D(b, pos + Vector3(0, wall_h + rh + 0.06, 0)),
			Vector3(rw + 0.1, 0.16, 0.34), roof_m)
	# fascia
	for s in [-1.0, 1.0]:
		mb.box(Transform3D(b, pos + Vector3(0, wall_h + 0.06, s * rd * 0.5)),
				Vector3(rw, 0.22, 0.12), trim_m)

	# chimney and a gutter downpipe
	var cx := pos + b * Vector3(w * 0.28, 0, -d * 0.12)
	mb.box(Transform3D(b, cx + Vector3(0, wall_h + rh * 0.85, 0)),
			Vector3(0.72, rh * 1.3 + 1.1, 0.72), m("brick"))
	mb.box(Transform3D(b, cx + Vector3(0, wall_h + rh * 0.85 + (rh * 1.3 + 1.1) * 0.5, 0)),
			Vector3(0.86, 0.16, 0.86), m("concrete_dark"))
	for s in [-1.0, 1.0]:
		mb.cylinder_at(pos + b * Vector3(s * (w * 0.5 + 0.1), wall_h * 0.45, d * 0.5 + 0.1),
				0.07, wall_h * 0.9, m("steel_rust"), 6)

	# yard fence
	var yard := float(opts.get("yard", 0.0))
	if yard > 0.5:
		var picket := m("wood_pale", Color("c8c2b4"))
		for s in [-1.0, 1.0]:
			var fx := pos + b * Vector3(s * (w * 0.5 + 0.2), 0, d * 0.5 + yard)
			for i in int(yard / 0.28):
				mb.box(Transform3D(b, fx + b * Vector3(0, 0.45, -float(i) * 0.28
						- d * 0.5)), Vector3(0.06, 0.9, 0.09), picket)
			mb.box(Transform3D(b, fx + b * Vector3(0, 0.72, -yard * 0.5)),
					Vector3(0.05, 0.08, yard), picket)
		mb.box(Transform3D(b, pos + b * Vector3(w * 0.5 + 0.2, 0.45, -d * 0.5 - 0.2)),
				Vector3(yard, 0.9, 0.09), picket)


# ======================================================================= CAMP

## A ridge tent: canvas over a frame, with a doorway you can read.
static func tent(mb: MeshBuilder, pos: Vector3, yaw_deg: float, seed := 1,
		col := Color("556040")) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var b := basis_yaw(yaw_deg)
	var w := r.randf_range(2.6, 3.6)
	var d := r.randf_range(3.6, 5.0)
	var h := r.randf_range(1.5, 1.9)
	var canvas := m("canvas", col, 1.2)
	var ridge := pos + Vector3(0, h, 0)
	# the two slopes, built as explicit triangles so the ridge stays crisp
	for s in [-1.0, 1.0]:
		var p0 := pos + b * Vector3(0, 0.02, -d * 0.5)
		var p1 := pos + b * Vector3(0, 0.02, d * 0.5)
		var p2 := ridge + b * Vector3(0, 0, d * 0.5)
		var p3 := ridge + b * Vector3(0, 0, -d * 0.5)
		if s < 0:
			mb.tri2(p0, p3, p2, canvas)
			mb.tri2(p0, p2, p1, canvas)
		else:
			mb.tri2(p0, p2, p3, canvas)
			mb.tri2(p0, p1, p2, canvas)
	# gable ends
	for s in [-1.0, 1.0]:
		var zz := pos + b * Vector3(0, 0, s * d * 0.5)
		mb.tri2(zz + b * Vector3(-w * 0.4, 0.02, 0), zz + b * Vector3(w * 0.4, 0.02, 0),
				zz + Vector3(0, h * 0.92, 0), canvas)
	# ridge pole, guys and pegs
	mb.pipe(ridge + b * Vector3(0, -0.06, -d * 0.5 - 0.2),
			ridge + b * Vector3(0, -0.06, d * 0.5 + 0.2), 0.045, m("wood"), 6)
	for s in [-1.0, 1.0]:
		mb.pipe(pos + b * Vector3(s * w * 0.5, 0.02, -d * 0.5),
				ridge + b * Vector3(0, 0, -d * 0.5), 0.04, m("steel_rust"), 5)
		mb.pipe(pos + b * Vector3(s * w * 0.5, 0.02, d * 0.5),
				ridge + b * Vector3(0, 0, d * 0.5), 0.04, m("steel_rust"), 5)


static func flagpole(mb: MeshBuilder, pos: Vector3, yaw_deg: float, height := 7.0,
		col := Color("b8402f")) -> void:
	var b := basis_yaw(yaw_deg)
	mb.cylinder_at(pos + Vector3(0, height * 0.5, 0), 0.09, height, m("steel_paint", Color("8a8f94")), 8)
	mb.box(Transform3D(b, pos + Vector3(0, 0.2, 0)), Vector3(0.7, 0.4, 0.7), m("concrete"))
	var top := pos + Vector3(0, height - 0.12, 0)
	mb.quad(top + b * Vector3(0.1, 0, 0), b.x, Vector3.UP, Vector2(2.2, 1.3),
			m("canvas", col, 1.0))


# ====================================================================== MARKET

## A trader's stall: trestle, tarp canopy, goods.
static func stall(mb: MeshBuilder, pos: Vector3, yaw_deg: float, seed := 1) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var b := basis_yaw(yaw_deg)
	var w := r.randf_range(2.6, 3.8)
	var d := 1.5
	var canopy: Color = _pick(r, [Color("8a4a34"), Color("3f5a52"), Color("6a5a34"),
			Color("4a4458")])
	var wood := m("wood")
	# trestle
	mb.box(Transform3D(b, pos + Vector3(0, 0.86, 0)), Vector3(w, 0.09, d), wood)
	for s in [-1.0, 1.0]:
		mb.box(Transform3D(b, pos + b * Vector3(s * (w * 0.5 - 0.2), 0.43, 0)),
				Vector3(0.10, 0.86, d - 0.2), wood)
		mb.box(Transform3D(b, pos + b * Vector3(s * (w * 0.5 - 0.2), 0.10, 0)),
				Vector3(0.14, 0.12, d - 0.1), wood)
	# back posts and canopy
	for s in [-1.0, 1.0]:
		mb.box(Transform3D(b, pos + b * Vector3(s * w * 0.5, 1.05, -d * 0.5 - 0.2)),
				Vector3(0.1, 2.1, 0.1), m("steel_rust"))
		mb.box(Transform3D(b, pos + b * Vector3(s * w * 0.5, 1.05, d * 0.5 + 0.2)),
				Vector3(0.1, 2.1, 0.1), m("steel_rust"))
	mb.quad(pos + b * Vector3(-w * 0.5 - 0.25, 2.0, -d * 0.5 - 0.35), b.x, b.z,
			Vector2(w + 0.5, d + 0.7), m("canvas", canopy, 1.1))
	mb.box(Transform3D(b, pos + Vector3(0, 1.95, 0)), Vector3(w + 0.5, 0.08, 0.08),
			m("steel_rust"))
	# goods
	for i in int(w / 0.42):
		var px := -w * 0.5 + (float(i) + 0.5) * (w / maxf(1.0, float(int(w / 0.42))))
		if r.randf() < 0.25:
			continue
		var st := Vector3(r.randf_range(0.2, 0.34), r.randf_range(0.16, 0.3),
				r.randf_range(0.2, 0.34))
		mb.box(Transform3D(b, pos + b * Vector3(px, 0.91 + st.y * 0.5, r.randf_range(-0.3, 0.3))),
				st, _pick(r, [m("canvas", Color("8a6a3a"), 0.5), m("wood_pale"),
				m("steel_rust", Color("5a6a4a")), m("brick")]))


# ================================================================== VEHICLES

static func car(mb: MeshBuilder, pos: Vector3, yaw_deg: float, variant := 0,
		seed := 1, wrecked := true) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var b := basis_yaw(yaw_deg)
	const BODY_COLS := [Color("2f4756"), Color("5b3230"), Color("39423a"),
			Color("6b6a63"), Color("23303a"), Color("7a4a2a")]
	var col: Color = BODY_COLS[variant % BODY_COLS.size()]
	var body := m("steel_paint", col)
	var tyre := m("steel_rust", Color("191a1c"))
	var L := 4.5
	var W := 1.86
	var glass_mat := glass(true)
	# chassis
	mb.box(Transform3D(b, pos + Vector3(0, 0.62, 0)), Vector3(W, 0.72, L), body)
	# lower sill darker
	mb.box(Transform3D(b, pos + Vector3(0, 0.34, 0)), Vector3(W + 0.04, 0.26, L - 1.5),
			m("steel_rust", Color("2a2a2c")))
	# bonnet and boot
	mb.box(Transform3D(b, pos + Vector3(0, 1.12, -L * 0.30)), Vector3(W - 0.14, 0.34, L * 0.34), body)
	mb.box(Transform3D(b, pos + Vector3(0, 1.14, L * 0.34)), Vector3(W - 0.14, 0.30, L * 0.26), body)
	# cabin
	mb.box(Transform3D(b, pos + Vector3(0, 1.34, 0.10)), Vector3(W - 0.22, 0.70, L * 0.40), body)
	for s in [-1.0, 1.0]:
		mb.box(Transform3D(b, pos + Vector3(s * (W * 0.5 - 0.13), 1.36, 0.10)),
				Vector3(0.06, 0.52, L * 0.34), glass_mat)
	mb.box(Transform3D(b, pos + Vector3(0, 1.40, -0.62)), Vector3(W - 0.30, 0.56, 0.07), glass_mat)
	mb.box(Transform3D(b, pos + Vector3(0, 1.40, 0.82)), Vector3(W - 0.30, 0.50, 0.07), glass_mat)
	if wrecked and r.randf() < 0.55:
		mb.box(Transform3D(b, pos + Vector3(0, 1.62, 0.10)), Vector3(W - 0.30, 0.34, L * 0.36),
				m("steel_rust", Color("241f1c")))
	# wheels
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var wp := pos + b * Vector3(sx * (W * 0.5 - 0.06), 0.36, sz * L * 0.31)
			mb.prism(Transform3D(b * Basis.from_euler(Vector3(0, 0, deg_to_rad(90))), wp),
					0.36, 0.22, 14, tyre)
	# lamps
	mb.box(Transform3D(b, pos + Vector3(W * 0.30, 0.80, -L * 0.5 - 0.02)),
			Vector3(0.42, 0.20, 0.10), m("steel_paint", Color("c9d6d8")))
	mb.box(Transform3D(b, pos + Vector3(-W * 0.30, 0.80, -L * 0.5 - 0.02)),
			Vector3(0.42, 0.20, 0.10), m("steel_paint", Color("c9d6d8")))
	mb.box(Transform3D(b, pos + Vector3(W * 0.30, 0.80, L * 0.5 + 0.02)),
			Vector3(0.36, 0.18, 0.08), emissive(Color("ff4a30"), 0.8))
	mb.box(Transform3D(b, pos + Vector3(-W * 0.30, 0.80, L * 0.5 + 0.02)),
			Vector3(0.36, 0.18, 0.08), emissive(Color("ff4a30"), 0.8))
	# bumper
	mb.box(Transform3D(b, pos + Vector3(0, 0.52, -L * 0.5 - 0.05)),
			Vector3(W - 0.10, 0.22, 0.14), m("steel_rust", Color("3a3a3c")))


static func bus(mb: MeshBuilder, pos: Vector3, yaw_deg: float, col := Color("2b4a44")) -> void:
	var b := basis_yaw(yaw_deg)
	var body := m("steel_paint", col)
	var L := 11.0
	var W := 2.5
	mb.box(Transform3D(b, pos + Vector3(0, 1.75, 0)), Vector3(W, 2.6, L), body)
	mb.box(Transform3D(b, pos + Vector3(0, 3.16, 0)), Vector3(W + 0.1, 0.24, L + 0.1),
			m("steel_rust", Color("3a3c3e")))
	# window band
	for s in [-1.0, 1.0]:
		mb.box(Transform3D(b, pos + Vector3(s * (W * 0.5 + 0.02), 2.42, 0)),
				Vector3(0.06, 1.0, L - 1.4), glass(true))
	mb.box(Transform3D(b, pos + Vector3(0, 2.42, -L * 0.5 - 0.02)),
			Vector3(W - 0.3, 1.1, 0.06), glass(true))
	mb.box(Transform3D(b, pos + Vector3(0, 2.60, L * 0.5 + 0.02)),
			Vector3(W - 0.4, 0.9, 0.06), glass(true))
	# skirt, door, destination blind
	mb.box(Transform3D(b, pos + Vector3(0, 0.42, 0)), Vector3(W + 0.04, 0.5, L), m("steel_rust", Color("1d1f21")))
	mb.box(Transform3D(b, pos + Vector3(W * 0.5 - 0.01, 1.5, -L * 0.30)),
			Vector3(0.1, 2.0, 1.1), m("steel_paint", Color("1a1c1e")))
	mb.box(Transform3D(b, pos + Vector3(0, 3.05, -L * 0.5 - 0.04)),
			Vector3(W - 1.0, 0.4, 0.06), emissive(Color("ffb45a"), 2.4))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var wp := pos + b * Vector3(sx * (W * 0.5 - 0.05), 0.62, sz * L * 0.33)
			mb.prism(Transform3D(b * Basis.from_euler(Vector3(0, 0, deg_to_rad(90))), wp),
					0.62, 0.3, 14, m("steel_rust", Color("17181a")))


## A half-sunk hull.  `bow` points along the local -Z.
static func boat(mb: MeshBuilder, pos: Vector3, yaw_deg: float, length := 8.0,
		col := Color("3a3830"), tilt := 0.0) -> void:
	var b := basis_yaw(yaw_deg) * Basis.from_euler(Vector3(deg_to_rad(tilt), 0, 0))
	var hull := m("steel_rust", col)
	var beam := length * 0.34
	var depth := beam * 0.62
	var deck_y := depth * 0.34
	# hull sides taper towards the bow: build as three segments
	for i in 4:
		var f0 := float(i) / 4.0
		var f1 := float(i + 1) / 4.0
		var z0 := -length * 0.5 + f0 * length
		var z1 := -length * 0.5 + f1 * length
		var w0 := beam * (0.45 + 0.55 * smoothstep(0.0, 0.35, f0))
		var w1 := beam * (0.45 + 0.55 * smoothstep(0.0, 0.35, f1))
		var ww := (w0 + w1) * 0.5
		var cz := (z0 + z1) * 0.5
		mb.box(Transform3D(b, pos + Vector3(0, deck_y - depth * 0.5, cz)),
				Vector3(ww, depth, (z1 - z0) * 1.02), hull)
		if i > 0:
			# gunwale rail
			for s in [-1.0, 1.0]:
				mb.box(Transform3D(b, pos + Vector3(s * ww * 0.5, deck_y + 0.10, cz)),
						Vector3(0.10, 0.22, z1 - z0), hull)
	# deck and cabin
	mb.box(Transform3D(b, pos + Vector3(0, deck_y + 0.04, length * 0.08)),
			Vector3(beam * 0.9, 0.12, length * 0.6), m("wood", Color("4a4438")))
	mb.box(Transform3D(b, pos + Vector3(0, deck_y + 0.75, length * 0.22)),
			Vector3(beam * 0.66, 1.3, length * 0.24), m("steel_paint", Color("6a5f4a")))
	mb.box(Transform3D(b, pos + Vector3(0, deck_y + 1.0, length * 0.13)),
			Vector3(beam * 0.5, 0.5, 0.06), glass(true))
	# mast
	mb.cylinder_at(pos + b * Vector3(0, deck_y + 2.0, length * 0.12), 0.06, 4.0,
			m("steel_rust"), 6, Vector3(_yaw_of(b), 0, 0))


static func _yaw_of(b: Basis) -> float:
	return rad_to_deg(atan2(b.x.z, b.x.x))


# ============================================================ STREET FURNITURE

static func streetlamp(mb: MeshBuilder, pos: Vector3, yaw_deg: float,
		arm_side := 1.0, tall := true) -> Vector3:
	var b := basis_yaw(yaw_deg)
	var metal := m("steel_paint", Color("2b2f33"))
	var h := 8.2 if tall else 5.4
	# base, shaft, arm, head
	mb.cylinder_at(pos + Vector3(0, 0.22, 0), 0.30, 0.44, metal, 10)
	mb.cylinder_at(pos + Vector3(0, h * 0.5 + 0.3, 0), 0.12, h, metal, 10)
	var arm := arm_side * 1.9
	mb.box(Transform3D(b, pos + b * Vector3(arm * 0.5, h + 0.28, 0)),
			Vector3(absf(arm), 0.13, 0.16), metal)
	mb.box(Transform3D(b, pos + b * Vector3(arm, h + 0.14, 0)),
			Vector3(0.72, 0.14, 0.42), metal)
	var lamp_y := h - 0.02
	mb.box(Transform3D(b, pos + b * Vector3(arm, lamp_y, 0)),
			Vector3(0.62, 0.11, 0.34), emissive(Color("ffb45a"), 1.7))
	# a little transformer box and a banner
	mb.box(Transform3D(b, pos + b * Vector3(0, 1.5, 0.16)), Vector3(0.34, 0.6, 0.24), m("steel_rust"))
	return pos + b * Vector3(arm, lamp_y - 0.5, 0)


static func traffic_light(mb: MeshBuilder, pos: Vector3, yaw_deg: float) -> void:
	var b := basis_yaw(yaw_deg)
	var metal := m("steel_paint", Color("22302c"))
	mb.cylinder_at(pos + Vector3(0, 2.6, 0), 0.14, 5.2, metal, 10)
	mb.box(Transform3D(b, pos + b * Vector3(1.5, 5.0, 0)), Vector3(3.0, 0.14, 0.14), metal)
	mb.box(Transform3D(b, pos + b * Vector3(3.0, 4.5, 0)), Vector3(0.36, 1.05, 0.3), metal)
	for i in 3:
		var c: Color = [Color("ff3b2f"), Color("ffc23b"), Color("3bff7a")][i]
		mb.box(Transform3D(b, pos + b * Vector3(3.0, 4.85 - float(i) * 0.32, 0.16)),
				Vector3(0.22, 0.22, 0.06), emissive(c, 1.6 if i == 2 else 0.25))


static func hydrant(mb: MeshBuilder, pos: Vector3) -> void:
	var rust := m("steel_red")
	mb.cylinder_at(pos + Vector3(0, 0.34, 0), 0.14, 0.68, rust, 10)
	mb.cylinder_at(pos + Vector3(0, 0.72, 0), 0.10, 0.30, rust, 10)
	mb.cylinder_at(pos + Vector3(0, 0.88, 0), 0.18, 0.10, rust, 10)
	for s in [-1.0, 1.0]:
		mb.cylinder_at(pos + Vector3(s * 0.16, 0.52, 0), 0.09, 0.16, rust, 8,
				Vector3(0, 0, 90))


static func bench(mb: MeshBuilder, pos: Vector3, yaw_deg: float) -> void:
	var b := basis_yaw(yaw_deg)
	var wood := m("wood", Color("4a3a26"))
	var iron := m("steel_rust")
	for s in [-1.0, 1.0]:
		mb.box(Transform3D(b, pos + b * Vector3(s * 0.72, 0.42, 0)), Vector3(0.10, 0.84, 0.52), iron)
	for i in 3:
		mb.box(Transform3D(b, pos + Vector3(0, 0.50, -0.16 + float(i) * 0.16)),
				Vector3(1.72, 0.07, 0.13), wood)
	for i in 3:
		mb.box(Transform3D(b, pos + b * Vector3(0, 0.72 + float(i) * 0.16, -0.24)),
				Vector3(1.72, 0.07, 0.13), wood)


static func bollard(mb: MeshBuilder, pos: Vector3, yaw_deg := 0.0) -> void:
	mb.cylinder_at(pos + Vector3(0, 0.36, 0), 0.11, 0.72, m("steel_rust"), 10)
	mb.cylinder_at(pos + Vector3(0, 0.74, 0), 0.13, 0.08, m("steel_rust"), 10)


static func crate(mb: MeshBuilder, pos: Vector3, size := Vector3(1.1, 1.0, 1.1),
		yaw_deg := 0.0, pale := false) -> void:
	var b := basis_yaw(yaw_deg)
	var wood := m("wood_pale" if pale else "wood")
	mb.box(Transform3D(b, pos + Vector3(0, size.y * 0.5, 0)), size, wood)
	# corner battens
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.box(Transform3D(b, pos + Vector3(sx * size.x * 0.46, size.y * 0.5,
					sz * size.z * 0.46)), Vector3(0.08, size.y, 0.08),
					m("wood", Color("241a10")))
	mb.box(Transform3D(b, pos + Vector3(0, size.y - 0.06, 0)),
			Vector3(size.x + 0.03, 0.08, size.z + 0.03), m("wood", Color("241a10")))


static func barrel(mb: MeshBuilder, pos: Vector3, yaw_deg := 0.0,
		col := Color("44523a")) -> void:
	mb.cylinder_at(pos + Vector3(0, 0.45, 0), 0.30, 0.90, m("steel_rust", col), 12)
	for y in [0.22, 0.68]:
		mb.cylinder_at(pos + Vector3(0, y, 0), 0.315, 0.06, m("steel_rust"), 12)


static func dumpster(mb: MeshBuilder, pos: Vector3, yaw_deg: float,
		col := Color("2e5a44")) -> void:
	var b := basis_yaw(yaw_deg)
	var body := m("steel_paint", col)
	var metal := m("steel_rust")
	mb.box(Transform3D(b, pos + Vector3(0, 0.72, 0)), Vector3(2.0, 1.05, 3.4), body)
	# lid, slightly open
	mb.box(Transform3D(b * Basis.from_euler(Vector3(deg_to_rad(-14), 0, 0)),
			pos + b * Vector3(0, 1.30, -0.1)), Vector3(1.95, 0.09, 3.3), m("steel_paint", col.darkened(0.25)))
	# ribs and skids
	for i in 4:
		mb.box(Transform3D(b, pos + Vector3(0, 0.72, -1.2 + float(i) * 0.8)),
				Vector3(2.06, 1.0, 0.07), metal)
	for s in [-1.0, 1.0]:
		mb.box(Transform3D(b, pos + Vector3(s * 0.85, 0.14, 0)), Vector3(0.3, 0.28, 3.2), metal)


static func pallet(mb: MeshBuilder, pos: Vector3, yaw_deg := 0.0) -> void:
	var b := basis_yaw(yaw_deg)
	var wood := m("wood_pale")
	for i in 5:
		mb.box(Transform3D(b, pos + Vector3(0, 0.13, -0.5 + float(i) * 0.25)),
				Vector3(1.2, 0.04, 0.14), wood)
	for i in 3:
		mb.box(Transform3D(b, pos + Vector3(-0.5 + float(i) * 0.5, 0.07, 0)),
				Vector3(0.12, 0.08, 1.1), m("wood"))


static func tyre(mb: MeshBuilder, pos: Vector3, yaw_deg := 0.0, scale := 1.0) -> void:
	mb.prism(Transform3D(basis_yaw(yaw_deg) * Basis.from_euler(
			Vector3(deg_to_rad(90), 0, 0)), pos + Vector3(0, 0.18 * scale, 0)),
			0.36 * scale, 0.24 * scale, 14, m("steel_rust", Color("1a1b1d")))


static func traffic_cone(mb: MeshBuilder, pos: Vector3, yaw_deg := 0.0) -> void:
	mb.box_at(pos + Vector3(0, 0.04, 0), Vector3(0.42, 0.08, 0.42), m("steel_rust", Color("b34a28")), Vector3(0, yaw_deg, 0))
	mb.prism(Transform3D(basis_yaw(yaw_deg), pos + Vector3(0, 0.32, 0)), 0.17,
			0.58, 10, m("steel_rust", Color("c2552c")), 0.25)


static func fence(mb: MeshBuilder, pos: Vector3, yaw_deg: float, length: float,
		height := 2.1) -> void:
	var b := basis_yaw(yaw_deg)
	var post := m("steel_rust")
	var n := maxi(2, int(length / 2.6))
	for i in n + 1:
		var px := -length * 0.5 + float(i) * (length / float(n))
		mb.box(Transform3D(b, pos + b * Vector3(px, height * 0.5, 0)),
				Vector3(0.1, height, 0.1), post)
	for k in 3:
		var y := 0.25 + (height - 0.3) * float(k) / 2.0
		mb.box(Transform3D(b, pos + b * Vector3(0, y, 0)), Vector3(length, 0.05, 0.04),
				m("steel_rust", Color("5b4030") if k == 0 else Color("3a3a3a")))
	# mesh panel
	mb.box(Transform3D(b, pos + b * Vector3(0, height * 0.5, 0)),
			Vector3(length, height - 0.1, 0.02), m("steel_rust", Color("4a4a4a")))


static func barrier(mb: MeshBuilder, pos: Vector3, yaw_deg: float) -> void:
	var b := basis_yaw(yaw_deg)
	var metal := m("steel_rust")
	for s in [-1.0, 1.0]:
		mb.box(Transform3D(b, pos + b * Vector3(s * 0.9, 0.5, 0)),
				Vector3(0.12, 1.0, 0.12), metal)
		mb.box(Transform3D(b, pos + b * Vector3(s * 0.9, 0.06, 0)),
				Vector3(0.4, 0.12, 0.5), metal)
	mb.box(Transform3D(b, pos + Vector3(0, 0.95, 0)), Vector3(2.0, 0.16, 0.08),
			m("steel_paint", Color("b8532a")))
	mb.box(Transform3D(b, pos + Vector3(0, 0.50, 0)), Vector3(2.0, 0.09, 0.06), metal)


static func sandbag_wall(mb: MeshBuilder, from: Vector3, to: Vector3, height := 1.0,
		seed := 3) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var d := to - from
	var len := d.length()
	if len < 0.2:
		return
	var dir := d / len
	var yaw := rad_to_deg(atan2(dir.x, dir.z))
	var layers := maxi(1, int(height / 0.34))
	for layer in layers:
		var y := 0.17 + float(layer) * 0.32
		var inset := float(layer) * 0.12
		var n := maxi(1, int((len - inset * 2.0) / 0.62))
		for i in n:
			var t := (float(i) + 0.5) / float(n)
			var p := from.lerp(to, t) + Vector3(0, y, 0)
			p += Vector3(r.randf_range(-0.05, 0.05), r.randf_range(-0.03, 0.03),
					r.randf_range(-0.05, 0.05))
			mb.box_at(p, Vector3(0.62, 0.30, 0.42),
					m("canvas", Color("6b6350"), 0.8),
					Vector3(0, yaw + r.randf_range(-7, 7), 0))


# ==================================================================== RUBBLE

## Scattered slabs, brick chunks and rebar.
static func rubble(mb: MeshBuilder, centre: Vector3, extents: Vector3, count := 40,
		seed := 5, scale := 1.0) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var concrete := m("concrete_dark")
	var brick := m("brick")
	var rod := m("steel_rust")
	for i in count:
		var kind := r.randf()
		var p := centre + Vector3(r.randf_range(-extents.x, extents.x),
				r.randf_range(-0.05, extents.y * 0.6),
				r.randf_range(-extents.z, extents.z))
		var yaw := r.randf_range(0, 360)
		if kind < 0.45:
			var s := Vector3(r.randf_range(0.3, 1.2), r.randf_range(0.18, 0.5),
					r.randf_range(0.3, 1.2)) * scale
			mb.box_at(p + Vector3(0, s.y * 0.5, 0), s, concrete,
					Vector3(r.randf_range(-14, 14), yaw, r.randf_range(-10, 10)))
		elif kind < 0.72:
			var s := Vector3(r.randf_range(0.2, 0.5), r.randf_range(0.1, 0.24),
					r.randf_range(0.2, 0.5)) * scale
			mb.box_at(p + Vector3(0, s.y * 0.5, 0), s, brick,
					Vector3(r.randf_range(-20, 20), yaw, r.randf_range(-20, 20)))
		elif kind < 0.86:
			mb.cylinder_at(p + Vector3(0, r.randf_range(0.1, 0.3) * scale, 0),
					0.025 * scale, r.randf_range(0.8, 2.4) * scale, rod, 5,
					Vector3(r.randf_range(60, 110), yaw, r.randf_range(-30, 30)))
		else:
			var s := Vector3(r.randf_range(0.5, 1.8), r.randf_range(0.3, 0.8),
					r.randf_range(0.5, 1.8)) * scale
			mb.box_at(p + Vector3(0, s.y * 0.5, 0), s, concrete,
					Vector3(r.randf_range(-6, 6), yaw, r.randf_range(-6, 6)))


## A heap with structure: big slabs at the bottom, fines on top.
static func debris_pile(mb: MeshBuilder, centre: Vector3, radius := 3.0, seed := 7) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	for i in 26:
		var a := r.randf_range(0, TAU)
		var rr := sqrt(r.randf()) * radius
		var p := centre + Vector3(cos(a) * rr, 0, sin(a) * rr)
		var h := (1.0 - rr / radius) * radius * 0.55
		mb.box_at(p + Vector3(0, r.randf_range(0.1, maxf(0.2, h)), 0),
				Vector3(r.randf_range(0.6, 1.9), r.randf_range(0.3, 0.8),
						r.randf_range(0.6, 1.9)), m("concrete_dark"),
				Vector3(r.randf_range(-12, 12), r.randf_range(0, 360), r.randf_range(-12, 12)))
	for i in 40:
		var a := r.randf_range(0, TAU)
		var rr := sqrt(r.randf()) * radius
		var p := centre + Vector3(cos(a) * rr, 0, sin(a) * rr)
		mb.box_at(p + Vector3(0, 0.12, 0), Vector3(r.randf_range(0.2, 0.5), 0.2,
				r.randf_range(0.2, 0.5)), m("brick"), Vector3(0, r.randf_range(0, 360), 0))


# ================================================================ OVERGROWTH

static func tree(mb: MeshBuilder, pos: Vector3, seed := 1, scale := 1.0,
		leaf := Color("2c4a1e")) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var bark := m("wood", Color("3a2f22"))
	var h := r.randf_range(3.4, 6.6) * scale
	mb.cylinder_at(pos + Vector3(0, h * 0.5, 0), 0.20 * scale, h, bark, 9, Vector3.ZERO)
	# limbs
	var branches := r.randi_range(3, 5)
	for i in branches:
		var a := TAU * float(i) / float(branches) + r.randf_range(-0.4, 0.4)
		var up := r.randf_range(0.52, 0.78)
		var bl := r.randf_range(1.6, 2.8) * scale
		var start := pos + Vector3(0, h * r.randf_range(0.62, 0.86), 0)
		var dir := Vector3(cos(a), up, sin(a)).normalized()
		var mid := start + dir * bl * 0.5
		mb.cylinder_at(mid, 0.09 * scale, bl, bark, 7,
				Vector3(rad_to_deg(asin(clampf(dir.y, -1, 1))) - 90, rad_to_deg(atan2(dir.x, dir.z)), 0))
		var tip := start + dir * bl
		for k in r.randi_range(2, 4):
			var off := Vector3(r.randf_range(-1.1, 1.1), r.randf_range(-0.3, 0.7),
					r.randf_range(-1.1, 1.1)) * scale
			mb.box_at(tip + off + Vector3(0, 0.3, 0),
					Vector3(r.randf_range(1.4, 2.6), r.randf_range(1.1, 1.9),
							r.randf_range(1.4, 2.6)),
					m("canvas", leaf, 1.6),
					Vector3(r.randf_range(-20, 20), r.randf_range(0, 360), r.randf_range(-20, 20)))


static func bush(mb: MeshBuilder, pos: Vector3, seed := 1, scale := 1.0,
		col := Color("2f4a22")) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	for i in r.randi_range(3, 6):
		var p := pos + Vector3(r.randf_range(-0.7, 0.7), r.randf_range(0.2, 0.7),
				r.randf_range(-0.7, 0.7)) * scale
		mb.box_at(p, Vector3(r.randf_range(0.7, 1.3), r.randf_range(0.5, 1.0),
				r.randf_range(0.7, 1.3)) * scale, m("canvas", col, 1.4),
				Vector3(r.randf_range(-20, 20), r.randf_range(0, 360), r.randf_range(-20, 20)))


static func rock(mb: MeshBuilder, pos: Vector3, seed := 1, scale := 1.0) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	mb.box_at(pos + Vector3(0, 0.35 * scale, 0),
			Vector3(r.randf_range(0.8, 2.2), r.randf_range(0.5, 1.4),
					r.randf_range(0.8, 2.2)) * scale, m("rock"),
			Vector3(r.randf_range(-16, 16), r.randf_range(0, 360), r.randf_range(-16, 16)))


# ================================================================ ATTACHMENTS

static func wires(mb: MeshBuilder, from: Vector3, to: Vector3, sag := 0.6,
		segments := 6, radius := 0.035) -> void:
	var prev := from
	for i in range(1, segments + 1):
		var t := float(i) / float(segments)
		var p := from.lerp(to, t)
		p.y -= sin(t * PI) * sag
		mb.pipe(prev, p, radius, m("steel_rust", Color("1c1c1e")), 5)
		prev = p


static func laundry(mb: MeshBuilder, from: Vector3, to: Vector3, seed := 1) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	mb.pipe(from, to, 0.02, m("steel_rust", Color("2a2620")), 4)
	var cols := [Color("c8c0ac"), Color("8a6f5a"), Color("556472"), Color("a3554a")]
	for i in r.randi_range(3, 6):
		var t := r.randf_range(0.12, 0.88)
		var p := from.lerp(to, t) + Vector3(0, -0.35, 0)
		mb.box_at(p, Vector3(r.randf_range(0.4, 0.75), 0.7, 0.05),
				m("canvas", _pick(r, cols), 0.9), Vector3(0, 90, r.randf_range(-6, 6)))


## A shop awning.  It has to *slope*: a horizontal panel at head height faces
## straight up, catches the whole sky and reads as a glowing white slab
## floating over the street.
static func awning(mb: MeshBuilder, b: Basis, pos: Vector3, heading: Vector3,
		width: float, depth := 2.4, col := Color("7a3a2e")) -> void:
	var along := heading.cross(Vector3.UP).normalized()
	var canvas := m("canvas", col, 1.0)
	var drop := 0.62
	var slope := (heading * depth - Vector3.UP * drop).normalized()
	var run := sqrt(depth * depth + drop * drop)
	var inner := pos + heading * 0.05 - along * (width * 0.5)
	var top_n := along.cross(slope).normalized()
	# top skin, underside, and the two side gussets
	mb.quad(inner, along, slope, Vector2(width, run), canvas, 1.0)
	mb.quad(inner - top_n * 0.07, -along, slope, Vector2(width, run), canvas, 1.0)
	for side in [-1.0, 1.0]:
		var s := float(side)
		var corner := inner + along * (width * 0.5 * s)
		mb.tri2(corner, corner + slope * run, corner - top_n * 0.07, canvas)
		mb.tri2(corner + slope * run, corner + slope * run - top_n * 0.07,
				corner - top_n * 0.07, canvas)
	# valance and stays
	var edge: Vector3 = pos + heading * depth - Vector3.UP * drop
	mb.box_basis(b, edge - Vector3.UP * 0.16, Vector3(width, 0.34, 0.12),
			m("canvas", col.darkened(0.25), 0.8))
	for side in [-1.0, 1.0]:
		var s := float(side)
		mb.pipe(pos + along * (s * width * 0.5) + Vector3(0, 0.62, 0),
				edge + along * (s * width * 0.5), 0.05, m("steel_rust"), 6)


static func scaffold(mb: MeshBuilder, b: Basis, origin: Vector3, heading: Vector3,
		width: float, height: float, levels := 4) -> void:
	var along := heading.cross(Vector3.UP).normalized()
	var metal := m("steel_rust", Color("8a7a5a"))
	for side in [-1.0, 1.0]:
		var s := float(side)
		for i in levels + 1:
			var p: Vector3 = origin + along * (s * width * 0.5) + heading * 0.7 \
					+ Vector3(0, float(i) * (height / float(levels)), 0)
			mb.cylinder_at(p, 0.055, height / float(levels), metal, 6)
	for i in levels:
		var y := float(i) * (height / float(levels)) + height / float(levels)
		mb.box(Transform3D(b, origin + heading * 0.7 + Vector3(0, y, 0)),
				Vector3(width, 0.07, 1.1), m("wood_pale"))
		for k in int(width / 0.9):
			mb.box(Transform3D(b, origin + heading * 0.7
					+ along * (-width * 0.5 + (float(k) + 0.5) * 0.9)
					+ Vector3(0, y + 0.06, 0)), Vector3(0.9, 0.05, 1.1), m("wood_pale"))
		mb.box(Transform3D(b, origin + heading * 1.2 + Vector3(0, y + 0.5, 0)),
				Vector3(width, 0.06, 0.06), metal)


# ================================================================== INTERIORS

## A plastered interior wall: skirting, a dado rail, panelling, and optionally a
## window opening or a doorway.  `openings` is a list of
## {x, y, w, h, kind} in wall-local metres, kind being "window" or "door".
static func interior_wall(mb: MeshBuilder, b: Basis, origin: Vector3,
		heading: Vector3, w: float, h: float, opts := {}) -> void:
	var t := float(opts.get("thickness", 0.30))
	var along := heading.cross(Vector3.UP).normalized()
	var plaster_m: Material = opts.get("wall", m("plaster", Color("6a5a48")))
	var dado_m: Material = opts.get("dado", m("wood", Color("4a3524")))
	var openings: Array = opts.get("openings", [])

	# slab, then carve by placing the solid bands around each opening
	mb.box_basis(b, origin + Vector3(0, h * 0.5, 0), Vector3(w, h, t), plaster_m)
	for o in openings:
		var ox := float(o.get("x", 0.0))
		var oy := float(o.get("y", 1.0))
		var ow := float(o.get("w", 1.0))
		var oh := float(o.get("h", 1.4))
		var kind := String(o.get("kind", "window"))
		# Void *outside* the opening.  `heading` points out of the room, so the
		# dark card belongs on the +heading side -- put it on the other side and
		# a slab of blackness juts into the middle of the room.
		mb.box_basis(b, origin + along * ox + heading * 0.72
				+ Vector3(0, oy + oh * 0.5, 0), Vector3(ow + 0.3, oh + 0.3, 1.4),
				interior(0.035 if kind == "window" else 0.02))
		# jamb linings
		for side in [-1.0, 1.0]:
			mb.box_basis(b, origin + along * (ox + float(side) * (ow * 0.5 + 0.07))
					+ Vector3(0, oy + oh * 0.5, 0), Vector3(0.14, oh + 0.24, t + 0.08),
					dado_m)
		mb.box_basis(b, origin + along * ox + Vector3(0, oy - 0.07, 0),
				Vector3(ow + 0.28, 0.14, t + 0.08), dado_m)
		mb.box_basis(b, origin + along * ox + Vector3(0, oy + oh + 0.07, 0),
				Vector3(ow + 0.28, 0.14, t + 0.08), dado_m)

	# skirting and dado rail
	mb.box_basis(b, origin + Vector3(0, 0.11, 0), Vector3(w, 0.22, t + 0.06), dado_m)
	mb.box_basis(b, origin + Vector3(0, 1.02, 0), Vector3(w, 0.08, t + 0.05), dado_m)
	if bool(opts.get("panels", true)):
		var n := maxi(2, int(w / 1.5))
		for i in n:
			var px := -w * 0.5 + (float(i) + 0.5) * (w / float(n))
			mb.box_basis(b, origin + along * px + Vector3(0, 0.58, 0),
					Vector3(w / float(n) - 0.28, 0.72, t + 0.04),
					m("wood", Color("543d29")))
	# ceiling trim
	mb.box_basis(b, origin + Vector3(0, h - 0.16, 0), Vector3(w, 0.22, t + 0.08), dado_m)

	# Colliders, built as the wall *minus* its openings so a doorway is passable.
	var cuts: Array = []
	for o in openings:
		cuts.append({"x": float(o.get("x", 0.0)), "w": float(o.get("w", 1.0)),
				"y": float(o.get("y", 0.0)), "h": float(o.get("h", 1.4))})
	cuts.sort_custom(func(a, c): return float(a["x"]) < float(c["x"]))
	var cursor := -w * 0.5
	for c in cuts:
		var x0: float = float(c["x"]) - float(c["w"]) * 0.5
		var x1: float = float(c["x"]) + float(c["w"]) * 0.5
		if x0 > cursor:
			_wall_collide(mb, b, origin, along, heading, cursor, x0, 0.0, h, t)
		_wall_collide(mb, b, origin, along, heading, x0, x1, 0.0, float(c["y"]), t)
		_wall_collide(mb, b, origin, along, heading, x0, x1,
				float(c["y"]) + float(c["h"]), h, t)
		cursor = maxf(cursor, x1)
	if cursor < w * 0.5:
		_wall_collide(mb, b, origin, along, heading, cursor, w * 0.5, 0.0, h, t)


static func _wall_collide(mb: MeshBuilder, b: Basis, origin: Vector3, along: Vector3,
		heading: Vector3, x0: float, x1: float, y0: float, y1: float, t: float) -> void:
	if x1 - x0 < 0.02 or y1 - y0 < 0.02:
		return
	var mid := origin + along * ((x0 + x1) * 0.5) + Vector3(0, (y0 + y1) * 0.5, 0)
	var ext := Vector3(absf(x1 - x0), y1 - y0, t)
	var use_x := absf(along.dot(b.x)) > 0.5
	if not use_x:
		ext = Vector3(t, y1 - y0, absf(x1 - x0))
	mb.collide(Transform3D(b, mid), ext)


## Four interior walls with a doorway and a window run.
static func room(mb: MeshBuilder, centre: Vector3, size: Vector3, opts := {}) -> void:
	var b := Basis.IDENTITY
	var w := size.x
	var d := size.z
	var h := size.y
	var wall: Material = opts.get("wall", m("plaster", Color("6a5a48")))
	var floor_mat: Material = opts.get("floor", m("wood", Color("3a2c1c")))
	mb.box_basis(b, centre + Vector3(0, -0.18, 0), Vector3(w, 0.36, d), floor_mat)
	mb.box_basis(b, centre + Vector3(0, h + 0.2, 0), Vector3(w + 0.7, 0.4, d + 0.7),
			m("wood", Color("2a1e14")))
	# side index: 0 = +Z, 1 = -Z, 2 = +X, 3 = -X.  Openings name their wall by
	# that index so a window on one wall never appears on the one opposite.
	var sides := [
		{"nrm": Vector3(0, 0, 1), "off": Vector3(0, 0, d * 0.5), "len": w},
		{"nrm": Vector3(0, 0, -1), "off": Vector3(0, 0, -d * 0.5), "len": w},
		{"nrm": Vector3(1, 0, 0), "off": Vector3(w * 0.5, 0, 0), "len": d},
		{"nrm": Vector3(-1, 0, 0), "off": Vector3(-w * 0.5, 0, 0), "len": d},
	]
	var openings: Array = opts.get("openings", [])
	for idx in sides.size():
		var s: Dictionary = sides[idx]
		var mine: Array = []
		for o in openings:
			if int(o.get("side", 0)) == idx:
				mine.append(o)
		interior_wall(mb, b, centre + (s["off"] as Vector3), s["nrm"], float(s["len"]),
				h, {"thickness": 0.3, "wall": wall, "openings": mine,
				"panels": bool(opts.get("panels", true))})


static func stairs(mb: MeshBuilder, b: Basis, origin: Vector3, heading: Vector3,
		width: float, rise: float, run: float, steps: int) -> void:
	var along := heading.cross(Vector3.UP).normalized()
	var wood := m("wood", Color("4a3524"))
	for i in steps:
		var y := float(i) * rise
		var z := float(i) * run
		mb.box_basis(b, origin + heading * z + Vector3(0, y + rise * 0.5, 0),
				Vector3(width, rise, run * 1.02), wood)
		if i == 0:
			mb.box_basis(b, origin + heading * (-0.4) + Vector3(0, rise * 0.5, 0),
					Vector3(width, rise, 0.8), wood)
	# stringers and balusters
	for side in [-1.0, 1.0]:
		var s := float(side)
		mb.box_basis(b, origin + heading * (run * float(steps) * 0.5)
				+ along * (s * (width * 0.5 + 0.05))
				+ Vector3(0, rise * float(steps) * 0.5 - 0.2, 0),
				Vector3(0.09, 1.1, run * float(steps)), m("wood", Color("2e2113")))


static func door_frame(mb: MeshBuilder, b: Basis, origin: Vector3, heading: Vector3,
		w := 1.1, h := 2.2, open := false, col := Color("3a2a1c")) -> void:
	var wood := m("wood", col)
	mb.box_basis(b, origin + Vector3(0, h - 0.06, 0), Vector3(w + 0.36, 0.20, 0.46), wood)
	for side in [-1.0, 1.0]:
		mb.box_basis(b, origin + heading.cross(Vector3.UP).normalized()
				* (float(side) * (w * 0.5 + 0.08)) + Vector3(0, h * 0.5, 0),
				Vector3(0.16, h, 0.46), wood)
	if open:
		mb.box_basis(b * Basis.from_euler(Vector3(0, deg_to_rad(78), 0)),
				origin + heading * 0.12 + Vector3(0, h * 0.5 - 0.02, 0),
				Vector3(w - 0.04, h - 0.06, 0.08), wood)
	else:
		mb.box_basis(b, origin + heading * 0.14 + Vector3(0, h * 0.5 - 0.02, 0),
				Vector3(w - 0.04, h - 0.06, 0.09), wood)
		mb.box_basis(b, origin + heading * 0.20 + Vector3(0, 1.05, 0.0),
				Vector3(0.09, 0.09, 0.22), m("steel_rust", Color("7a6a4a")))


# --- furniture ---------------------------------------------------------------

static func table(mb: MeshBuilder, pos: Vector3, yaw_deg := 0.0, seed := 1,
		waist := 0.78) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var b := basis_yaw(yaw_deg)
	var top := m("wood", Color("4a3626"))
	var w := r.randf_range(1.1, 1.5)
	var d := r.randf_range(0.8, 1.1)
	mb.box(Transform3D(b, pos + Vector3(0, waist, 0)), Vector3(w, 0.08, d), top)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.box(Transform3D(b, pos + b * Vector3(sx * (w * 0.5 - 0.12),
					waist * 0.5, sz * (d * 0.5 - 0.12))),
					Vector3(0.09, waist, 0.09), m("wood", Color("2e2113")))
	# clutter on the table: a candle, a mug or two, a plate
	if r.randf() < 0.7:
		mb.cylinder_at(pos + b * Vector3(w * 0.18, waist + 0.14, d * 0.14), 0.035, 0.2,
				m("canvas", Color("d8cfae"), 0.5), 8)
		mb.prism(Transform3D(b, pos + b * Vector3(w * 0.18, waist + 0.28, d * 0.14)),
				0.03, 0.05, 6, emissive(Color("ffb060"), 2.0))
	for i in r.randi_range(1, 3):
		mb.cylinder_at(pos + b * Vector3(r.randf_range(-w * 0.3, w * 0.3), waist + 0.09,
				r.randf_range(-d * 0.3, d * 0.3)), 0.055, 0.11,
				m("canvas", Color("9a8a6a"), 0.4), 8)
	if r.randf() < 0.45:
		mb.prism(Transform3D(b, pos + b * Vector3(r.randf_range(-w * 0.3, w * 0.3),
				waist + 0.03, r.randf_range(-d * 0.3, d * 0.3))),
				0.14, 0.02, 12, m("wood_pale"))


static func chair(mb: MeshBuilder, pos: Vector3, yaw_deg := 0.0, toppled := false) -> void:
	var b := basis_yaw(yaw_deg)
	if toppled:
		b = b * Basis.from_euler(Vector3(deg_to_rad(84), 0, 0))
	var wood := m("wood", Color("3e2d1d"))
	mb.box(Transform3D(b, pos + b * Vector3(0, 0.45, 0)), Vector3(0.46, 0.06, 0.46), wood)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.box(Transform3D(b, pos + b * Vector3(sx * 0.19, 0.22, sz * 0.19)),
					Vector3(0.05, 0.45, 0.05), wood)
	for sx in [-1.0, 1.0]:
		mb.box(Transform3D(b, pos + b * Vector3(sx * 0.19, 0.72, -0.20)),
				Vector3(0.05, 0.55, 0.05), wood)
	for i in 2:
		mb.box(Transform3D(b, pos + b * Vector3(0, 0.62 + float(i) * 0.22, -0.20)),
				Vector3(0.42, 0.07, 0.05), wood)


static func stool(mb: MeshBuilder, pos: Vector3, yaw_deg := 0.0) -> void:
	var b := basis_yaw(yaw_deg)
	var wood := m("wood", Color("4a3524"))
	mb.cylinder_at(pos + Vector3(0, 0.72, 0), 0.20, 0.07, wood, 12)
	for i in 3:
		var a := TAU * float(i) / 3.0
		mb.box(Transform3D(b, pos + Vector3(cos(a) * 0.14, 0.36, sin(a) * 0.14)),
				Vector3(0.05, 0.72, 0.05), wood)
	mb.prism(Transform3D(b, pos + Vector3(0, 0.2, 0)), 0.16, 0.04, 10, wood)


## The bar: a long counter with a foot rail, a top, and a back shelf of bottles.
static func bar_counter(mb: MeshBuilder, b: Basis, origin: Vector3, heading: Vector3,
		length: float, seed := 1) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var along := heading.cross(Vector3.UP).normalized()
	var top := m("wood", Color("3a2718"))
	var front := m("wood", Color("4d3521"))
	mb.box(Transform3D(b, origin + Vector3(0, 1.10, 0)), Vector3(length, 0.10, 0.72), top)
	mb.box(Transform3D(b, origin + Vector3(0, 0.60, 0.02)), Vector3(length, 1.0, 0.62), front)
	mb.box(Transform3D(b, origin + Vector3(0, 0.06, 0.02)), Vector3(length, 0.12, 0.7),
			m("wood", Color("241809")))
	# foot rail and a brass top strip
	mb.pipe(origin + along * (length * 0.5) + heading * 0.44 + Vector3(0, 0.22, 0),
			origin - along * (length * 0.5) + heading * 0.44 + Vector3(0, 0.22, 0),
			0.035, m("steel_rust", Color("8a6a3a")), 6)
	mb.box(Transform3D(b, origin + Vector3(0, 1.16, 0)), Vector3(length, 0.03, 0.74),
			m("steel_rust", Color("7a6238")))
	# stools and glasses along the bar
	var n := maxi(1, int(length / 1.1))
	for i in n:
		var px := -length * 0.5 + (float(i) + 0.5) * (length / float(n))
		if r.randf() < 0.55:
			stool(mb, origin + along * px + heading * 0.75, rad_to_deg(r.randf()))
		if r.randf() < 0.6:
			mb.cylinder_at(origin + along * px + heading * 0.10 + Vector3(0, 1.24, 0),
					0.042, 0.14, m("canvas", Color("b8c4c0"), 0.3), 8)


static func back_bar(mb: MeshBuilder, b: Basis, origin: Vector3, heading: Vector3,
		length: float, height := 2.6, seed := 1) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var along := heading.cross(Vector3.UP).normalized()
	var wood := m("wood", Color("33230f"))
	mb.box(Transform3D(b, origin + Vector3(0, height * 0.5, 0)), Vector3(length, height, 0.5), wood)
	var shelves := maxi(2, int(height / 0.62))
	var tints := [Color("4a6a3a"), Color("6a3a2a"), Color("7a6a2a"), Color("3a4a6a")]
	for s in shelves:
		var y := 0.35 + float(s) * (height - 0.5) / float(shelves)
		mb.box(Transform3D(b, origin + heading * 0.30 + Vector3(0, y, 0)),
				Vector3(length, 0.05, 0.34), wood)
		var nb := int(length / 0.22)
		for i in nb:
			if r.randf() < 0.34:
				continue
			var px := -length * 0.5 + (float(i) + 0.5) * (length / float(nb))
			var h := r.randf_range(0.20, 0.34)
			mb.cylinder_at(origin + heading * 0.32 + along * px + Vector3(0, y + h * 0.5 + 0.03, 0),
					0.042, h, m("canvas", _pick(r, tints), 0.3), 7)
			mb.cylinder_at(origin + heading * 0.32 + along * px
					+ Vector3(0, y + h + 0.06, 0), 0.016, 0.09,
					m("canvas", _pick(r, tints), 0.3), 6)


static func shelf_unit(mb: MeshBuilder, b: Basis, origin: Vector3, heading: Vector3,
		width: float, height := 2.2, seed := 1) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var wood := m("wood", Color("40301c"))
	mb.box(Transform3D(b, origin + Vector3(0, height * 0.5, 0)), Vector3(width, height, 0.42), wood)
	var levels := maxi(2, int(height / 0.48))
	for s in levels:
		var y := 0.22 + float(s) * (height - 0.3) / float(levels)
		mb.box(Transform3D(b, origin + heading * 0.18 + Vector3(0, y, 0)),
				Vector3(width - 0.1, 0.04, 0.32), m("wood_pale"))
		var nb := int(width / 0.09)
		for i in nb:
			if r.randf() < 0.22:
				continue
			var px := -width * 0.5 + 0.06 + float(i) * 0.09
			var bh := r.randf_range(0.22, 0.32)
			var lean := r.randf_range(-0.12, 0.12)
			mb.box_basis(b * Basis.from_euler(Vector3(0, 0, lean)),
					origin + heading * 0.20 + b.x * px + Vector3(0, y + bh * 0.5 + 0.04, 0),
					Vector3(0.045, bh, 0.19),
					m("canvas", _pick(r, [Color("7a4a3a"), Color("3a5a4a"),
							Color("5a5a7a"), Color("7a6a4a")]), 0.3))


static func locker_bank(mb: MeshBuilder, b: Basis, origin: Vector3, heading: Vector3,
		count := 6, height := 1.95, seed := 1) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var along := heading.cross(Vector3.UP).normalized()
	var metal := m("steel_paint", Color("3a4a44"))
	var dark := m("steel_paint", Color("2a3630"))
	var w := 0.42
	mb.box(Transform3D(b, origin + Vector3(0, height * 0.5, 0)),
			Vector3(float(count) * w, height, 0.5), dark)
	for i in count:
		var px := -float(count) * w * 0.5 + (float(i) + 0.5) * w
		var open := r.randf() < 0.24
		if open:
			mb.box_basis(b * Basis.from_euler(Vector3(0, deg_to_rad(76), 0)),
					origin + heading * 0.30 + along * px + Vector3(0, height * 0.5 + (height - 0.14) * 0.5, 0),
					Vector3(w - 0.04, height - 0.14, 0.05), metal)
		else:
			mb.box(Transform3D(b, origin + heading * 0.27 + along * px
					+ Vector3(0, height * 0.5 + 0.05, 0)),
					Vector3(w - 0.04, height - 0.14, 0.05), metal)
			for k in 3:
				mb.box(Transform3D(b, origin + heading * 0.30 + along * px
						+ Vector3(0, 0.55 + float(k) * 0.5, 0)), Vector3(w - 0.12, 0.05, 0.02),
						m("steel_rust"))
		mb.box(Transform3D(b, origin + heading * 0.32 + along * px
				+ Vector3(0, height * 0.78, 0)), Vector3(0.10, 0.10, 0.03),
				m("steel_rust", Color("9a8a5a")))


static func fireplace(mb: MeshBuilder, b: Basis, origin: Vector3, heading: Vector3,
		width := 2.4) -> void:
	var stone := m("rock", Color("5a5550"), 1.4)
	var along := heading.cross(Vector3.UP).normalized()
	mb.box(Transform3D(b, origin + Vector3(0, 1.5, 0)), Vector3(width + 0.9, 3.0, 0.9), stone)
	mb.box(Transform3D(b, origin + heading * 0.5 + Vector3(0, 1.0, 0)),
			Vector3(width, 1.9, 0.5), interior(0.02))
	mb.box(Transform3D(b, origin + heading * 0.28 + Vector3(0, 0.06, 0)),
			Vector3(width - 0.1, 0.12, 0.9), stone)
	mb.box(Transform3D(b, origin + heading * 0.46 + Vector3(0, 2.06, 0)),
			Vector3(width + 0.7, 0.24, 0.6), m("wood", Color("3a2a1c")))
	mb.box(Transform3D(b, origin + heading * 0.30 + Vector3(0, 0.34, 0)),
			Vector3(width - 0.2, 0.5, 0.4), m("brick", Color("2a1c16"), 0.7))
	# a log basket beside it
	mb.box(Transform3D(b, origin + along * (width * 0.5 + 0.7) + Vector3(0, 0.24, 0)),
			Vector3(0.6, 0.48, 0.5), m("wood", Color("392a18")))
	for i in 5:
		mb.cylinder_at(origin + along * (width * 0.5 + 0.7) + Vector3(0, 0.5, 0),
				0.08, 0.9, m("wood", Color("4a3626")), 6,
				Vector3(90, float(i) * 72.0, 0))


static func rug(mb: MeshBuilder, pos: Vector3, size: Vector2, col := Color("5a2f28"),
		yaw_deg := 0.0) -> void:
	var b := basis_yaw(yaw_deg)
	mb.box(Transform3D(b, pos + Vector3(0, 0.012, 0)),
			Vector3(size.x, 0.024, size.y), m("canvas", col, 1.6))
	mb.box(Transform3D(b, pos + Vector3(0, 0.026, 0)),
			Vector3(size.x - 0.34, 0.01, size.y - 0.34), m("canvas", col.darkened(0.28), 1.6))


static func painting(mb: MeshBuilder, b: Basis, pos: Vector3, heading: Vector3,
		w := 1.0, h := 1.4, seed := 1) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var frame := m("wood", Color("6a5230"))
	var img := m("canvas", _pick(r, [Color("4a5a4a"), Color("5a4a3a"),
			Color("3a4450"), Color("6a5540")]), 0.8)
	mb.box(Transform3D(b, pos), Vector3(w, h, 0.07), frame)
	mb.box(Transform3D(b, pos + heading * 0.05), Vector3(w - 0.16, h - 0.16, 0.03), img)


## Pendant lamp: cord, shade, bulb.  Returns the shade position so the caller can
## hang a real light there.
static func hanging_lamp(mb: MeshBuilder, pos: Vector3, col := Color("ffc074"),
		shade := Color("2e4a40")) -> Vector3:
	mb.pipe(pos, pos + Vector3(0, 0.9, 0), 0.012, m("steel_rust", Color("1a1a1a")), 4)
	mb.prism(Transform3D(Basis.from_euler(Vector3(PI, 0, 0)), pos + Vector3(0, 0.06, 0)),
			0.26, 0.22, 14, m("steel_paint", shade), 0.35)
	mb.prism(Transform3D(Basis.IDENTITY, pos + Vector3(0, -0.10, 0)), 0.05, 0.09, 8,
			emissive(col, 3.0))
	return pos + Vector3(0, -0.16, 0)


static func caged_lamp(mb: MeshBuilder, b: Basis, pos: Vector3, heading: Vector3) -> Vector3:
	var metal := m("steel_rust", Color("3a3a3a"))
	mb.box(Transform3D(b, pos), Vector3(0.34, 0.14, 0.26), metal)
	mb.box(Transform3D(b, pos + heading * 0.16), Vector3(0.26, 0.10, 0.05), metal)
	mb.box(Transform3D(b, pos + heading * 0.24), Vector3(0.22, 0.09, 0.03),
			emissive(Color("ffe0b0"), 2.4))
	return pos + heading * 0.4


## Exposed services running along a corridor ceiling.
static func pipe_run(mb: MeshBuilder, from: Vector3, to: Vector3, y: float,
		count := 3, radius := 0.10, seed := 1) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var tints := [Color("5a5a5e"), Color("6a4a3a"), Color("4a5a4a")]
	var along := (to - from)
	var perp := Vector3(along.z, 0, -along.x).normalized()
	for i in count:
		var off := perp * ((float(i) - float(count - 1) * 0.5) * 0.34)
		mb.pipe(from + off + Vector3(0, y, 0), to + off + Vector3(0, y, 0),
				radius * (0.7 + 0.5 * float(i % 2)),
				m("steel_paint", _pick(r, tints)), 8)
		var n := maxi(1, int(along.length() / 2.2))
		for k in n:
			var p := (from + off).lerp(to + off, (float(k) + 0.5) / float(n))
			mb.box_at(p + Vector3(0, y + 0.22, 0), Vector3(0.06, 0.44, 0.06), m("steel_rust"))


# --- outdoor nature ---------------------------------------------------------

static func flowers(mb: MeshBuilder, centre: Vector3, extents: Vector3, count := 120,
		seed := 1) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var tints := [Color("e8d05a"), Color("e06a7a"), Color("d8d8e8"), Color("c88ad0"),
			Color("f0a050")]
	for i in count:
		var p := centre + Vector3(r.randf_range(-extents.x, extents.x), 0,
				r.randf_range(-extents.z, extents.z))
		var h := r.randf_range(0.22, 0.46)
		mb.box_at(p + Vector3(0, h * 0.5, 0), Vector3(0.02, h, 0.02),
				m("grass", Color(0.35, 0.45, 0.18), 0.5))
		mb.box_at(p + Vector3(0, h + 0.03, 0), Vector3(0.09, 0.07, 0.09),
				m("canvas", _pick(r, tints), 0.4),
				Vector3(r.randf_range(-20, 20), r.randf_range(0, 360), r.randf_range(-20, 20)))


static func tuft(mb: MeshBuilder, pos: Vector3, seed := 1, scale := 1.0) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	for i in r.randi_range(3, 7):
		var a := r.randf_range(0, TAU)
		var h := r.randf_range(0.25, 0.6) * scale
		mb.box_at(pos + Vector3(cos(a) * 0.12 * scale, h * 0.5, sin(a) * 0.12 * scale),
				Vector3(0.04 * scale, h, 0.04 * scale),
				m("grass", Color(0.30, 0.42, 0.16), 0.4),
				Vector3(r.randf_range(-24, 24), r.randf_range(0, 360), r.randf_range(-24, 24)))


static func wood_fence(mb: MeshBuilder, from: Vector3, to: Vector3, height := 1.2,
		seed := 1) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var d := to - from
	var len := d.length()
	if len < 0.3:
		return
	var yaw := rad_to_deg(atan2(d.x, d.z))
	var wood := m("wood", Color("5a4632"))
	var n := maxi(2, int(len / 0.42))
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var p := from.lerp(to, t)
		var h := height * r.randf_range(0.88, 1.08)
		mb.box_at(p + Vector3(0, h * 0.5, 0), Vector3(0.05, h, 0.09), wood,
				Vector3(0, yaw, r.randf_range(-3, 3)))
	for k in 2:
		var y := height * (0.32 + 0.44 * float(k))
		mb.box_at((from + to) * 0.5 + Vector3(0, y, 0),
				Vector3(0.05, 0.09, len), wood, Vector3(0, yaw, 0))
