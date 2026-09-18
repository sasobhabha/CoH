class_name HumanoidRig
extends Node3D
## Skinned character rig driven by the Blender-authored GLB.
##
## The public surface is deliberately the same as the primitive rig this
## replaces, so Player, Enemy and Talker keep calling `build`, `update`,
## `flash`, `die` and `reset` unchanged.  What changed underneath is that the
## character is now a real skinned mesh with baked animation clips instead of a
## tree of boxes posed by hand.
##
## Clip playback is a small state machine: locomotion picks a clip from the
## movement the game already reports, and one-shots (fire, reload, melee, hit,
## death) are requested explicitly and hold until they finish.
##
## The held weapon hangs off the skeleton's `weapon` bone rather than the right
## hand.  The bone lives in chest space, which is what lets both arms stay on
## the rifle across every clip and lets recoil be absorbed by the arms.

const MODELS := {
	"player": "res://assets/characters/player.glb",
	"trooper": "res://assets/characters/trooper.glb",
	"heavy": "res://assets/characters/heavy.glb",
	"guard": "res://assets/characters/guard.glb",
	"civilian": "res://assets/characters/civilian.glb",
}

## Height of the baseline build, in metres, as measured off the trooper mesh.
## Every clip was authored against this body, so the ratio of a mesh's height to
## this one is the archetype's stature.
const BASE_HEIGHT := 1.857

## Metres per second each locomotion clip was authored for, measured from its
## frame count, foot stride and 24 fps bake.  Playback is scaled by the actual
## speed so the feet do not skate.
const NOMINAL := {
	"walk": 0.90,
	"run": 1.83,
	"crouch_walk": 0.40,
}

## The rifle is modelled with its muzzle 0.60 m ahead of the grip, in rifle
## space (-Z is the barrel).
const RIFLE_MUZZLE := Vector3(0.0, 0.012, -0.60)
## Rotating the mount +90 deg about X maps the bone's forward (+Y, the barrel
## direction authored in Blender) onto the rifle's -Z.
const MOUNT_ROTATION := Vector3(90.0, 0.0, 0.0)

var palette := {}
var bulk := 1.0
## Which GLB this rig loaded, e.g. "heavy".
var model_key := ""
## How tall this archetype is relative to the baseline build.  Measured from
## the mesh rather than looked up from a table: the packer's table is
## authoritative at build time and this is authoritative at run time, and the
## two can only agree if one of them is measured.
var stature := 1.0

var model: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
## Rifle attach point.  Parent the held weapon here, not to `hand_r`.
var weapon_mount: Node3D
var muzzle: Node3D
var head: Node3D
var hand_r: Node3D

var _overlay: StandardMaterial3D
## MeshInstance3D, not GeometryInstance3D: only the former has `.mesh`, and
## reaching for it through the base class silently yields an untyped value.
var _tinted: Array[MeshInstance3D] = []
var _flash := 0.0
var _dead := false
var _current := ""
var _one_shot := ""
var _one_shot_left := 0.0
var _weapon_bone := -1
var _aim_pitch := 0.0
var _built := false
var _armed := false


# ------------------------------------------------------------------ build

func build(pal := {}) -> void:
	palette = pal.duplicate()
	bulk = float(palette.get("bulk", 1.0))
	_armed = false

	model_key = String(palette.get("model", "trooper"))
	var path: String = String(MODELS.get(model_key, MODELS["trooper"]))
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("HumanoidRig: could not load %s" % path)
		return
	model = packed.instantiate() as Node3D
	model.name = "Model"
	add_child(model)

	skeleton = _find_node(model, "Skeleton3D") as Skeleton3D
	anim = _find_node(model, "AnimationPlayer") as AnimationPlayer
	if skeleton == null or anim == null:
		push_error("HumanoidRig: %s has no Skeleton3D/AnimationPlayer" % path)
		return
	_weapon_bone = skeleton.find_bone("weapon")

	_tint_materials()
	_measure()
	_build_attachments()
	_built = true
	play("idle", 0.0)


## Read this mesh's size and whether it is built to carry a rifle.
func _measure() -> void:
	var box := AABB()
	var first := true
	for mi in _tinted:
		if mi.mesh == null:
			continue
		var b := mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false

	# `bulk` predates the archetypes -- it was how the old primitive rig varied a
	# person's size.  Size now lives in the geometry, so this is a narrow band of
	# individual variation on top of it, clamped because a palette asking for
	# 1.14 would otherwise double up with a heavy's own proportions and walk the
	# skeleton away from the hitbox and health bar the enemy was built with.
	var s := clampf(bulk, 0.94, 1.06)
	model.scale = Vector3.ONE * s

	# Stature is what the game sizes hitboxes and eye lines from, so it has to
	# describe the character as it is actually rendered: the mesh's own height
	# times whatever `bulk` did on top of it.
	if not first and box.size.y > 0.01:
		stature = box.size.y * s / BASE_HEIGHT

	# The unarmed archetype ships without the clips that need a rifle, so the
	# file itself says whether there is one to hold.  No parallel table to keep
	# in step with the packer.
	_armed = anim.has_animation("fire")


