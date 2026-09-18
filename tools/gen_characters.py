#!/usr/bin/env python3
"""
CENTURY OF HUMILIATION -- character pipeline.

Builds the character meshes, armatures and animation clips with Blender, run
head-less, and exports them as glTF binary (`.glb`) for Godot to import.

    blender --background --python tools/gen_characters.py -- --stage all --all
    blender --background --python tools/gen_characters.py -- --stage all --variant heavy

Everything is parametric: one body is lofted from section curves, pushed
through an archetype's proportions, and dressed with gear variants, so the
player, the troopers, the heavies, the guards and the city's civilians all come
out of the same code with different proportions, kit and palettes.

Archetypes (`--all` builds the lot in one pass)
-----------------------------------------------
    player     light kit, no pack, lamp -- readable at close camera range
    trooper    the baseline body every proportion is measured against
    heavy      broad, 6% taller, pauldrons and a blast plate
    guard      tall and lean, emissive visor, thigh rig, near-black cloth
    civilian   no armour and no rifle: coat, hood, satchel

The cast is three groups: the resistance (cool), the occupier (sand under a
pale shemagh, red agal, one geometry across all three roles) and the occupied
population (dark civilian clothes).  Colours are authored as the same sRGB
hexes the engine's palettes use, so `--stage mesh` and the running game agree.

The extra clips a soldier needs (aim, fire, reload, melee) are skipped for an
unarmed archetype rather than baked against a weapon that is not there.

Geometry conventions
--------------------
* Blender is Z-up, the character stands with its feet at z = 0 and *faces +Y*.
  The glTF exporter maps Blender +Y to glTF -Z, which is "forward" in Godot,
  so the character arrives in engine already facing the right way.
* Sections are lofted as rings around a tangent frame, which is what gives the
  limbs a real taper (deltoid -> elbow -> wrist) instead of a capsule.
* Organic parts get smooth shading and a subdivision pass; hard-surface gear
  gets a bevel instead.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector, Matrix

# --------------------------------------------------------------------------
# paths / cli
# --------------------------------------------------------------------------

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_GLB = os.path.join(ROOT, "assets", "characters")
# Editable Blender sources live beside the exports but inside a directory Godot
# is told to ignore: left loose in assets/ the editor tries to import every
# .blend as a scene and errors out in headless mode.
OUT_SRC = os.path.join(OUT_GLB, "src")
OUT_PREVIEW = os.path.join(ROOT, ".concept", "chars")


def argv_after_ddash() -> list:
    if "--" in sys.argv:
        return sys.argv[sys.argv.index("--") + 1:]
    return []


def arg(name: str, default=None):
    a = argv_after_ddash()
    for i, tok in enumerate(a):
        if tok == name and i + 1 < len(a):
            return a[i + 1]
        if tok.startswith(name + "="):
            return tok.split("=", 1)[1]
    return default


def flag(name: str) -> bool:
    return name in argv_after_ddash()


# --------------------------------------------------------------------------
# scene helpers
# --------------------------------------------------------------------------


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.armatures,
                  bpy.data.actions, bpy.data.objects):
        for item in list(block):
            block.remove(item)


def link(obj):
    bpy.context.collection.objects.link(obj)
    return obj


def mesh_object(name: str, verts, faces, material=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    me.validate(verbose=False)
    me.update()
    obj = link(bpy.data.objects.new(name, me))
    if material is not None:
        obj.data.materials.append(material)
    return obj


def activate(obj):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply_modifiers(obj) -> None:
    activate(obj)
    for m in list(obj.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=m.name)
        except RuntimeError as exc:
            print("  ! could not apply %s on %s: %s" % (m.name, obj.name, exc))


def shade(obj, smooth=True, auto_angle=None) -> None:
    activate(obj)
    for p in obj.data.polygons:
        p.use_smooth = smooth
    if smooth and auto_angle is not None:
        # Blender 4.1+ replaced mesh.use_auto_smooth with a modifier/operator.
        try:
            bpy.ops.object.shade_auto_smooth(angle=auto_angle)
        except (AttributeError, RuntimeError):
            pass


# --------------------------------------------------------------------------
# lofting -- the core shape primitive
# --------------------------------------------------------------------------


def _frame(tangent: Vector):
    """Orthonormal frame around `tangent`; `right` is roughly world +X."""
    t = tangent.normalized()
    up_ref = Vector((0.0, 0.0, 1.0))
    if abs(t.dot(up_ref)) > 0.94:
        up_ref = Vector((0.0, 1.0, 0.0))
    right = up_ref.cross(t)
    if right.length < 1e-6:
        right = Vector((1.0, 0.0, 0.0))
    right.normalize()
    up = t.cross(right).normalized()
    return right, up


def loft(sections, sides=12, cap=True, profile=1.0):
    """
    Build a tube through `sections`.

    Each section is (point, rx, rz) -- an ellipse in the plane perpendicular to
    the path.  `sides` controls how round the cross-section is; `profile` < 1
    squashes the ring towards a rounded rectangle, which reads as muscle and
    cloth rather than hose pipe.
    """
    pts = [Vector(s[0]) for s in sections]
    verts, faces = [], []
    n = sides
    ring_index = []

    for i, (p, rx, rz) in enumerate(sections):
        if i == 0:
            tan = pts[1] - pts[0]
        elif i == len(sections) - 1:
            tan = pts[-1] - pts[-2]
        else:
            tan = pts[i + 1] - pts[i - 1]
        right, up = _frame(tan)
        base = len(verts)
        ring_index.append(base)
        for k in range(n):
            a = 2.0 * math.pi * k / n
            # superellipse-ish: pushing cos/sin towards +-1 flattens the sides
            c, s = math.cos(a), math.sin(a)
            if profile != 1.0:
                c = math.copysign(abs(c) ** profile, c)
                s = math.copysign(abs(s) ** profile, s)
            verts.append(p + right * (c * rx) + up * (s * rz))

    for i in range(len(sections) - 1):
        a, b = ring_index[i], ring_index[i + 1]
        for k in range(n):
            k2 = (k + 1) % n
            faces.append((a + k, a + k2, b + k2, b + k))

    if cap:
        # end caps as fans around a centre vertex, so they stay quads/tris
        c0 = Vector(sections[0][0])
        i0 = len(verts)
        verts.append(c0)
        a = ring_index[0]
        for k in range(n):
            faces.append((i0, a + (k + 1) % n, a + k))
        c1 = Vector(sections[-1][0])
        i1 = len(verts)
        verts.append(c1)
        b = ring_index[-1]
        for k in range(n):
            faces.append((i1, b + k, b + (k + 1) % n))
    return verts, faces


def box_mesh(center, size, rot=None):
    cx, cy, cz = center
    sx, sy, sz = (s * 0.5 for s in size)
    v = [Vector((x, y, z)) for x in (-sx, sx) for y in (-sy, sy) for z in (-sz, sz)]
    if rot is not None:
        v = [rot @ p for p in v]
    v = [p + Vector((cx, cy, cz)) for p in v]
    f = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 2, 6, 4), (1, 5, 7, 3),
         (0, 4, 5, 1), (2, 3, 7, 6)]
    return v, f


def mirrored(sections):
    """Mirror a section list across X."""
    return [(Vector((-p[0], p[1], p[2])), rx, rz) for (p, rx, rz) in sections]


def lerp_sections(a, b, t):
    return [(a[i][0].lerp(b[i][0], t), a[i][1] + (b[i][1] - a[i][1]) * t,
             a[i][2] + (b[i][2] - a[i][2]) * t) for i in range(len(a))]


# --------------------------------------------------------------------------
# materials
# --------------------------------------------------------------------------


def mat(name: str, color, roughness=0.7, metallic=0.0, sheen=0.0, coat=0.0,
        emission=None, emission_strength=0.0):
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf is None:
        return m
    r, g, b = color
    bsdf.inputs["Base Color"].default_value = (r, g, b, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    for key, val in (("Sheen Weight", sheen), ("Coat Weight", coat)):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = val
    if emission is not None:
        for key in ("Emission Color", "Emission"):
            if key in bsdf.inputs:
                bsdf.inputs[key].default_value = (*emission, 1.0)
                break
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emission_strength
    m["monolith_role"] = name
    return m


def srgb(hexstr: str):
    """sRGB hex -> the linear triple Blender wants.

    The engine tints these same materials at runtime from a palette written in
    sRGB, and this table used to be hand-picked in linear instead.  The two
    drifted, so the reference renders showed one army and the game showed
    another.  Authoring both in the same notation is what keeps them equal.
    """
    h = hexstr.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


def materials():
    return {
        # --- body -------------------------------------------------------
        "skin":      mat("skin", (0.42, 0.32, 0.26), roughness=0.62, sheen=0.25),
        "cloth":     mat("cloth_uniform", (0.115, 0.128, 0.118), roughness=0.88,
                         sheen=0.35),
        "cloth_lt":  mat("cloth_pale", (0.163, 0.176, 0.163), roughness=0.85,
                         sheen=0.3),
        # The head-wrap.  Its own material rather than a repaint of `cloth`, so
        # a contingent can carry a scarf colour deliberately set against its
        # uniform -- which is how the real thing is worn, and what makes the
        # silhouette readable.
        "shemagh":   mat("shemagh", (0.34, 0.30, 0.21), roughness=0.9,
                         sheen=0.45),
        "webbing":   mat("webbing", (0.086, 0.092, 0.082), roughness=0.78,
                         sheen=0.2),
        "leather":   mat("leather", (0.055, 0.048, 0.042), roughness=0.58,
                         coat=0.25),
        "rubber":    mat("rubber", (0.032, 0.032, 0.034), roughness=0.92),
        "metal":     mat("hardware", (0.16, 0.165, 0.175), roughness=0.42,
                         metallic=0.92),
        "steel_lt":  mat("hardware_pale", (0.30, 0.32, 0.34), roughness=0.36,
                         metallic=0.9),
        "glass":     mat("goggle_glass", (0.045, 0.055, 0.062), roughness=0.14,
                         metallic=0.15, coat=0.6),
        # --- trim -------------------------------------------------------
        "accent":    mat("accent_tape", (0.34, 0.19, 0.08), roughness=0.72),
        # The elite's eye-band.  It used to be cyan, which belonged to nobody:
        # the contingent is sand and red, so the one emissive thing in the game
        # is now the contingent's red, which is also what makes the elite
        # legible in the dark now that it wears a wrap instead of a helmet.
        "visor":     mat("visor_emit", (0.09, 0.02, 0.01), roughness=0.25,
                         emission=(1.0, 0.30, 0.12), emission_strength=3.0),
        "lamp":      mat("lamp_lens", (0.85, 0.82, 0.72), roughness=0.2,
                         emission=(1.0, 0.94, 0.8), emission_strength=6.0),
        # Named on purpose: the engine's palette map tints by material-name
        # prefix, so hair has to answer to `webbing` (dark) and the inside of a
        # hood to `rubber` (darkest) rather than looking like unmapped extras.
        "hair":      mat("webbing_hair", (0.052, 0.046, 0.040), roughness=0.66,
                         sheen=0.4),
        "shadow":    mat("rubber_shadow", (0.020, 0.020, 0.022), roughness=0.95),
    }


# --------------------------------------------------------------------------
# anatomy -- reference skeleton, shared by mesh and rig
# --------------------------------------------------------------------------

# Every measurement is metres, feet on the floor, facing +Y.
A = {
    "height": 1.80,
    "ankle_z": 0.095,
    "knee_z": 0.475,
    "hip_z": 0.945,
    "waist_z": 1.055,
    "chest_z": 1.315,
    "shoulder_z": 1.455,
    "shoulder_x": 0.203,
    "neck_z": 1.505,
    "chin_z": 1.615,
    "head_z": 1.695,
    "crown_z": 1.795,
    "elbow_z": 1.150,
    "wrist_z": 0.880,
    "hip_x": 0.098,
}

# The same table is the *base* build every archetype is shaped from.
BASE = dict(A)

# --------------------------------------------------------------------------
# archetype proportions
# --------------------------------------------------------------------------
#
# Heavy, guard and civilian are not separate hand-modelled meshes: they are the
# one authored body pushed through a shape function.  One anatomy, one skinning
# pass, one clip set -- and the difference between a trooper and a heavy is a
# number that gets applied everywhere at once instead of four meshes that drift
# apart every time the body is edited.
#
# The function is applied to the joined mesh vertices *and* to the armature's
# bone coordinates with the same numbers, which is what keeps the skeleton
# inside the skin.  Scaling the mesh alone walks the arm centrelines away from
# their bones; scaling the bones alone drags the skin with them.
#
# Width is tapered towards the shoulder line rather than scaled flat, so a
# heavy reads as broad rather than as a uniformly inflated trooper, and the
# skull is pulled back to its own factor so it does not balloon with the chest.
P = {"stature": 1.0, "girth": 1.0, "shoulder": 1.0, "head": 1.0,
     "armed": True}


def set_proportion(variant: str) -> None:
    spec = VARIANTS.get(variant, {}).get("proportion", {})
    P["stature"] = float(spec.get("stature", 1.0))
    P["girth"] = float(spec.get("girth", 1.0))
    P["shoulder"] = float(spec.get("shoulder", P["girth"]))
    P["head"] = float(spec.get("head", 1.0))
    P["armed"] = bool(VARIANTS.get(variant, {}).get("armed", True))


def _ramp(u: float) -> float:
    u = max(0.0, min(1.0, u))
    return u * u * (3.0 - 2.0 * u)


def width_at(z: float) -> float:
    """Lateral scale for the archetype at height `z`."""
    u = _ramp((z - BASE["hip_z"]) / max(BASE["shoulder_z"] - BASE["hip_z"], 1e-6))
    w = _ramp((z - BASE["neck_z"]) / max(BASE["crown_z"] - BASE["neck_z"], 1e-6))
    return (P["girth"] + (P["shoulder"] - 1.0) * u) * (1.0 - w) + P["head"] * w


def shape_point(p) -> Vector:
    """Map a base-space point on the character into this archetype's build."""
    p = Vector(p)
    return Vector((p.x * width_at(p.z), p.y * P["girth"], p.z * P["stature"]))