## Whether this archetype is built to hold a rifle.
func is_armed() -> bool:
	return _armed


func _find_node(root: Node, type_name: String) -> Node:
	if root.is_class(type_name) or root.get_class() == type_name:
		return root
	for c in root.get_children():
		var hit := _find_node(c, type_name)
		if hit != null:
			return hit
	return null


func _attach(bone: String, node_name: String, pos := Vector3.ZERO,
		rot := Vector3.ZERO) -> Node3D:
	if skeleton.find_bone(bone) < 0:
		push_warning("HumanoidRig: no bone '%s'" % bone)
		return null
	var holder := BoneAttachment3D.new()
	holder.name = node_name + "Bone"
	holder.bone_name = bone
	skeleton.add_child(holder)
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	n.rotation_degrees = rot
	holder.add_child(n)
	return n


func _build_attachments() -> void:
	weapon_mount = _attach("weapon", "WeaponMount", Vector3.ZERO, MOUNT_ROTATION)
	if weapon_mount != null:
		# The rifle does not grow with the person holding it: cancel the model
		# scale on the mount so the weapon keeps its authored size while its
		# position still follows the scaled skeleton.
		if not is_equal_approx(model.scale.x, 1.0):
			weapon_mount.scale = Vector3.ONE / model.scale.x
		muzzle = Node3D.new()
		muzzle.name = "Muzzle"
		muzzle.position = RIFLE_MUZZLE
		weapon_mount.add_child(muzzle)
	# `head` is the eye position the enemy AI aims from
	head = _attach("head", "Head", Vector3(0.0, 0.10, -0.02))
	hand_r = _attach("hand_R", "HandR")


# ----------------------------------------------------------------- visuals

func _color_of(v) -> Color:
	if v is Color:
		return v
	if v is BaseMaterial3D:
		return (v as BaseMaterial3D).albedo_color
	return Color.WHITE


func _tint_materials() -> void:
	var primary := _color_of(palette.get("primary", Color("39424a")))
	var secondary := _color_of(palette.get("secondary", Color("232a30")))
	var accent := _color_of(palette.get("accent", Color("8a5a2b")))
	# `gear` is the boots, gloves and belt -- separate from `accent` so a faction
	# can wear a red mark without its footwear going red with it.  Defaults to
	# the accent, so any palette that does not name it is unchanged.
	var gear := _color_of(palette.get("gear", palette.get("accent", Color("8a5a2b"))))
	# The head-wrap is its own colour rather than a repaint of the uniform,
	# because that contrast -- a pale scarf over sand cloth -- is the whole
	# reason the contingent reads.  Defaults to the uniform for anyone else.
	var scarf := _color_of(palette.get("scarf", palette.get("primary", Color("6b5b4a"))))
	var skin := _color_of(palette.get("skin", Color("6b5b4a")))

	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.albedo_color = Color(1, 1, 1, 0)
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_overlay.disable_receive_shadows = true

	_tinted.clear()
	_collect_meshes(model)
	var tinted_surfaces := 0
	# one duplicated material per (mesh, surface) so tinting cannot leak between
	# the player and the enemies sharing the same imported sub-resources
	for mi in _tinted:
		mi.material_overlay = _overlay
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(s)
			if src == null or not (src is StandardMaterial3D):
				continue
			var name := String((src as StandardMaterial3D).resource_name).to_lower()
			var tint := primary
			if name.begins_with("cloth_lt") or name.begins_with("cloth_pale") \
					or name.begins_with("webbing") or name.begins_with("rubber"):
				tint = secondary
			elif name.begins_with("shemagh"):
				tint = scarf
			elif name.begins_with("leather"):
				tint = gear
			elif name.begins_with("accent"):
				tint = accent
			elif name.begins_with("skin"):
				tint = skin
			elif name.begins_with("cloth"):
				tint = primary
			else:
				continue  # hardware, glass and the lamp keep their own look
			var dup := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
			dup.resource_name = name
			dup.albedo_color = tint
			mi.set_surface_override_material(s, dup)
			tinted_surfaces += 1
	if tinted_surfaces == 0:
		# if this ever fires the character renders in the GLB's own colours and
		# the faction palette silently stops mattering
		push_warning("HumanoidRig: no surfaces matched the palette map")