def shape_chest_offset(v) -> Vector:
    """Reshape a metre offset authored at chest height (weapon-bone space).
    The weapon bone's local axes line up with the world's, so the same width /
    depth / height scaling applies to the offsets the clips write into it."""
    v = Vector(v)
    return Vector((v.x * width_at(BASE["chest_z"]), v.y * P["girth"],
                   v.z * P["stature"]))


def shaped_cfg(cfg: dict) -> dict:
    """Scale the metre-valued clip parameters with the body they belong to.
    Angles are scale-free and are left alone; lengths, lifts and pelvis drops
    are not, and neither is the width of the pelvis sway.

    Tagged and re-entrant because the clip builders pass cfg dicts down a
    couple of layers, and applying this twice would silently double the
    character's stride instead of failing loudly."""
    if cfg.get("_shaped"):
        return cfg
    out = dict(cfg)
    out["_shaped"] = True
    for key in ("stride", "lift", "bob", "crouch_drop"):
        if key in out:
            out[key] = out[key] * P["stature"]
    if "sway" in out:
        out["sway"] = out["sway"] * P["girth"]
    return out


def shape_mesh(body) -> int:
    """Push the joined mesh through `shape_point`."""
    for v in body.data.vertices:
        v.co = shape_point(v.co)
    body.data.update()
    return len(body.data.vertices)


def shape_armature(arm) -> None:
    """Push every bone through the same function as the mesh."""
    activate(arm)
    bpy.ops.object.mode_set(mode='EDIT')
    for b in arm.data.edit_bones:
        b.head = shape_point(b.head)
        b.tail = shape_point(b.tail)
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.context.view_layer.update()


def torso_sections():
    return [
        (Vector((0.0, 0.0, 0.900)), 0.150, 0.112),   # crotch
        (Vector((0.0, 0.004, 0.960)), 0.170, 0.122),  # hips
        (Vector((0.0, 0.004, 1.055)), 0.152, 0.110),  # waist
        (Vector((0.0, 0.002, 1.150)), 0.163, 0.113),
        (Vector((0.0, 0.0, 1.240)), 0.184, 0.121),    # lower ribs
        (Vector((0.0, -0.004, 1.320)), 0.201, 0.128),  # chest
        (Vector((0.0, -0.004, 1.400)), 0.207, 0.124),  # upper chest
        (Vector((0.0, 0.0, 1.455)), 0.196, 0.112),    # shoulder line
        (Vector((0.0, 0.004, 1.510)), 0.140, 0.098),  # trapezius
    ]


def neck_sections():
    return [
        (Vector((0.0, 0.004, 1.495)), 0.062, 0.062),
        (Vector((0.0, 0.006, 1.560)), 0.056, 0.058),
        (Vector((0.0, 0.004, 1.620)), 0.058, 0.062),
    ]


def head_sections():
    return [
        (Vector((0.0, 0.012, 1.610)), 0.066, 0.074),   # under jaw
        (Vector((0.0, 0.014, 1.650)), 0.082, 0.092),   # jaw
        (Vector((0.0, 0.010, 1.690)), 0.090, 0.099),   # cheek / temple
        (Vector((0.0, 0.004, 1.735)), 0.089, 0.097),
        (Vector((0.0, 0.0, 1.780)), 0.070, 0.077),     # crown
        (Vector((0.0, -0.006, 1.810)), 0.030, 0.033),
    ]


def arm_sections(side=1.0):
    s = float(side)
    sx = A["shoulder_x"]
    return [
        (Vector((s * (sx - 0.012), 0.0, A["shoulder_z"] + 0.022)), 0.070, 0.072),  # deltoid top
        (Vector((s * (sx + 0.026), 0.004, A["shoulder_z"] - 0.075)), 0.058, 0.060),
        (Vector((s * (sx + 0.038), 0.010, 1.225)), 0.049, 0.051),                 # biceps
        (Vector((s * (sx + 0.044), 0.016, A["elbow_z"])), 0.045, 0.047),          # elbow
        (Vector((s * (sx + 0.050), 0.014, 1.055)), 0.048, 0.050),                 # forearm
        (Vector((s * (sx + 0.054), 0.020, 0.960)), 0.039, 0.041),
        (Vector((s * (sx + 0.056), 0.026, A["wrist_z"])), 0.031, 0.034),          # wrist
    ]


def hand_sections(side=1.0):
    s = float(side)
    sx = A["shoulder_x"]
    return [
        (Vector((s * (sx + 0.056), 0.026, A["wrist_z"] - 0.005)), 0.033, 0.036),
        (Vector((s * (sx + 0.058), 0.030, 0.820)), 0.041, 0.050),
        (Vector((s * (sx + 0.058), 0.034, 0.760)), 0.039, 0.052),
        (Vector((s * (sx + 0.056), 0.036, 0.722)), 0.030, 0.045),   # knuckles
    ]


def leg_sections(side=1.0):
    s = float(side)
    hx = A["hip_x"]
    return [
        (Vector((s * hx, 0.0, A["hip_z"] + 0.035)), 0.098, 0.096),
        (Vector((s * (hx + 0.008), 0.002, 0.830)), 0.088, 0.090),
        (Vector((s * (hx + 0.016), 0.006, 0.690)), 0.075, 0.079),
        (Vector((s * (hx + 0.020), 0.008, A["knee_z"] + 0.055)), 0.064, 0.068),
        (Vector((s * (hx + 0.022), 0.010, A["knee_z"])), 0.058, 0.061),     # knee
        (Vector((s * (hx + 0.024), 0.004, 0.380)), 0.060, 0.066),          # calf
        (Vector((s * (hx + 0.026), 0.0, 0.230)), 0.048, 0.052),
        (Vector((s * (hx + 0.026), 0.0, A["ankle_z"] + 0.015)), 0.038, 0.042),
    ]


def boot_sections(side=1.0):
    """Ankle -> instep -> toe box, flattened so it reads as footwear."""
    s = float(side)
    x = s * (A["hip_x"] + 0.026)
    return [
        (Vector((x, 0.0, 0.120)), 0.042, 0.046),
        (Vector((x, 0.010, 0.062)), 0.048, 0.052),
        (Vector((x, 0.055, 0.040)), 0.046, 0.062),
        (Vector((x, 0.105, 0.034)), 0.044, 0.060),
        (Vector((x, 0.150, 0.030)), 0.040, 0.052),
        (Vector((x, 0.178, 0.030)), 0.030, 0.040),   # toe
    ]


# --------------------------------------------------------------------------
# body assembly
# --------------------------------------------------------------------------


def build_body(M) -> list:
    """Skin + uniform.  Returns the list of created objects."""
    out = []

    def add(name, sections, material, sides=14, profile=1.0, sub=2, bevel=0.0,
            smooth=True):
        v, f = loft(sections, sides=sides, profile=profile)
        o = mesh_object(name, v, f, material)
        if sub:
            m = o.modifiers.new("Subsurf", 'SUBSURF')
            m.levels = sub
            m.render_levels = sub
        if bevel:
            b = o.modifiers.new("Bevel", 'BEVEL')
            b.width = bevel
            b.segments = 2
            b.limit_method = 'ANGLE'
        apply_modifiers(o)
        shade(o, smooth)
        out.append(o)
        return o

    # torso in the uniform, neck and a small wedge of face in skin
    add("Torso", torso_sections(), M["cloth"], sides=16, profile=0.78, sub=2)
    add("Neck", neck_sections(), M["skin"], sides=12, sub=1)
    add("Head", head_sections(), M["skin"], sides=16, profile=0.8, sub=2)

    # a jaw/cheek mass so the profile is not a bare egg
    add("Jaw", [
        (Vector((0.0, 0.052, 1.672)), 0.052, 0.026),
        (Vector((0.0, 0.086, 1.660)), 0.030, 0.020),
    ], M["cloth"], sides=10, sub=1)

    for side in (-1.0, 1.0):
        tag = "L" if side < 0 else "R"
        add("Arm" + tag, arm_sections(side), M["cloth"], sides=12, profile=0.85, sub=2)
        add("Hand" + tag, hand_sections(side), M["leather"], sides=10,
            profile=0.7, sub=1)
        add("Leg" + tag, leg_sections(side), M["cloth"], sides=12, profile=0.85, sub=2)
        add("Boot" + tag, boot_sections(side), M["leather"], sides=12,
            profile=0.68, sub=1)

        # thumb, tucked against the grip
        s = float(side)
        x = s * (A["shoulder_x"] + 0.056)
        add("Thumb" + tag, [
            (Vector((x - s * 0.024, 0.030, 0.815)), 0.017, 0.017),
            (Vector((x - s * 0.030, 0.052, 0.792)), 0.015, 0.015),
        ], M["leather"], sides=8, sub=1)

        # boot sole
        v, f = box_mesh((s * (A["hip_x"] + 0.026), 0.086, 0.016), (0.092, 0.235, 0.032))
        o = mesh_object("Sole" + tag, v, f, M["rubber"])
        b = o.modifiers.new("Bevel", 'BEVEL')
        b.width = 0.010
        b.segments = 2
        apply_modifiers(o)
        shade(o, False)
        out.append(o)

    return out


def build_gear(M, kit) -> list:
    """Hard-surface kit: helmet, carrier, pouches, belt, pads, pack."""
    out = []

    def add(name, sections, material, sides=12, profile=1.0, sub=0, bevel=0.006,
            smooth=False):
        v, f = loft(sections, sides=sides, profile=profile)
        o = mesh_object(name, v, f, material)
        if bevel:
            b = o.modifiers.new("Bevel", 'BEVEL')
            b.width = bevel
            b.segments = 2
            b.limit_method = 'ANGLE'
        if sub:
            m = o.modifiers.new("Subsurf", 'SUBSURF')
            m.levels = sub
            m.render_levels = sub
        apply_modifiers(o)
        shade(o, smooth)
        out.append(o)
        return o

    def addbox(name, center, size, material, bevel=0.008, smooth=False, rot=None):
        v, f = box_mesh(center, size, rot)
        o = mesh_object(name, v, f, material)
        if bevel:
            b = o.modifiers.new("Bevel", 'BEVEL')
            b.width = bevel
            b.segments = 2
            b.limit_method = 'ANGLE'
        apply_modifiers(o)
        shade(o, smooth)
        out.append(o)
        return o

    # --- helmet -----------------------------------------------------------
    if kit.get("helmet", True):
        add("HelmetShell", [
            (Vector((0.0, 0.010, 1.678)), 0.104, 0.111),
            (Vector((0.0, 0.006, 1.714)), 0.108, 0.114),
            (Vector((0.0, 0.0, 1.760)), 0.101, 0.107),
            (Vector((0.0, -0.006, 1.802)), 0.077, 0.083),
            (Vector((0.0, -0.010, 1.832)), 0.033, 0.036),
        ], M["cloth_lt"], sides=16, profile=0.82, sub=1, bevel=0.0, smooth=True)
        # brim, a little heavier at the front
        add("HelmetBrim", [
            (Vector((0.0, 0.020, 1.684)), 0.108, 0.113),
            (Vector((0.0, 0.030, 1.678)), 0.118, 0.130),
        ], M["cloth_lt"], sides=16, profile=0.8, sub=0, bevel=0.004, smooth=True)
        for side in (-1.0, 1.0):
            tag = "L" if side < 0 else "R"
            addbox("EarCup" + tag, (side * 0.100, 0.006, 1.688), (0.032, 0.108, 0.088),
                   M["cloth"], bevel=0.012)
            addbox("CupBolt" + tag, (side * 0.118, 0.006, 1.688), (0.012, 0.032, 0.032),
                   M["metal"], bevel=0.003)
        if kit.get("goggles", True):
            add("Goggles", [
                (Vector((0.0, 0.086, 1.706)), 0.086, 0.030),
                (Vector((0.0, 0.098, 1.706)), 0.080, 0.026),
            ], M["glass"], sides=12, profile=1.0, sub=0, bevel=0.005, smooth=True)
            add("GoggleStrap", [
                (Vector((0.0, -0.030, 1.712)), 0.110, 0.017),
                (Vector((0.0, 0.030, 1.712)), 0.110, 0.017),
            ], M["webbing"], sides=12, profile=0.9, sub=0, bevel=0.004, smooth=True)
        if kit.get("nvg", False):
            addbox("NvgMount", (0.0, 0.104, 1.756), (0.046, 0.052, 0.030), M["metal"],
                   bevel=0.005)
            addbox("NvgBody", (0.0, 0.140, 1.762), (0.070, 0.080, 0.056), M["cloth"],
                   bevel=0.010)
            addbox("NvgLens", (0.0, 0.184, 1.762), (0.040, 0.020, 0.036), M["lamp"],
                   bevel=0.006)

    # A banded visor is the elite's tell: one emissive strip across the eyes,
    # so a guard is identifiable at 40 m in the dark.  It hangs off the face
    # rather than off the helmet, because the elite now goes bare-headed under
    # a wrap, and an emissive band is the one identifier that survives that.
    if kit.get("visor", False):
        add("VisorBand", [
            (Vector((0.0, 0.088, 1.702)), 0.094, 0.026),
            (Vector((0.0, 0.104, 1.704)), 0.086, 0.022),
        ], M["visor"], sides=14, profile=0.88, sub=0, bevel=0.004, smooth=True)
        # The brow plate sits on the forehead, which is exactly where a wrap's
        # front edge lands, so it comes off for anyone wearing one.  The
        # emissive band itself is below the brow line and stays.
        if not kit.get("shemagh", False):
            add("VisorBrow", [
                (Vector((0.0, 0.074, 1.726)), 0.104, 0.016),
                (Vector((0.0, 0.102, 1.720)), 0.100, 0.014),
            ], M["metal"], sides=14, profile=0.8, sub=0, bevel=0.004, smooth=True)

    # --- shemagh: the contingent's head-wrap ------------------------------
    # Cloth over the crown, a cord holding it, and a tail down each side of the
    # face.  Built as cloth rather than as a helmet in another colour, because
    # this is the piece the whole faction reads from -- so it drapes: the cap
    # stands clear of the skull, the tails hang past the jaw to the shoulder
    # line, and the front edge stops at the brow so the face stays open.
    if kit.get("shemagh", False):
        add("ShemaghCap", [
            (Vector((0.0, 0.004, 1.718)), 0.106, 0.118),
            (Vector((0.0, -0.002, 1.750)), 0.104, 0.117),
            (Vector((0.0, -0.010, 1.782)), 0.088, 0.102),
            (Vector((0.0, -0.018, 1.810)), 0.048, 0.060),
        ], M["shemagh"], sides=16, profile=0.76, sub=1, bevel=0.0, smooth=True)
        # The agal: the cord that holds the wrap, and the faction's mark.  A real
        # one is plain black twist; here it takes the contingent's red, which is
        # the same red as the banner -- a soldier is identifiable from the top
        # of his head, which is all a third-person camera ever sees of him.
        add("Agal", [
            (Vector((0.0, -0.006, 1.744)), 0.112, 0.125),
            (Vector((0.0, -0.006, 1.768)), 0.109, 0.122),
        ], M["accent"], sides=18, profile=0.98, sub=0, bevel=0.0, smooth=True)
        for side in (-1.0, 1.0):
            tag = "L" if side < 0 else "R"
            add("ShemaghTail" + tag, [
                (Vector((side * 0.092, -0.008, 1.716)), 0.028, 0.084),
                (Vector((side * 0.104, -0.002, 1.642)), 0.033, 0.096),
                (Vector((side * 0.101, 0.008, 1.550)), 0.031, 0.090),
                (Vector((side * 0.093, 0.016, 1.464)), 0.025, 0.076),
                (Vector((side * 0.085, 0.022, 1.420)), 0.019, 0.056),
            ], M["shemagh"], sides=10, profile=0.62, sub=1, bevel=0.0, smooth=True)

    # --- bare head: hair and a hood, nobody here is wearing a helmet -------
    if kit.get("hair", False):
        add("Hair", [
            (Vector((0.0, -0.012, 1.648)), 0.086, 0.096),
            (Vector((0.0, -0.014, 1.694)), 0.094, 0.104),
            (Vector((0.0, -0.016, 1.740)), 0.092, 0.100),
            (Vector((0.0, -0.020, 1.776)), 0.070, 0.078),
        ], M["hair"], sides=14, profile=0.84, sub=1, bevel=0.0, smooth=True)
    if kit.get("hood", False):
        add("Hood", [
            (Vector((0.0, -0.004, 1.586)), 0.116, 0.128),
            (Vector((0.0, -0.006, 1.664)), 0.118, 0.132),
            (Vector((0.0, -0.010, 1.742)), 0.108, 0.120),
            (Vector((0.0, -0.018, 1.800)), 0.070, 0.082),
        ], M["cloth_lt"], sides=16, profile=0.8, sub=1, bevel=0.0, smooth=True)
        add("HoodShadow", [
            (Vector((0.0, 0.062, 1.640)), 0.070, 0.078),
            (Vector((0.0, 0.082, 1.700)), 0.076, 0.082),
        ], M["shadow"], sides=12, profile=0.9, sub=0, bevel=0.0, smooth=True)

    # --- balaclava / neck wrap -------------------------------------------
    # Gated, because on a civilian the same loft stops reading as a neck wrap
    # and starts reading as a soldier's collar.
    if kit.get("collar", True):
        add("Collar", [
            (Vector((0.0, 0.004, 1.480)), 0.116, 0.108),
            (Vector((0.0, 0.006, 1.535)), 0.092, 0.090),
            (Vector((0.0, 0.008, 1.578)), 0.080, 0.082),
        ], M["webbing"], sides=14, profile=0.85, sub=1, bevel=0.0, smooth=True)

    # --- plate carrier ----------------------------------------------------
    if kit.get("carrier", True):
        add("Carrier", [
            (Vector((0.0, 0.0, 1.120)), 0.172, 0.122),
            (Vector((0.0, -0.002, 1.200)), 0.196, 0.136),
            (Vector((0.0, -0.004, 1.300)), 0.208, 0.144),
            (Vector((0.0, -0.004, 1.386)), 0.200, 0.138),
            (Vector((0.0, 0.0, 1.430)), 0.182, 0.124),
        ], M["cloth_lt"], sides=16, profile=0.62, sub=0, bevel=0.012, smooth=True)
        # front plate seam
        addbox("PlatSeam", (0.0, 0.146, 1.280), (0.150, 0.020, 0.200), M["webbing"],
               bevel=0.006)
        if kit.get("band", False):
            # The contingent's mark across the plate.  The head already carries
            # it on the agal, which is all a rear camera sees; this is for the
            # frontal read, where a 6 cm unit patch would be four pixels.
            addbox("ChestBand", (0.0, 0.150, 1.360), (0.150, 0.020, 0.028),
                   M["accent"], bevel=0.003)
        for side in (-1.0, 1.0):
            tag = "L" if side < 0 else "R"
            addbox("StrapFront" + tag, (side * 0.104, 0.132, 1.400),
                   (0.048, 0.024, 0.150), M["webbing"], bevel=0.005)
            addbox("StrapBack" + tag, (side * 0.104, -0.118, 1.400),
                   (0.048, 0.024, 0.150), M["webbing"], bevel=0.005)
            addbox("SidePlate" + tag, (side * 0.196, 0.0, 1.250),
                   (0.030, 0.126, 0.170), M["cloth_lt"], bevel=0.010)
            if kit.get("mag_pouches", True):
                addbox("Mag" + tag, (side * 0.052, 0.156, 1.176),
                       (0.076, 0.056, 0.104), M["webbing"], bevel=0.010)

    # --- belt / harness ---------------------------------------------------
    if kit.get("belt", True):
        add("Belt", [
            (Vector((0.0, 0.004, 0.995)), 0.178, 0.130),
            (Vector((0.0, 0.004, 1.048)), 0.180, 0.132),
            (Vector((0.0, 0.004, 1.086)), 0.170, 0.124),
        ], M["webbing"], sides=16, profile=0.66, sub=0, bevel=0.006, smooth=True)
        addbox("Buckle", (0.0, 0.136, 1.042), (0.056, 0.026, 0.048), M["metal"],
               bevel=0.005)

    # --- tabard: two hanging aprons off the belt --------------------------
    # Written as a front and a back panel rather than a skirt around both legs.
    # A tube would be heat-weighted between the two thigh bones and tear open
    # the first time the legs disagree, which they do on every single step.
    if kit.get("apron", False):
        for tag, ay in (("Front", 0.148), ("Back", -0.146)):
            add("Apron" + tag, [
                (Vector((0.0, ay * 0.92, 0.985)), 0.118, 0.032),
                (Vector((0.0, ay, 0.900)), 0.126, 0.030),
                (Vector((0.0, ay * 1.04, 0.795)), 0.116, 0.026),
                (Vector((0.0, ay * 1.06, 0.742)), 0.092, 0.020),
            ], M["cloth_lt"], sides=10, profile=0.55, sub=1, bevel=0.006, smooth=True)
        addbox("ApronClasp", (0.0, 0.150, 1.012), (0.052, 0.024, 0.040), M["metal"],
               bevel=0.005)

    # --- a coat: the civilian silhouette ---------------------------------
    # Flares from the waist to below the knee and is open at the bottom.  It is
    # heat-weighted across hips and thighs, which only holds up while the legs
    # stay together -- so it belongs on the people who stand and talk, and the
    # guard's shorter apron exists for exactly the same reason.
    if kit.get("coat", False):
        add("Coat", [
            (Vector((0.0, 0.0, 1.140)), 0.206, 0.140),
            (Vector((0.0, 0.0, 1.040)), 0.196, 0.136),
            (Vector((0.0, -0.002, 0.860)), 0.212, 0.148),
            (Vector((0.0, -0.004, 0.640)), 0.218, 0.152),
            (Vector((0.0, -0.004, 0.470)), 0.208, 0.146),
        ], M["cloth"], sides=18, profile=0.72, sub=1, bevel=0.0, smooth=True)
        add("CoatLapel", [
            (Vector((0.0, 0.132, 1.300)), 0.108, 0.026),
            (Vector((0.0, 0.140, 1.160)), 0.128, 0.024),
        ], M["cloth_lt"], sides=10, profile=0.6, sub=1, bevel=0.005, smooth=True)

    if kit.get("pouches", True):
        for i, (bx, by, bw) in enumerate(((-0.132, 0.086, 0.062),
                                          (0.132, 0.086, 0.062),
                                          (0.132, -0.086, 0.062))):
            addbox("HipPouch%d" % i, (bx, by, 0.972), (bw, 0.058, 0.088),
                   M["webbing"], bevel=0.009)

    # --- shoulders, knees, wrists ----------------------------------------
    for side in (-1.0, 1.0):
        tag = "L" if side < 0 else "R"
        s = float(side)
        sx = A["shoulder_x"]
        if kit.get("pads", True):
            v, f = box_mesh((s * (sx + 0.028), 0.006, A["shoulder_z"] - 0.010),
                            (0.130, 0.128, 0.076))
            o = mesh_object("ShoulderPad" + tag, v, f, M["cloth_lt"])
            b = o.modifiers.new("Bevel", 'BEVEL')
            b.width = 0.016
            b.segments = 3
            b.limit_method = 'ANGLE'
            apply_modifiers(o)
            shade(o, True)
            out.append(o)
        if kit.get("pauldrons", False):
            # The heavy's silhouette, not its mass: a slab that overhangs the
            # deltoid, a second plate below it and a rim that catches the rim
            # light, so the shoulders read as armour rather than as a fat arm.
            add("Pauldron" + tag, [
                (Vector((s * (sx - 0.030), 0.004, A["shoulder_z"] + 0.052)), 0.086, 0.104),
                (Vector((s * (sx + 0.030), 0.006, A["shoulder_z"] + 0.036)), 0.104, 0.122),
                (Vector((s * (sx + 0.062), 0.008, A["shoulder_z"] - 0.036)), 0.098, 0.116),
                (Vector((s * (sx + 0.070), 0.010, A["shoulder_z"] - 0.086)), 0.072, 0.086),
            ], M["cloth_lt"], sides=12, profile=0.62, sub=1, bevel=0.010, smooth=True)
            addbox("PauldronRim" + tag, (s * (sx + 0.034),
                  0.006, A["shoulder_z"] + 0.046), (0.116, 0.150, 0.026), M["metal"],
                bevel=0.008)
        if kit.get("knee_pads", True):
            addbox("KneePad" + tag, (s * (A["hip_x"] + 0.030), 0.056,
                   A["knee_z"] + 0.020), (0.086, 0.048, 0.106), M["cloth_lt"],
                   bevel=0.014)
        if kit.get("gloves", True):
            addbox("Glove" + tag, (s * (sx + 0.058), 0.028, 0.842),
                   (0.070, 0.078, 0.062), M["leather"], bevel=0.012)
        if kit.get("thigh_rig", False):
            addbox("ThighRig" + tag, (s * (A["hip_x"] + 0.062), 0.048, 0.700),
                   (0.056, 0.076, 0.176), M["leather"], bevel=0.010)
        if kit.get("leg_wrap", False):
            add("LegWrap" + tag, [
                (Vector((s * (A["hip_x"] + 0.024), 0.006, 0.400)), 0.058, 0.062),
                (Vector((s * (A["hip_x"] + 0.026), 0.0, 0.230)), 0.052, 0.056),
                (Vector((s * (A["hip_x"] + 0.026), 0.0, 0.130)), 0.046, 0.050),
            ], M["cloth"], sides=12, profile=0.8, sub=1, bevel=0.0, smooth=True)

    # --- backpack ---------------------------------------------------------
    if kit.get("backpack", False):
        addbox("PackBody", (0.0, -0.196, 1.276), (0.256, 0.142, 0.330),
               M["cloth"], bevel=0.016)
        addbox("PackLid", (0.0, -0.206, 1.428), (0.240, 0.126, 0.062),
               M["webbing"], bevel=0.012)
        for side in (-1.0, 1.0):
            tag = "L" if side < 0 else "R"
            addbox("PackStrap" + tag, (side * 0.088, -0.208, 1.212),
                   (0.038, 0.118, 0.116), M["webbing"], bevel=0.008)

    # --- a bedroll on the small of the back -------------------------------
    if kit.get("bedroll", False):
        add("Bedroll", [
            (Vector((-0.150, -0.164, 1.062)), 0.048, 0.048),
            (Vector((0.150, -0.164, 1.062)), 0.048, 0.048),
        ], M["cloth"], sides=10, sub=1, bevel=0.0, smooth=True)

    # --- blast plate: an extra slab on the carrier ----------------------
    if kit.get("blast_plate", False):
        add("BlastPlate", [
            (Vector((0.0, 0.170, 1.160)), 0.150, 0.024),
            (Vector((0.0, 0.186, 1.240)), 0.176, 0.028),
            (Vector((0.0, 0.184, 1.340)), 0.180, 0.028),
            (Vector((0.0, 0.166, 1.412)), 0.152, 0.022),
        ], M["cloth_lt"], sides=12, profile=0.5, sub=0, bevel=0.012, smooth=True)
        for i, bz in enumerate((1.196, 1.312)):
            addbox("BlastBolt%d" % i, (0.0, 0.202, bz), (0.024, 0.030, 0.024),
                   M["metal"], bevel=0.004)

    # --- scarf: a wrap and a hanging tail --------------------------------
    if kit.get("scarf", False):
        add("Scarf", [
            (Vector((0.0, 0.004, 1.452)), 0.116, 0.112),
            (Vector((0.0, 0.006, 1.510)), 0.098, 0.096),
            (Vector((0.0, 0.008, 1.566)), 0.088, 0.090),
        ], M["cloth_lt"], sides=14, profile=0.82, sub=1, bevel=0.0, smooth=True)
        add("ScarfTail", [
            (Vector((-0.052, 0.104, 1.470)), 0.036, 0.030),
            (Vector((-0.062, 0.126, 1.330)), 0.034, 0.026),
            (Vector((-0.070, 0.132, 1.212)), 0.028, 0.022),
        ], M["cloth_lt"], sides=10, profile=0.8, sub=1, bevel=0.0, smooth=True)

    # --- satchel on the left hip, strap across the chest -----------------
    if kit.get("satchel", False):
        addbox("Satchel", (-0.176, 0.048, 0.946), (0.086, 0.140, 0.150),
               M["leather"], bevel=0.014)
        addbox("SatchelFlap", (-0.176, 0.056, 1.020), (0.094, 0.128, 0.048),
               M["leather"], bevel=0.010)
        add("SatchelStrap", [
            (Vector((0.108, 0.108, 1.430)), 0.026, 0.016),
            (Vector((0.030, 0.146, 1.286)), 0.024, 0.015),
            (Vector((-0.082, 0.128, 1.100)), 0.024, 0.015),
            (Vector((-0.170, 0.070, 0.998)), 0.022, 0.014),
        ], M["leather"], sides=8, profile=0.7, sub=1, bevel=0.0, smooth=True)

    return out