func _collect_meshes(n: Node) -> void:
	if n is MeshInstance3D:
		_tinted.append(n as MeshInstance3D)
	for c in n.get_children():
		_collect_meshes(c)


# -------------------------------------------------------------------- play

func current_clip() -> String:
	return _current


func has_clip(name: String) -> bool:
	return anim != null and anim.has_animation(name)


func play(name: String, blend := 0.22) -> void:
	if anim == null or not anim.has_animation(name):
		return
	if _current == name and anim.is_playing():
		return
	anim.play(name, blend)
	_current = name


## Play a clip once and hold its last frame; further `update` calls leave it be
## until the clip finishes or something else interrupts it.
func play_once(name: String, blend := 0.12) -> void:
	if anim == null or not anim.has_animation(name):
		return
	_one_shot = name
	_one_shot_left = anim.get_animation(name).length
	_current = name
	anim.play(name, blend)


func one_shot_active() -> bool:
	return _one_shot != ""


# ------------------------------------------------------------------ update

func update(delta: float, p: Dictionary) -> void:
	if not _built:
		return

	_aim_pitch = float(p.get("aim_pitch", 0.0))

	if _one_shot != "":
		_one_shot_left -= delta
		if _one_shot_left > 0.0:
			_apply_aim_pitch()
			return
		_one_shot = ""
	if _dead:
		_apply_aim_pitch()
		return

	var speed := float(p.get("speed", 0.0))
	var max_speed := maxf(float(p.get("max_speed", 4.0)), 0.5)
	var crouch := float(p.get("crouch", 0.0)) > 0.5
	var aiming := bool(p.get("aiming", false))
	var ratio := clampf(speed / max_speed, 0.0, 1.5)

	var want := "idle"
	if aiming:
		want = "aim_idle"
	elif crouch:
		want = "crouch_walk" if speed > 0.25 else "crouch_idle"
	elif speed > 0.25:
		want = "run" if ratio > 0.55 else "walk"

	play(want)

	# Match playback to real speed so the contact foot does not skate.  The
	# clips cover ground in proportion to the body that walks them, so the
	# nominal speed travels with stature too.
	var nominal := float(NOMINAL.get(want, 0.0)) * stature
	if nominal > 0.0:
		anim.speed_scale = clampf(speed / nominal, 0.55, 1.9)
	else:
		anim.speed_scale = 1.0
	_apply_aim_pitch()


## Pitch the shouldered rifle with the camera.  Applied as a bone override so
## it layers on top of whatever the clip is doing instead of fighting it.
func _apply_aim_pitch() -> void:
	if skeleton == null or _weapon_bone < 0:
		return
	if absf(_aim_pitch) < 0.001:
		# Nothing to undo: overrides are set non-persistent, so the renderer
		# drops the previous frame's on its own.  There is no per-bone clear in
		# Skeleton3D, only clear_bones_global_pose_override() for all of them.
		return
	# get_bone_global_pose returns the animated pose, not the override, and a
	# non-persistent override is dropped every frame -- so this composes cleanly
	# instead of accumulating pitch frame after frame.
	var pose := skeleton.get_bone_global_pose(_weapon_bone)
	var extra := Basis(Vector3.RIGHT, -_aim_pitch * 0.85)
	skeleton.set_bone_global_pose_override(_weapon_bone,
			Transform3D(extra * pose.basis, pose.origin), 1.0, false)


# ----------------------------------------------------------------- effects

func flash(strength := 0.8) -> void:
	_flash = maxf(_flash, strength)


func tick_flash(delta: float) -> void:
	if _flash <= 0.0:
		return
	_flash = maxf(0.0, _flash - delta * 4.2)
	if _overlay != null:
		_overlay.albedo_color = Color(1.0, 0.93, 0.86, _flash * 0.85)


func set_visible_body(v: bool) -> void:
	visible = v


func aim_transform() -> Transform3D:
	return muzzle.global_transform if muzzle != null else global_transform


func weapon_forward() -> Vector3:
	## Unit vector the held weapon is pointing, in world space.
	if muzzle != null and weapon_mount != null:
		return -weapon_mount.global_transform.basis.z
	return -global_transform.basis.z


# ------------------------------------------------------------ death / reset

func die(_dir_yaw := 0.0) -> void:
	_dead = true
	_one_shot = ""
	play_once("death", 0.08)


func is_dead() -> bool:
	return _dead


func reset() -> void:
	_dead = false
	_one_shot = ""
	_flash = 0.0
	if _overlay != null:
		_overlay.albedo_color = Color(1, 0.93, 0.86, 0.0)
	if skeleton != null and _weapon_bone >= 0:
		skeleton.clear_bones_global_pose_override()
	rotation = Vector3.ZERO
	position = Vector3.ZERO
	if _built:
		play("idle", 0.0)