# --------------------------------------------------------------------------
# archetypes
# --------------------------------------------------------------------------# Three readable groups, and the colours below are the same sRGB hexes the
# engine's palettes carry, run through `srgb()` -- one source of truth, so the
# reference renders and the game can no longer show two different armies.
#
#   the resistance   cool grey-blue, no head-wrap, surplus tan leather
#   the occupier     sand cloth under a pale shemagh, red agal
#   the occupied     dark brown civilian clothes, nobody's uniform
#
# The occupier's three roles are graded rather than recoloured, and they share
# one geometry: the same wrap, the same agal, the same cloth skirt.  Only the
# heavy adds plates and the elite drops to near-black, which is how a contingent
# reads as one army with specialisations instead of three unrelated enemies.
_SAND = srgb("8a7a5c")

VARIANTS = {
    # the resistance: light kit, lamp on the shoulder, no pack, and the only
    # cool palette in the game, so the player never mistakes himself for them.
    "player": {
        "kit": {"helmet": True, "goggles": True, "nvg": False, "carrier": True,
                "mag_pouches": True, "pouches": True, "backpack": False,
                "bedroll": False},
        "mats": {"cloth": srgb("78868f"), "cloth_lt": srgb("39424a"),
                 "webbing": srgb("39424a"), "leather": srgb("c08a45"),
                 "skin": srgb("9a7f61")},
        "accent": srgb("c08a45"),
    },
    # the occupier's line infantryman: sand uniform, pale wrap, red agal, and
    # the thigh-length cloth the carrier is worn over.  Still the baseline body
    # every other archetype is proportioned against.
    "trooper": {
        "kit": {"helmet": False, "goggles": False, "nvg": False,
                "shemagh": True, "carrier": True, "mag_pouches": True,
                "pouches": True, "backpack": True, "apron": True,
                "bedroll": False, "band": True},
        "mats": {"cloth": _SAND, "cloth_lt": srgb("3a352b"),
                 "webbing": srgb("3a352b"), "shemagh": srgb("b8a688"),
                 "leather": srgb("4a3f30"), "skin": srgb("8a765c")},
        "accent": srgb("a8342a"),
    },
    # the heavy: the same cloth in shadow, under pauldrons and a blast plate.
    # Not a scaled-up trooper -- the width is tapered towards the shoulder line,
    # which is what reads as armoured mass instead of as a big person.
    "heavy": {
        "proportion": {"stature": 1.06, "girth": 1.11, "shoulder": 1.13,
                       "head": 1.03},
        "kit": {"helmet": False, "goggles": False, "nvg": False,
                "shemagh": True, "carrier": True, "mag_pouches": True,
                "pouches": True, "backpack": True, "apron": True,
                "bedroll": False, "pauldrons": True, "blast_plate": True,
                "knee_pads": True, "gloves": True, "band": True},
        "mats": {"cloth": srgb("6f6247"), "cloth_lt": srgb("2f2b23"),
                 "webbing": srgb("2f2b23"), "shemagh": srgb("9c8c6e"),
                 "leather": srgb("3d3428"), "skin": srgb("8a765c")},
        "accent": srgb("a8342a"),
    },
    # the elite: nearly black uniform under the palest wrap in the game, tall
    # and lean, with the emissive visor so it is still identifiable in the dark
    # now that its silhouette is cloth rather than a helmet.  The one archetype
    # whose shoulders are close to the trooper's, so it reads as *discipline*
    # next to the heavy's mass.
    "guard": {
        "proportion": {"stature": 1.03, "girth": 1.02, "shoulder": 1.05,
                       "head": 1.00},
        "kit": {"helmet": False, "goggles": False, "nvg": False,
                "shemagh": True, "visor": True, "carrier": True,
                "mag_pouches": True, "pouches": True, "backpack": False,
                "bedroll": False, "apron": True, "thigh_rig": True,
                "knee_pads": True, "gloves": True, "band": True},
        "mats": {"cloth": srgb("242a2e"), "cloth_lt": srgb("14181b"),
                 "webbing": srgb("14181b"), "shemagh": srgb("c8b493"),
                 "leather": srgb("1d1f21"), "skin": srgb("7d6448")},
        "accent": srgb("b03a26"),
    },
    # nobody: no armour, no rifle, no wrap -- the occupied population's own
    # clothes.  A coat, a hood and a satchel, which is a different vocabulary
    # of shapes rather than a soldier with the armour switches turned off, and
    # deliberately dark brown so they never read as the occupier.
    "civilian": {
        "armed": False,
        "proportion": {"stature": 0.96, "girth": 0.96, "shoulder": 0.97,
                       "head": 0.98},
        "kit": {"helmet": False, "goggles": False, "nvg": False, "carrier": False,
                "mag_pouches": False, "pouches": False, "backpack": False,
                "bedroll": False, "collar": False, "pads": False,
                "knee_pads": False, "gloves": False, "coat": True, "hood": True,
                "hair": True, "scarf": True, "satchel": True, "leg_wrap": True},
        "mats": {"cloth": srgb("4a4038"), "cloth_lt": srgb("2a2622"),
                 "webbing": srgb("2a2622"), "leather": srgb("7a5a2b"),
                 "skin": srgb("7d6144")},
        "accent": srgb("7a5a2b"),
    },
}

# One pass builds the whole cast.  Order matters only for the build log.
ALL_VARIANTS = ["player", "trooper", "heavy", "guard", "civilian"]


def build_character(variant: str):
    M = materials()
    spec = VARIANTS.get(variant, VARIANTS["trooper"])
    # pull variant overrides into fresh material copies so archetypes can differ
    for key, col in spec.get("mats", {}).items():
        base = M[key]
        M[key] = mat("%s_%s" % (key, variant), col,
                     roughness=base.node_tree.nodes["Principled BSDF"].inputs[
                         "Roughness"].default_value)
    M["accent"] = mat("accent_%s" % variant, spec.get("accent", (0.3, 0.16, 0.07)),
                      roughness=0.72)

    parts = build_body(M) + build_gear(M, spec["kit"])
    return M, parts


def join_parts(parts, name="Character"):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    joined.data.name = name + "Mesh"
    return joined


# --------------------------------------------------------------------------
# armature
# --------------------------------------------------------------------------

# (name, parent, head, tail, deform) -- built from the same table as the mesh,
# so the skeleton cannot drift away from the geometry it drives.
def bone_table():
    sx = A["shoulder_x"]
    hx = A["hip_x"]
    rows = [
        ("root", None, (0.0, 0.0, 0.0), (0.0, 0.26, 0.0), False),
        ("hips", "root", (0.0, 0.0, A["hip_z"]), (0.0, 0.0, A["waist_z"]), True),
        ("spine", "hips", (0.0, 0.0, A["waist_z"]), (0.0, 0.004, 1.245), True),
        ("chest", "spine", (0.0, 0.004, 1.245), (0.0, 0.004, A["neck_z"]), True),
        ("neck", "chest", (0.0, 0.004, A["neck_z"]), (0.0, 0.006, A["chin_z"]), True),
        ("head", "neck", (0.0, 0.006, A["chin_z"]), (0.0, 0.0, A["crown_z"]), True),
    ]
    for side in (-1.0, 1.0):
        tag = "L" if side < 0 else "R"
        s = float(side)
        rows += [
            ("shoulder_" + tag, "chest", (s * 0.048, 0.0, A["shoulder_z"] - 0.022),
             (s * sx, 0.0, A["shoulder_z"]), True),
            ("upperarm_" + tag, "shoulder_" + tag, (s * sx, 0.0, A["shoulder_z"]),
             (s * (sx + 0.044), 0.016, A["elbow_z"]), True),
            ("forearm_" + tag, "upperarm_" + tag,
             (s * (sx + 0.044), 0.016, A["elbow_z"]),
             (s * (sx + 0.056), 0.026, A["wrist_z"]), True),
            ("hand_" + tag, "forearm_" + tag, (s * (sx + 0.056), 0.026, A["wrist_z"]),
             (s * (sx + 0.058), 0.034, 0.760), True),
            ("thigh_" + tag, "hips", (s * hx, 0.0, A["hip_z"]),
             (s * (hx + 0.022), 0.010, A["knee_z"]), True),
            ("shin_" + tag, "thigh_" + tag, (s * (hx + 0.022), 0.010, A["knee_z"]),
             (s * (hx + 0.026), 0.0, A["ankle_z"] + 0.015), True),
            ("foot_" + tag, "shin_" + tag, (s * (hx + 0.026), 0.0, A["ankle_z"] + 0.015),
             (s * (hx + 0.026), 0.120, 0.034), True),
            ("toe_" + tag, "foot_" + tag, (s * (hx + 0.026), 0.120, 0.034),
             (s * (hx + 0.026), 0.176, 0.030), True),
        ]
    # The held weapon lives in *chest* space, not hand space.  Parenting it to
    # the hand makes the left hand's grip circular (the left hand has to find a
    # weapon that is itself following the right hand) and any recoil drags the
    # whole support arm with it.  Chest space means one authored transform per
    # clip, both arms solved onto it, and recoil that the arms absorb.
    # The rest pose points the weapon straight down +Y with local Z up, which
    # makes the pose euler readable: x = pitch (negative is muzzle down),
    # y = roll about the barrel, z = yaw (positive swings the muzzle left).
    # A rest direction that is merely *roughly* forward silently falls back to
    # the wrong roll reference and turns pitch into yaw.
    grip = Vector((0.035, 0.175, 1.256))
    rows.append(("weapon", "chest", tuple(grip), tuple(grip + Vector((0.0, 0.45, 0.0))),
                 False))
    return rows


def build_armature(name="Rig"):
    arm_data = bpy.data.armatures.new(name)
    arm = link(bpy.data.objects.new(name, arm_data))
    activate(arm)
    bpy.ops.object.mode_set(mode='EDIT')
    made = {}
    for bname, parent, head, tail, deform in bone_table():
        b = arm_data.edit_bones.new(bname)
        b.head = Vector(head)
        b.tail = Vector(tail)
        b.use_deform = deform
        # limbs and spine bend about X, so align roll to world +X where the
        # bone is not itself along X
        # Local Z points along the reference axis, so limb and spine bones bend
        # about local X and twist about local Y.  Bones that point along that
        # reference (feet, toes, the weapon, the root) would be degenerate, so
        # they use +Z instead.
        dirn = (Vector(tail) - Vector(head)).normalized()
        ref = (Vector((0.0, 0.0, 1.0))
               if abs(dirn.dot(Vector((0.0, 1.0, 0.0)))) > 0.8
               or abs(dirn.dot(Vector((1.0, 0.0, 0.0)))) > 0.8
               else Vector((0.0, -1.0, 0.0)))
        b.align_roll(ref)
        if parent:
            b.parent = made[parent]
            b.use_connect = (Vector(head) - made[parent].tail).length < 1e-5
        made[bname] = b
    bpy.ops.object.mode_set(mode='OBJECT')
    for pb in arm.pose.bones:
        pb.rotation_mode = 'XYZ'
    return arm


def skin(body, arm):
    """Bind with bone heat, falling back to distance weights if it fails.

    Heat weighting gives the nicest falloff but needs a manifold-ish mesh; a
    soldier built from dozens of overlapping gear shells often has no solution,
    so the distance solver is the safety net rather than an afterthought.
    """
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    body.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    try:
        bpy.ops.object.parent_set(type='ARMATURE_AUTO')
        ok = any(m.type == 'ARMATURE' for m in body.modifiers)
        if ok:
            print("   skin: heat weighting")
            return "heat"
    except RuntimeError as exc:
        print("   skin: heat failed (%s), using distance weights" % exc)
    return skin_by_distance(body, arm)


def _segments(arm):
    segs = []
    for b in arm.data.bones:
        if b.use_deform:
            segs.append((b.name, Vector(b.head_local), Vector(b.tail_local)))
    return segs


def _dist_to_seg(p, a, b):
    ab = b - a
    denom = ab.length_squared
    t = 0.0 if denom < 1e-9 else max(0.0, min(1.0, (p - a).dot(ab) / denom))
    return (p - (a + ab * t)).length


def skin_by_distance(body, arm):
    segs = _segments(arm)
    body.vertex_groups.clear()
    groups = {n: body.vertex_groups.new(name=n) for n, _, _ in segs}
    for v in body.data.vertices:
        p = v.co
        d = sorted(((_dist_to_seg(p, a, b), n) for n, a, b in segs))[:3]
        # inverse-square falloff across the three nearest bones, then normalise
        w = [(1.0 / max(dist, 1e-4) ** 2, n) for dist, n in d]
        total = sum(x for x, _ in w)
        for x, n in w:
            if x / total > 0.02:
                groups[n].add([v.index], x / total, 'REPLACE')
    m = body.modifiers.new("Armature", 'ARMATURE')
    m.object = arm
    body.parent = arm
    print("   skin: distance weighting (%d bones)" % len(segs))
    return "distance"


def pose_test(arm):
    """A deliberately extreme pose: if any weight is wrong it shows up as a
    collapsed joint or a spike, which is much cheaper to spot than a whole
    animation that subtly looks off."""
    poses = {
        "upperarm_L": (0.0, 0.0, -1.15), "forearm_L": (-1.35, 0.0, 0.0),
        "upperarm_R": (-0.45, 0.0, 0.30), "forearm_R": (-1.10, 0.0, 0.0),
        "thigh_L": (-0.95, 0.0, 0.0), "shin_L": (1.25, 0.0, 0.0),
        "thigh_R": (0.35, 0.0, 0.0), "shin_R": (0.30, 0.0, 0.0),
        "foot_L": (0.35, 0.0, 0.0),
        "spine": (0.14, 0.0, 0.0), "chest": (0.10, -0.35, 0.0),
        "neck": (-0.16, 0.30, 0.0), "head": (0.0, 0.25, 0.0),
    }
    for name, rot in poses.items():
        pb = arm.pose.bones.get(name)
        if pb is not None:
            pb.rotation_euler = rot
    bpy.context.view_layer.update()


def clean_weights(body):
    """Cap influences at four and renormalise, which is all the skin shader
    consumes anyway."""
    activate(body)
    try:
        bpy.ops.object.vertex_group_limit_total(limit=4)
        bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    except RuntimeError as exc:
        print("   ! weight cleanup skipped: %s" % exc)


def fill_unweighted(body, arm) -> int:
    """Heat weighting leaves interior or isolated shell vertices with no
    influence at all.  Those do not just deform badly, they stay pinned at the
    bind pose and drag a spike of stretched geometry behind the limb, so they
    are patched with the distance solver instead of being tolerated."""
    segs = _segments(arm)
    groups = {}
    for name, _, _ in segs:
        groups[name] = body.vertex_groups.get(name) or body.vertex_groups.new(name=name)
    patched = 0
    for v in body.data.vertices:
        if sum(g.weight for g in v.groups) >= 1e-3:
            continue
        p = v.co
        d = sorted(((_dist_to_seg(p, a, b), n) for n, a, b in segs))[:2]
        w = [(1.0 / max(dist, 1e-4) ** 2, n) for dist, n in d]
        total = sum(x for x, _ in w)
        for x, n in w:
            groups[n].add([v.index], x / total, 'REPLACE')
        patched += 1
    print("   weights: patched %d unweighted vertices" % patched)
    return patched


def audit_weights(body) -> float:
    """Any vertex with no influence stays at its rest position while the rest of
    the limb moves, which reads on screen as a spike.  Report the worst case."""
    loose = 0
    for v in body.data.vertices:
        total = sum(g.weight for g in v.groups)
        if total < 1e-3:
            loose += 1
    pct = 100.0 * loose / max(1, len(body.data.vertices))
    print("   weights: %d/%d unweighted (%.2f%%)" % (loose, len(body.data.vertices), pct))
    return pct


# --------------------------------------------------------------------------
# animation
# --------------------------------------------------------------------------
#
# Bone rotation conventions established by the roll above:
#   limb bones point down -> +x swings backward, -x forward, y twists, z abducts
#   spine/neck/head point up -> -x leans forward, y twists (yaw), z side-bends
#   feet point forward -> +x is toe-up, -x is toe-down
# The action is authored as pure FK: legs and torso from phase functions, both
# arms solved numerically onto the weapon, so nothing depends on Blender's
# constraint solver or on a bake step that can silently produce garbage.

FPS = 24


def R(x=0.0, y=0.0, z=0.0):
    return (math.radians(x), math.radians(y), math.radians(z))


def vstr(v: Vector) -> str:
    return "(%.3f, %.3f, %.3f)" % (v.x, v.y, v.z)


# Rifle attitude, authored in chest space.  These are not arbitrary: the
# angles are chosen so the *left* hand can actually reach the foregrip.
# A butt-at-the-shoulder stance puts the foregrip 0.70 m from the left shoulder
# and the arm only reaches ~0.57 m, so the low ready is carried across the body
# (the real "modified low ready") which brings it back inside reach at ~0.51 m.
WEAPON_CARRY = (R(-29.0, 0.0, 31.0), Vector((0.0, 0.0, 0.0)))
WEAPON_AIM_ROT = R(-6.0, 0.0, 3.0)
WEAPON_AIM_LOC = Vector((0.118, 0.052, 0.104))


# How far the support hand sits from its own shoulder when the rifle is
# shouldered, as a fraction of that arm's length.  Taken from the base build,
# where the pose was tuned by hand.
AIM_REACH_RATIO = 0.881

# Solved per archetype from the arm that actually exists (see solve_aim_offset).
AIM_LOC = None


def arm_lengths(arm, tag):
    b_ua = arm.data.bones["upperarm_" + tag]
    b_fa = arm.data.bones["forearm_" + tag]
    return ((b_ua.tail_local - b_ua.head_local).length,
            (b_fa.tail_local - b_fa.head_local).length)


def _foregrip_distance(arm, loc) -> float:
    """How far the support shoulder is from the foregrip at this mount offset."""
    place_weapon(arm, (WEAPON_AIM_ROT, loc))
    origin, fwd, up = weapon_frame(arm)
    fore = origin + fwd * 0.205 - up * 0.008
    return (fore - arm.pose.bones["upperarm_L"].head).length


def solve_aim_offset(arm) -> Vector:
    """Shouldered mount offset that keeps the support hand on the foregrip.

    The base aim pose sits deliberately near the limit of the left arm's reach
    (0.51 m of a 0.58 m arm), so it is exactly the pose that a wider body
    breaks: a heavy's shoulders are 6 cm further out and the hand ends up 7 cm
    short of a rifle that did not move.  Hand-tuning a second offset against a
    second body is how four archetypes quietly become four poses that all need
    re-tuning, so the offset is solved for instead, against the arm that is
    actually in the file.  One-dimensional, deterministic, and printed.
    """
    l1, l2 = arm_lengths(arm, "L")
    target = (l1 + l2) * AIM_REACH_RATIO
    base = shape_chest_offset(WEAPON_AIM_LOC)
    best, best_err = base, 1e9
    dx = -0.34
    while dx <= 0.161:
        loc = base + Vector((dx, 0.0, 0.0))
        err = abs(_foregrip_distance(arm, loc) - target)
        if err < best_err:
            best_err, best = err, loc
        dx += 0.005
    return best


def weapon_aim():
    """The shouldered attitude, with its mount offset solved for this body."""
    if AIM_LOC is None:
        return WEAPON_AIM_ROT, shape_chest_offset(WEAPON_AIM_LOC)
    return WEAPON_AIM_ROT, AIM_LOC


def mount_shift() -> Vector:
    """How far the solved shouldered mount sits from the authored one.

    The reload and the butt stroke are the same cross-body geometry as the aim
    -- both hands forward of a wide chest -- so they inherit the solved
    correction rather than each growing its own hand-tuned offset that has to
    be re-tuned again for every new archetype.
    """
    if AIM_LOC is None:
        return Vector((0.0, 0.0, 0.0))
    return AIM_LOC - shape_chest_offset(WEAPON_AIM_LOC)


def set_pose(arm, name, rot):
    pb = arm.pose.bones.get(name)
    if pb is not None:
        pb.rotation_euler = rot


def _world_head(arm, name) -> Vector:
    return arm.matrix_world @ arm.pose.bones[name].head


def _world_tail(arm, name) -> Vector:
    return arm.matrix_world @ arm.pose.bones[name].tail


def bone_matrix(head: Vector, y_dir: Vector, up_hint: Vector) -> Matrix:
    """A bone's pose matrix: local Y along the bone, local Z towards the hint."""
    y = Vector(y_dir).normalized()
    z = Vector(up_hint) - y * Vector(up_hint).dot(y)
    if z.length < 1e-5:
        z = Vector((0.0, 0.0, 1.0)) - y * y.z
    z.normalize()
    x = y.cross(z)
    return Matrix(((x.x, y.x, z.x, head.x),
                   (x.y, y.y, z.y, head.y),
                   (x.z, y.z, z.z, head.z),
                   (0.0, 0.0, 0.0, 1.0)))


def two_bone_ik(root: Vector, target: Vector, l1: float, l2: float, pole: Vector):
    """Elbow and (clamped) wrist for a two-bone chain reaching for `target`.

    The elbow rides a circle around the root->target axis; `pole` picks where on
    that circle, which is what decides whether the arm reads as a rifle carry
    or as a chicken wing.
    """
    delta = Vector(target) - Vector(root)
    dist = delta.length
    if dist < 1e-6:
        delta = Vector((0.0, 0.0, -1.0))
        dist = 1e-6
    limit_lo = abs(l1 - l2) + 1e-4
    limit_hi = l1 + l2 - 1e-4
    dist = max(limit_lo, min(dist, limit_hi))
    axis = delta.normalized()
    cos_a = (l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist)
    angle = math.acos(max(-1.0, min(1.0, cos_a)))
    radial = Vector(pole) - axis * Vector(pole).dot(axis)
    if radial.length < 1e-5:
        radial = axis.cross(Vector((0.0, 0.0, 1.0)))
        if radial.length < 1e-5:
            radial = axis.cross(Vector((0.0, 1.0, 0.0)))
    radial.normalize()
    elbow = root + (axis * math.cos(angle) + radial * math.sin(angle)) * l1
    return elbow, root + axis * dist


def solve_arm(arm, tag, wrist_target: Vector, elbow_hint: Vector,
              seed=None, iters=0):
    """Exact two-bone IK for the arm, in armature space.

    Coordinate descent on the joint angles was the first attempt and it stalled
    in local minima, leaving the wrist 5-11 cm off the grip -- that is the
    difference between holding a rifle and hovering near one.  Solving the
    triangle directly places the wrist exactly and puts the elbow wherever the
    pole hint asks, with no convergence step to get stuck in.
    """
    ua, fa, hn = "upperarm_" + tag, "forearm_" + tag, "hand_" + tag
    bpy.context.view_layer.update()
    b_ua, b_fa = arm.data.bones[ua], arm.data.bones[fa]
    l1 = (b_ua.tail_local - b_ua.head_local).length
    l2 = (b_fa.tail_local - b_fa.head_local).length
    root = arm.pose.bones[ua].head.copy()
    elbow, wrist = two_bone_ik(root, wrist_target, l1, l2, elbow_hint)

    hand_dir = wrist - elbow
    if hand_dir.length < 1e-5:
        hand_dir = elbow_hint - elbow
    for name, head, direction in ((ua, root, elbow - root),
                                  (fa, elbow, wrist - elbow),
                                  (hn, wrist, hand_dir)):
        if direction.length < 1e-6:
            continue
        arm.pose.bones[name].matrix = bone_matrix(head, direction, elbow_hint)
        bpy.context.view_layer.update()

    err = (arm.pose.bones[hn].head - wrist_target).length
    if err > 0.045:
        print("   ! arm %s out of reach by %.3f m (target %s, got %s)"
              % (tag, err, vstr(wrist_target), vstr(arm.pose.bones[hn].head)))
    return err


LEG_ANKLE_Z = 0.110


def leg_lengths(arm):
    b_t = arm.data.bones["thigh_L"]
    b_s = arm.data.bones["shin_L"]
    return ((b_t.tail_local - b_t.head_local).length,
            (b_s.tail_local - b_s.head_local).length)


def place_leg(arm, tag, ankle: Vector, foot_pitch: float, side: float) -> None:
    """Two-bone IK for one leg plus a pitched sole.

    Authoring footfalls as world-space ankle positions is the only way contact
    is guaranteed: an FK leg driven by joint angles cannot know where the floor
    is, which is how the crouch ended up with the boots 20 cm under the ground.
    `foot_pitch` is radians, positive is toe-up, so heel strike and toe-off are
    explicit rather than emergent.
    """
    th, sh, ft = "thigh_" + tag, "shin_" + tag, "foot_" + tag
    l1, l2 = leg_lengths(arm)
    # pose_bone.head is stale until the depsgraph has run: without this the
    # first leg solved against the *rest* hip position and reached 34 cm low,
    # while the second leg, refreshed by the first one's update, looked fine.
    bpy.context.view_layer.update()
    root = arm.pose.bones[th].head.copy()
    pole = Vector((side * 0.30, 1.0, 0.0))
    knee, ankle_pt = two_bone_ik(root, ankle, l1, l2, pole)
    rest_dir = (arm.data.bones[ft].tail_local - arm.data.bones[ft].head_local)
    foot_dir = Matrix.Rotation(foot_pitch, 3, 'X') @ rest_dir
    for name, head, direction, hint in (
            (th, root, knee - root, pole),
            (sh, knee, ankle_pt - knee, pole),
            (ft, ankle_pt, foot_dir, Vector((0.0, 0.0, 1.0)))):
        if direction.length < 1e-6:
            continue
        arm.pose.bones[name].matrix = bone_matrix(head, direction, hint)
        bpy.context.view_layer.update()
    err = (arm.pose.bones[ft].head - Vector(ankle)).length
    if err > 0.02:
        print("   ! leg %s missed: err %.3f root %s target %s got %s"
              % (tag, err, vstr(root), vstr(Vector(ankle)),
                 vstr(arm.pose.bones[ft].head)))


def foot_track(p: float, stride: float, lift: float):
    """Ankle offset forward of the hip and height above the floor, for one
    foot.  `p` 0 is heel strike; the stance foot travels backwards under the
    body (an in-place cycle stands in for forward travel) and then swings."""
    half = stride * 0.5
    if p < 0.5:
        return half - stride * (p / 0.5), 0.0
    s = (p - 0.5) / 0.5
    return -half + stride * s, lift * math.sin(math.pi * s)


def foot_pitch_for(p: float, cfg: dict) -> float:
    """Heel strike, roll flat through mid-stance, drive off the toe, then lift
    the toe clear during swing."""
    heel = math.radians(cfg.get("heel", 9.0))
    toe = math.radians(cfg.get("toe_off", 30.0))
    swing = math.radians(cfg.get("toe_up", 11.0))
    if p < 0.5:
        u = p / 0.5
        return heel * max(0.0, 1.0 - u / 0.30) - toe * max(0.0, (u - 0.55) / 0.45) ** 1.4
    u = (p - 0.5) / 0.5
    return -toe * max(0.0, 1.0 - u / 0.25) + swing * math.sin(math.pi * u) ** 0.8


# Sole contact points relative to the ankle, in armature space: the heel and
# toe corners of the boot sole, which sits 0.110 below the ankle.
SOLE_HEEL = Vector((-0.0315, -0.110))
SOLE_TOE = Vector((0.2035, -0.110))


def ankle_height_for_pitch(pitch: float) -> float:
    """Ankle height that leaves the sole's *contact point* on the floor.

    A foot pivots about the heel when the toe comes up and about the toe when
    the heel comes up; it does not pivot about the ankle.  Holding the ankle at
    floor height while pitching the toe down drove the boot 5 cm through the
    ground at every push-off.
    """
    c, s = math.cos(pitch), math.sin(pitch)
    pt = SOLE_TOE if pitch < 0.0 else SOLE_HEEL
    return -(pt.x * s + pt.y * c) * P["stature"]


def hips_height(arm, max_fwd: float) -> float:
    """Hip height that keeps the most-extended planted leg inside its reach.
    A 0.70 m stride simply cannot be reached with the pelvis at standing
    height, which is why real walks drop the pelvis at double support."""
    l1, l2 = leg_lengths(arm)
    reach = (l1 + l2) * 0.995
    span = math.sqrt(max(reach * reach - max_fwd * max_fwd, 0.04))
    return LEG_ANKLE_Z * P["stature"] + span


def apply_legs(arm, phase: float, cfg: dict) -> None:
    """Both legs, half a cycle apart, ground-locked through stance."""
    if cfg.get("stance_only"):
        for side in (-1.0, 1.0):
            tag = "L" if side < 0 else "R"
            set_pose(arm, "toe_" + tag, R(2.0, 0.0, 0.0))
            place_leg(arm, tag,
                      shape_point(Vector((side * 0.098, 0.010, LEG_ANKLE_Z))),
                      0.0, side)
        return
    stride = cfg.get("stride", 0.62)
    lift = cfg.get("lift", 0.105)
    for side in (-1.0, 1.0):
        tag = "L" if side < 0 else "R"
        p = phase if side < 0 else (phase + 0.5) % 1.0
        fwd, h = foot_track(p, stride, lift)
        pitch = foot_pitch_for(p, cfg)
        set_pose(arm, "toe_" + tag, R(2.0, 0.0, 0.0))
        # `fwd` and `h` already carry the archetype's stride and lift; only the
        # lateral offset is hip width, so only that is scaled here.
        place_leg(arm, tag,
                  Vector((side * 0.104 * P["girth"], fwd,
                          ankle_height_for_pitch(pitch) + h)),
                  pitch, side)


def rest_hip_z(arm) -> float:
    """Rest height of the pelvis, in armature space.

    Read off the armature rather than the anatomy table.  The table is the
    *base* build, and a shaped archetype's pelvis is not at the base height, so
    using it as the reference pushed a heavy's pelvis 5.6 cm too high and left
    the legs permanently reaching for a floor they could not touch.
    """
    return arm.data.bones["hips"].head_local.z


def hips_offset(arm, world_delta: Vector) -> Vector:
    """Pose-bone `location` is in the bone's own space, not world space.  The
    hips bone points up, so its local Y is world up and its local Z is world
    -Y: writing a vertical offset into .z pushes the character backwards.
    Converting explicitly removes the whole class of bug.
    """
    m = arm.data.bones["hips"].matrix_local.to_3x3()
    return m.inverted() @ world_delta


def apply_torso(arm, phase: float, cfg: dict) -> None:
    """Hip bob/sway/yaw with the shoulders counter-rotating against them."""
    bob = cfg.get("bob", 0.024)
    sway = cfg.get("sway", 0.012)
    yaw = cfg.get("hip_yaw", 7.0)
    lean = cfg.get("lean", 5.0)
    crouch = cfg.get("crouch", 0.0)
    breathe = cfg.get("breathe", 0.0)
    t = phase * 2.0 * math.pi

    hips = arm.pose.bones["hips"]
    # Hip height comes from the planted feet (see _locomotion), so the pelvis
    # rises at mid-stance and drops at double support without a separate bob
    # curve to drift out of agreement with the legs.
    rest_z = rest_hip_z(arm)
    target_z = cfg.get("hips_z", rest_z)
    world_delta = Vector((sway * math.sin(t), 0.0, target_z - rest_z))
    hips.location = hips_offset(arm, world_delta)
    hips.rotation_euler = R(0.0, yaw * math.sin(t), -sway * 60.0 * math.sin(t))
    set_pose(arm, "spine", R(-lean * 0.45 - crouch * 9.0 + breathe * 1.2,
                             -yaw * 0.30 * math.sin(t),
                             math.sin(t) * 1.6))
    set_pose(arm, "chest", R(-lean * 0.55 - crouch * 5.0 + breathe * 1.6,
                             -yaw * 0.45 * math.sin(t), 0.0))
    set_pose(arm, "neck", R(lean * 0.30 + crouch * 4.0 - breathe * 0.8,
                            yaw * 0.25 * math.sin(t), 0.0))
    set_pose(arm, "head", R(0.0, yaw * 0.20 * math.sin(t), 0.0))


def weapon_frame(arm):
    """Origin, forward and up of the posed weapon bone, in armature space.
    Armature space is what `pose_bone.matrix` and the IK below work in; mixing
    it with world space only works while the armature sits at the origin, which
    is exactly the kind of assumption that breaks later.
    """
    wb = arm.pose.bones["weapon"]
    origin = wb.head.copy()
    fwd = wb.matrix.col[1].xyz.normalized()
    up = wb.matrix.col[2].xyz.normalized()
    return origin, fwd, up


def place_weapon(arm, spec) -> None:
    rot, offset = spec
    wb = arm.pose.bones["weapon"]
    wb.rotation_euler = rot
    wb.location = offset
    bpy.context.view_layer.update()


def smoothstep(u: float) -> float:
    u = max(0.0, min(1.0, u))
    return u * u * (3.0 - 2.0 * u)


def keyed(t: float, keys) -> Vector:
    """Piecewise smoothstep through world-space keys, for hand paths."""
    if t <= keys[0][0]:
        return Vector(keys[0][1])
    for i in range(len(keys) - 1):
        t0, v0 = keys[i]
        t1, v1 = keys[i + 1]
        if t <= t1:
            return Vector(v0).lerp(Vector(v1), smoothstep((t - t0) / max(t1 - t0, 1e-6)))
    return Vector(keys[-1][1])


def pose_arms_on_weapon(arm, state, wrist_pull=0.050, fore_reach=0.245,
                        support=True, left_target=None):
    """Solve both arms onto the weapon.  `state` carries the previous frame's
    solution so the arms stay continuous across frames instead of re-solving
    into a different elbow each key."""
    origin, fwd, up = weapon_frame(arm)
    grip = origin - fwd * wrist_pull + up * 0.020
    fore = origin + fwd * fore_reach - up * 0.008

    err_r = solve_arm(arm, "R", grip, grip + Vector((0.130, -0.100, -0.130)),
                      seed=state.get("seed_R"))
    state["seed_R"] = {k: list(arm.pose.bones[k].rotation_euler)
                       for k in ("shoulder_R", "upperarm_R", "forearm_R")}
    if not support:
        return err_r, 0.0
    # `left_target` lets a clip take the support hand off the rifle entirely
    # (a magazine change) without touching the right hand's grip.
    if left_target is None:
        target_l = fore
        hint_l = fore + Vector((-0.060, -0.060, -0.200))
    else:
        target_l = Vector(left_target)
        hint_l = target_l + Vector((-0.115, -0.045, -0.145))
    err_l = solve_arm(arm, "L", target_l, hint_l, seed=state.get("seed_L"))
    state["seed_L"] = {k: list(arm.pose.bones[k].rotation_euler)
                       for k in ("shoulder_L", "upperarm_L", "forearm_L")}
    return err_r, err_l


# ------------------------------------------------------------------ clips

# `stride` is metres of foot travel per cycle (the distance one foot covers
# between contacts), `lift` is peak ankle height in swing, and `crouch_drop`
# lowers the pelvis, which the leg IK then absorbs by folding the knees.
IDLE_CFG = {"sway": 0.010, "hip_yaw": 1.2, "lean": 2.0}
WALK_CFG = {"stride": 0.62, "lift": 0.105, "heel": 9.0, "toe_off": 30.0,
            "toe_up": 11.0, "sway": 0.011, "hip_yaw": 7.0, "lean": 5.0}
RUN_CFG = {"stride": 0.80, "lift": 0.220, "heel": 4.0, "toe_off": 38.0,
           "toe_up": 16.0, "sway": 0.007, "hip_yaw": 10.0, "lean": 14.0,
           "crouch_drop": 0.035}
CROUCH_IDLE_CFG = {"sway": 0.006, "hip_yaw": 1.0, "lean": 4.0,
                   "crouch_drop": 0.335}
CROUCH_WALK_CFG = {"stride": 0.34, "lift": 0.060, "heel": 4.0, "toe_off": 18.0,
                   "toe_up": 7.0, "sway": 0.008, "hip_yaw": 4.0, "lean": 4.0,
                   "crouch_drop": 0.335}
AIM_CFG = {"sway": 0.006, "hip_yaw": 3.0, "lean": 7.0}


def stance_cfg(arm, cfg: dict) -> dict:
    """Hip height for a two-footed stance, minus any crouch drop."""
    out = dict(cfg)
    out["hips_z"] = (hips_height(arm, 0.012) - out.get("crouch_drop", 0.0))
    return out


def _locomotion(arm, t, st, cfg, legs=True):
    cfg = shaped_cfg(cfg)
    stride = cfg.get("stride", 0.0)
    if not legs:
        cfg = stance_cfg(arm, cfg)
    else:
        # Hip height from whichever feet are actually planted this frame: this
        # is what gives a walk its 2-per-cycle bob for free, and it cannot
        # disagree with the legs because the legs are what it is computed from.
        planted = []
        for side in (-1.0, 1.0):
            p = t if side < 0 else (t + 0.5) % 1.0
            fwd, h = foot_track(p, stride, cfg.get("lift", 0.105))
            if h < 1e-4:
                planted.append(abs(fwd))
        cfg["hips_z"] = (hips_height(arm, max(planted) if planted else 0.020)
                         - cfg.get("crouch_drop", 0.0))
    apply_torso(arm, t, cfg)
    apply_legs(arm, t, cfg if legs else dict(cfg, stance_only=True))
    return carry_pose(arm, st)


def clip_idle(arm, t, st):
    cfg = dict(IDLE_CFG)
    cfg["breathe"] = math.sin(2.0 * math.pi * t)
    return _locomotion(arm, t, st, cfg, legs=False)


def clip_walk(arm, t, st):
    return _locomotion(arm, t, st, WALK_CFG)


def clip_run(arm, t, st):
    return _locomotion(arm, t, st, RUN_CFG)


def clip_crouch_idle(arm, t, st):
    cfg = dict(CROUCH_IDLE_CFG)
    cfg["breathe"] = math.sin(2.0 * math.pi * t)
    return _locomotion(arm, t, st, cfg, legs=False)


def clip_crouch_walk(arm, t, st):
    return _locomotion(arm, t, st, CROUCH_WALK_CFG)


def _aim_clip(arm, t, st, rot, loc):
    cfg = stance_cfg(arm, AIM_CFG)
    apply_torso(arm, t, cfg)
    apply_legs(arm, t, dict(cfg, stance_only=True))
    place_weapon(arm, (rot, loc))
    return pose_arms_on_weapon(arm, st, wrist_pull=0.040, fore_reach=0.205)


def clip_aim_idle(arm, t, st):
    # sight picture drifts, and the arms follow it rather than the reverse
    wobble = R(-6.0 + 1.1 * math.sin(2.0 * math.pi * t),
               0.7 * math.sin(2.0 * math.pi * t + 1.1),
               3.0 + 0.5 * math.sin(2.0 * math.pi * t + 2.2))
    return _aim_clip(arm, t, st, wobble, weapon_aim()[1])


def clip_fire(arm, t, st):
    """Shouldered, with the rifle driving back and up into the shoulder."""
    kick = math.exp(-7.0 * t) * math.sin(14.0 * t)
    rot = R(-6.0 + 7.5 * kick, 2.0 * kick, 3.0 + 1.5 * kick)
    loc = weapon_aim()[1] + Vector((0.0, -0.055 * kick, 0.012 * kick))
    return _aim_clip(arm, t, st, rot, loc)


# Magazine pouch on the left hip, in armature space -- the reload path starts
# and ends here, and it is read straight off build_gear's pouch placement.
BELT_MAG = Vector((-0.135, 0.075, 0.975))


def belt_mag() -> Vector:
    """The pouch, moved onto this archetype's hip."""
    return shape_point(BELT_MAG)


def clip_hit(arm, t, st):
    """Took a round: the torso whips back, the head snaps, the rifle jolts."""
    flinch = math.exp(-5.0 * t) * math.cos(9.0 * t)
    cfg = stance_cfg(arm, IDLE_CFG)
    cfg["hips_z"] -= 0.022 * max(0.0, flinch)
    cfg["lean"] = 2.0 - 7.0 * flinch
    apply_torso(arm, t, cfg)
    apply_legs(arm, t, dict(cfg, stance_only=True))
    set_pose(arm, "neck", R(4.0 - 9.0 * flinch, -4.0 * flinch, 0.0))
    rot = R(-29.0 + 4.0 * flinch, 6.0 * flinch, 31.0 + 5.0 * flinch)
    loc = Vector((0.0, -0.030 * flinch, 0.012 * flinch))
    place_weapon(arm, (rot, loc))  # a flinch, not a mount: no shoulder shift
    return pose_arms_on_weapon(arm, st)


def clip_reload(arm, t, st):
    """Magazine out, magazine in.  The support hand leaves the rifle, which is
    the whole reason the arms are solved onto the weapon rather than baked."""
    cfg = stance_cfg(arm, IDLE_CFG)
    cfg["lean"] = 4.0
    # the rifle dips and rolls towards the shooter while the hand is away
    dip = math.exp(-9.0 * max(0.0, t - 0.72) ** 2)
    rot = R(-29.0 - 9.0 * math.sin(math.pi * min(t / 0.75, 1.0)) + 6.0 * dip,
            0.0, 31.0 - 13.0 * math.sin(math.pi * min(t / 0.75, 1.0)))
    loc = mount_shift() + Vector((0.0, -0.010 * dip,
                                  -0.020 * math.sin(math.pi * min(t / 0.75, 1.0))))
    apply_torso(arm, t, cfg)
    apply_legs(arm, t, dict(cfg, stance_only=True))
    set_pose(arm, "neck", R(6.0 + 7.0 * math.sin(math.pi * min(t / 0.6, 1.0)), 0.0, 0.0))
    place_weapon(arm, (rot, loc))
    origin, fwd, up = weapon_frame(arm)
    fore = origin + fwd * 0.245 - up * 0.008
    mag = belt_mag()
    hand = keyed(t, [
        (0.00, fore),
        (0.10, fore + Vector((0.0, -0.05, -0.06))),
        (0.34, mag + Vector((0.0, 0.05, 0.03))),
        (0.46, mag + Vector((0.0, -0.02, 0.01))),
        (0.62, origin + fwd * 0.02 - up * 0.075),
        (0.72, origin + fwd * 0.02 - up * 0.030),
        (0.86, fore + Vector((0.0, -0.03, -0.03))),
        (1.00, fore),
    ])
    return pose_arms_on_weapon(arm, st, left_target=hand)


def pose_arms_relaxed(arm):
    """Arms hanging, hands empty.

    A civilian plays the same locomotion clips as everyone else, so its arms
    cannot be solved onto a rifle that is not there -- nor onto one that is
    slung, which would read as a soldier at rest.  The rig's rest pose is
    already arms-down, so this is a splay and a forearm bend on top of it.
    """
    for side, tag in ((-1.0, "L"), (1.0, "R")):
        set_pose(arm, "shoulder_" + tag, R(0.0, 0.0, 0.0))
        set_pose(arm, "upperarm_" + tag, R(-4.0, 0.0, side * 3.5))
        set_pose(arm, "forearm_" + tag, R(-13.0, 0.0, 0.0))
        set_pose(arm, "hand_" + tag, R(0.0, 0.0, 0.0))
    return 0.0, 0.0


def carry_pose(arm, st):
    """Locomotion arms: on the rifle, or hanging for an unarmed archetype."""
    place_weapon(arm, WEAPON_CARRY)
    if not P["armed"]:
        return pose_arms_relaxed(arm)
    return pose_arms_on_weapon(arm, st)


def clip_death(arm, t, st):
    """Backwards onto the ground.  The body pivots about the root, which is the
    one bone whose local axes are world-aligned, so the fall can be authored as
    a plain pitch plus a height."""
    fall = smoothstep(min(t / 0.55, 1.0))
    settle = smoothstep(max(0.0, (t - 0.55) / 0.45))
    root = arm.pose.bones["root"]
    root.rotation_euler = R(88.0 * fall, 0.0, -12.0 * fall)
    root.location = Vector((0.0, -0.10 * fall * P["stature"],
                            0.170 * fall * P["stature"]))
    set_pose(arm, "hips", R(-8.0 * fall, 0.0, 0.0))
    set_pose(arm, "spine", R(6.0 * fall - 4.0 * settle, 0.0, 3.0 * fall))
    set_pose(arm, "chest", R(9.0 * fall, 0.0, 5.0 * fall))
    set_pose(arm, "neck", R(-14.0 * fall + 6.0 * settle, 0.0, 0.0))
    set_pose(arm, "head", R(-8.0 * fall, 0.0, 0.0))
    for side in (-1.0, 1.0):
        tag = "L" if side < 0 else "R"
        set_pose(arm, "thigh_" + tag, R(-34.0 * fall - 16.0 * settle, 0.0, 0.0))
        set_pose(arm, "shin_" + tag, R(58.0 * fall + 28.0 * settle, 0.0, 0.0))
        set_pose(arm, "foot_" + tag, R(-14.0 * fall, 0.0, 0.0))
        set_pose(arm, "toe_" + tag, R(2.0, 0.0, 0.0))
    set_pose(arm, "shoulder_L", R(0.0, 0.0, 22.0 * fall))
    set_pose(arm, "shoulder_R", R(0.0, 0.0, -18.0 * fall))
    set_pose(arm, "upperarm_L", R(26.0 * fall, 0.0, 34.0 * fall))
    set_pose(arm, "forearm_L", R(-38.0 * fall, 0.0, 0.0))
    set_pose(arm, "upperarm_R", R(-14.0 * fall, 0.0, -46.0 * fall))
    set_pose(arm, "forearm_R", R(-62.0 * fall, 0.0, 0.0))
    # the rifle stays loosely in the right hand as it drops
    place_weapon(arm, (R(-29.0 + 30.0 * fall, 12.0 * fall, 31.0 - 20.0 * fall),
                       Vector((0.0, -0.03 * fall, -0.05 * fall))))
    return 0.0, 0.0


def clip_melee(arm, t, st):
    """Rifle-butt stroke: wind up, drive through, recover."""
    if t < 0.30:
        s = smoothstep(t / 0.30)
    elif t < 0.50:
        s = 1.0
    else:
        s = 1.0 - smoothstep((t - 0.50) / 0.50)
    wind = smoothstep(min(t / 0.30, 1.0)) - s
    cfg = stance_cfg(arm, IDLE_CFG)
    cfg["lean"] = 3.0 + 7.0 * s
    cfg["hip_yaw"] = 4.0 + 16.0 * s
    apply_torso(arm, t, cfg)
    apply_legs(arm, t, dict(cfg, stance_only=True))
    set_pose(arm, "chest", R(-4.0 - 6.0 * s, -10.0 * s, 0.0))
    rot = R(-29.0 - 46.0 * s + 10.0 * wind, -8.0 * s, 31.0 - 18.0 * s)
    loc = mount_shift() + Vector((0.0, 0.055 * s, 0.030 * s))
    place_weapon(arm, (rot, loc))
    return pose_arms_on_weapon(arm, st, fore_reach=0.245 - 0.045 * s)


# ------------------------------------------------------------------ bake


def contact_z(arm) -> float:
    """Lowest point of either boot, in armature space.  The sole sits 0.030
    below the toe bone, so a planted foot reports ~0.030 and anything lower is
    the boot going through the floor."""
    return min(min(arm.pose.bones["foot_" + t2].tail.z,
                   arm.pose.bones["toe_" + t2].tail.z) for t2 in ("L", "R"))


def bake_clip(arm, name, nframes, fn, loop=True, grounded=True):
    if arm.animation_data is None:
        arm.animation_data_create()
    act = bpy.data.actions.new(name)
    arm.animation_data.action = act
    names = [pb.name for pb in arm.pose.bones]
    state, grip, ground = {}, [], []
    for i in range(nframes):
        t = i / float(nframes - 1)
        err = fn(arm, t, state)
        if err:
            grip.extend([e for e in err if e])
        ground.append(contact_z(arm))
        if i == 0 and flag("--diag"):
            pb = arm.pose.bones
            print("   diag %s hips=%.3f thigh=%.3f knee=%.3f footL=%.3f toeL=%.3f footR=%.3f toeR=%.3f"
                  % (name, pb["hips"].head.z, pb["thigh_L"].tail.z, pb["shin_L"].tail.z,
                     pb["foot_L"].tail.z, pb["toe_L"].tail.z,
                     pb["foot_R"].tail.z, pb["toe_R"].tail.z))
        frame = i + 1
        for n in names:
            arm.pose.bones[n].keyframe_insert("rotation_euler", frame=frame)
        arm.pose.bones["hips"].keyframe_insert("location", frame=frame)
    act.use_fake_user = True
    # park each clip on its own muted NLA track so the exporter emits one glTF
    # animation per clip instead of only the last action assigned
    arm.animation_data.action = None
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 1, act)
    track.mute = True
    if grounded:
        print("   clip %-12s frames=%-4d grip %.3f m | ground %.3f..%.3f"
              % (name, nframes, max(grip) if grip else 0.0, min(ground), max(ground)))
    else:
        print("   clip %-12s frames=%-4d grip %.3f m | airborne by design (ground "
              "%.3f..%.3f)"
              % (name, nframes, max(grip) if grip else 0.0, min(ground), max(ground)))
    return act


# (name, frames, builder, grounded) -- `grounded` clips are checked against the
# floor; a death animation is *supposed* to leave the feet.
CLIP_TABLE = [
    ("idle", 73, clip_idle, True),
    ("walk", 33, clip_walk, True),
    ("run", 21, clip_run, True),
    ("crouch_idle", 61, clip_crouch_idle, True),
    ("crouch_walk", 41, clip_crouch_walk, True),
    ("aim_idle", 73, clip_aim_idle, True),
    ("fire", 9, clip_fire, True),
    ("reload", 55, clip_reload, True),
    ("hit", 13, clip_hit, True),
    ("melee", 21, clip_melee, True),
    ("death", 61, clip_death, False),
]


# Clips that only make sense for someone holding a rifle.  An unarmed
# archetype skips them rather than baking arms that reach for a weapon that
# does not exist -- a 0.4 m "grip error" in the audit would be the honest
# result, and it would be measuring nothing.
ARMED_ONLY = ("aim_idle", "fire", "reload", "melee")


def build_clips(arm) -> None:
    global AIM_LOC
    AIM_LOC = solve_aim_offset(arm)
    print("   aim mount dx=%+.3f (shaped %.3f) support reach %.3f of %.3f m"
          % (AIM_LOC.x - shape_chest_offset(WEAPON_AIM_LOC).x,
             AIM_LOC.x,
             _foregrip_distance(arm, AIM_LOC),
             sum(arm_lengths(arm, "L"))))
    only = arg("--clip")
    skipped = []
    for name, frames, fn, grounded in CLIP_TABLE:
        if only and only != name:
            continue
        if not P["armed"] and name in ARMED_ONLY:
            skipped.append(name)
            continue
        bake_clip(arm, name, frames, fn, grounded=grounded)
    if skipped:
        print("   clips skipped (unarmed): %s" % ", ".join(skipped))



def pick_engine():
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "CYCLES"):
        try:
            bpy.context.scene.render.engine = eng
            return eng
        except TypeError:
            continue
    return bpy.context.scene.render.engine


def setup_studio():
    sc = bpy.context.scene
    pick_engine()
    sc.render.resolution_x = 480
    sc.render.resolution_y = 700
    sc.render.film_transparent = False
    for tf in ("AgX", "Filmic", "Standard"):
        try:
            sc.view_settings.view_transform = tf
            break
        except TypeError:
            continue
    try:
        sc.view_settings.look = "None"
    except TypeError:
        pass

    world = bpy.data.worlds.new("Studio")
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.04, 0.045, 0.05, 1.0)
        bg.inputs[1].default_value = 1.0

    def lamp(name, loc, energy, color, size=2.0, kind='AREA'):
        d = bpy.data.lights.new(name, type=kind)
        d.energy = energy
        d.color = color
        if kind == 'AREA':
            d.size = size
        o = link(bpy.data.objects.new(name, d))
        o.location = loc
        return o

    key = lamp("Key", (2.6, 3.0, 2.6), 420.0, (1.0, 0.95, 0.88), size=2.2)
    key.rotation_euler = (math.radians(58), 0, math.radians(140))
    fill = lamp("Fill", (-2.8, 2.0, 1.5), 120.0, (0.72, 0.82, 1.0), size=3.0)
    fill.rotation_euler = (math.radians(72), 0, math.radians(-135))
    rim = lamp("Rim", (-0.6, -3.2, 2.4), 300.0, (0.85, 0.90, 1.0), size=1.4)
    rim.rotation_euler = (math.radians(120), 0, math.radians(-10))
    return sc


def _aim(cam, target: Vector) -> None:
    """Point a camera at a world position (Blender cameras look down -Z)."""
    cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()


def render_clip_frames(arm, out_dir, samples=5, variant=""):
    """Sample frames from every baked clip so motion can be reviewed as stills.
    The strip is what catches an arm that pops between keys."""
    os.makedirs(out_dir, exist_ok=True)
    sc = bpy.context.scene
    if arm.animation_data is None:
        return []
    files = []
    for act in bpy.data.actions:
        arm.animation_data.action = act
        # Blender 5 actions are slotted, so Action.fcurves no longer exists;
        # frame_range is the version-proof way to find the clip's extent.
        last = int(act.frame_range[1])
        for i in range(samples):
            f = 1 + int((last - 1) * i / max(1, samples - 1))
            sc.frame_set(f)
            bpy.context.view_layer.update()
            # The variant is part of the name: without it, five archetypes
            # render over each other into one strip of the last one built.
            stem = "anim_%s_%s_%02d" % (variant, act.name, i)
            render_views(out_dir, stem, views=[("threeq", 32.0)],
                         distance=5.4 * P["stature"], height=0.95 * P["stature"])
            files.append("%s/%s_threeq.png" % (out_dir, stem))
    arm.animation_data.action = None
    sc.frame_set(1)
    return files


def render_views(out_dir, name, views=None, distance=5.72, height=0.95,
                 silhouette=False):
    """Turntable renders.  The character is at the origin, facing +Y, so yaw 0
    is a profile view and yaw 90 is straight down the barrel."""
    os.makedirs(out_dir, exist_ok=True)
    sc = bpy.context.scene
    cam = bpy.data.objects.get("Cam")
    if cam is None:
        cam_data = bpy.data.cameras.new("Cam")
        cam_data.lens = 85.0
        cam = link(bpy.data.objects.new("Cam", cam_data))
    sc.camera = cam
    sc.render.film_transparent = bool(silhouette)

    if views is None:
        views = [("front", 90.0), ("threeq", 40.0), ("side", 0.0), ("back", -90.0)]
    target = Vector((0.0, 0.0, height))
    files = []
    for label, yaw in views:
        a = math.radians(yaw)
        cam.location = Vector((math.sin(a) * distance, math.cos(a) * distance,
                               height + 0.22))
        _aim(cam, target)
        if flag("--renderdebug"):
            print("   cam %-7s yaw=%6.1f loc=%s rot_deg=%s"
                  % (label, yaw, vstr(cam.location),
                     vstr(Vector((math.degrees(cam.rotation_euler.x),
                                  math.degrees(cam.rotation_euler.y),
                                  math.degrees(cam.rotation_euler.z))))))
        tag = "_sil" if silhouette else ""
        path = os.path.join(out_dir, "%s_%s%s.png" % (name, label, tag))
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        files.append(path)
        print("  rendered", path)
    sc.render.film_transparent = False
    return files


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------


def build_one(variant: str, stage: str) -> None:
    set_proportion(variant)
    print("== CENTURY OF HUMILIATION character build: stage=%s variant=%s "
          "(stature %.2f girth %.2f shoulder %.2f%s)"
          % (stage, variant, P["stature"], P["girth"], P["shoulder"],
             "" if P["armed"] else ", unarmed"))
    M, parts = build_character(variant)
    print("   parts: %d" % len(parts))
    body = join_parts(parts, "Character_%s" % variant)
    # The archetype shape is applied here, to the joined mesh, and again to the
    # armature below with the same numbers: everything downstream -- heat
    # weighting, the IK, the clips -- sees one consistent body.
    shape_mesh(body)

    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    print("   verts=%d faces=%d tris~%d mats=%d"
          % (len(body.data.vertices), len(body.data.polygons), tris,
             len(body.data.materials)))

    arm = None
    if stage in ("rig", "anim", "all"):
        arm = build_armature("Rig_%s" % variant)
        shape_armature(arm)
        print("   bones: %d (%d deform) | mesh %.3f m tall"
              % (len(arm.data.bones),
                 sum(1 for b in arm.data.bones if b.use_deform),
                 max(v.co.z for v in body.data.vertices)))
        skin(body, arm)
        fill_unweighted(body, arm)
        clean_weights(body)
        if audit_weights(body) > 0.0:
            print("   ! rig still has unweighted vertices")

    if arm is not None and stage in ("anim", "all"):
        build_clips(arm)

    if flag("--render") or stage == "mesh":
        setup_studio()
        # Baking the clips leaves the armature posed on the last frame of the
        # last clip, which is the death clip: rendering the beauty views from
        # there photographs a body lying on its back, 1.9 m of character reduced
        # to 114 px of shoulder in the corner of the frame.  Rest position pins
        # the mesh to its bind pose for as long as these renders run.
        if arm is not None:
            arm.data.pose_position = 'REST'
        # Framing follows the body: a fixed camera distance frames a heavy as a
        # trooper with its feet cut off.
        st = P["stature"]
        render_views(OUT_PREVIEW, "%s_mesh" % variant, distance=5.72 * st,
                     height=0.95 * st)
        render_views(OUT_PREVIEW, "%s_mesh" % variant, silhouette=True,
                     distance=5.72 * st, height=0.95 * st)
        # head close-up: the only part the camera ever gets near
        render_views(OUT_PREVIEW, "%s_head" % variant,
                     views=[("threeq", 52.0), ("front", 90.0)],
                     distance=1.32 * st, height=1.70 * st)

    if arm is not None and flag("--renderclips"):
        setup_studio()
        arm.data.pose_position = 'POSE'
        render_clip_frames(arm, OUT_PREVIEW, int(arg("--clipsamples", 5)), variant)
        print("   rendered clips to", OUT_PREVIEW)

    if arm is not None and flag("--posetest"):
        setup_studio()
        pose_test(arm)
        render_views(OUT_PREVIEW, "%s_pose" % variant,
                     views=[("threeq", 40.0), ("side", 0.0)])

    if stage in ("mesh", "rig", "anim", "all"):
        os.makedirs(OUT_GLB, exist_ok=True)
        out = os.path.join(OUT_GLB, "%s.glb" % variant)
        has_anim = stage in ("anim", "all")
        bpy.ops.export_scene.gltf(
            filepath=out, export_format='GLB', export_yup=True,
            export_animations=has_anim,
            export_animation_mode='ACTIONS' if has_anim else 'ACTIONS',
            export_skins=arm is not None,
            export_apply=False,
        )
        print("   wrote", out, os.path.getsize(out), "bytes")

    # Keep the editable source next to the export: this is the file to open in
    # Blender and sculpt over by hand when a shape needs a real artist.
    os.makedirs(OUT_SRC, exist_ok=True)
    gdignore = os.path.join(OUT_SRC, ".gdignore")
    if not os.path.exists(gdignore):
        with open(gdignore, "w", encoding="utf-8"):
            pass
    blend_out = os.path.join(OUT_SRC, "%s.blend" % variant)
    # stop Blender leaving a .blend1 backup behind on every rebuild
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=blend_out)
    print("   wrote", blend_out, os.path.getsize(blend_out), "bytes")


def main():
    stage = str(arg("--stage", "mesh"))
    batch = arg("--variants")
    if flag("--all"):
        names = list(ALL_VARIANTS)
    elif batch:
        names = [v.strip() for v in str(batch).split(",") if v.strip()]
    else:
        names = [str(arg("--variant", "trooper"))]
    built = 0
    for variant in names:
        if variant not in VARIANTS:
            print("   ! no such archetype: %s (have %s)"
                  % (variant, ", ".join(VARIANTS)))
            continue
        if built:
            print("")
        reset_scene()
        build_one(variant, stage)
        built += 1
    print("== done (%d archetype%s)" % (built, "" if built == 1 else "s"))


if __name__ == "__main__":
    main()
