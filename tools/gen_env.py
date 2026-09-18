#!/usr/bin/env python3
"""
CENTURY OF HUMILIATION -- occupied-city environment pipeline.

Builds the hero pieces of the occupation with Blender, run head-less, and
exports them as glTF binary (`.glb`) for Godot to import.

    blender --background --python tools/gen_env.py -- --all
    blender --background --python tools/gen_env.py -- --piece monument --render

Why only the hero pieces
------------------------
Everything *modular* in this game is already procedural: `Kit.gd` draws the
facades, the barriers, the tents, the wrecks and the props straight into merged
meshes, which is why a whole district costs under a thousand draw calls.  That
is the right tool for things that repeat.

What it cannot do is a one-off with real silhouette -- the monument the plaza is
built around, the balloon hanging over it, the gate you have to walk through.
Those are the pieces here: authored geometry with UV-less baked materials, the
same way the characters are.

Art direction
-------------
Taken from `.concept/reference/2050-shotlist.md`, which reconstructs the trailer
frame by frame.  Two things in that document drive this file:

* **The occupier's identity is carried by the balloon and the monument banner.**
  The source frames contain no legible signage, so the words on the cloth are
  art direction rather than reconstruction: the monument carries a motto and the
  checkpoint takes only functional marking ("CHECKPOINT", "AUTHORISED
  PERSONNEL") -- administrative Latin lettering, no real-world names.
* **The marks are the art director's, not the pixels'.**  The source banner
  measures red-dominant with a small yellow motif about 1% of its area and *no
  resolvable pattern* (34x40 px at capture size), so nothing here claims to
  reconstruct it.  The monument banner carries `--motto` (default "ALLAH|IS
  GREAT", `|` splits lines) as real extruded lettering, the balloon's flank
  carries the contingent's crescent, and neither the motto nor the balloon mark
  is load-bearing for any other piece.
* Note that the crescent and the motto together read as one specific real-world
  religion worn by the invading faction.  That is a deliberate art choice and
  easy to reconsider: `--motto` changes the words, and the balloon's mark is one
  function (`_hull_mark`) if the flag wants a different emblem.

Geometry conventions
--------------------
* Blender is Z-up, every piece stands on **z = 0** and its "front" faces **+Y**.
  The exporter maps Blender +Y to glTF -Z, which is "forward" in Godot, so a
  piece arrives in engine already facing the way the level's approach does.
* Everything is built from three primitives -- `box`, `loft` (imported from the
  character pipeline) and `extruded_poly` -- then welded into one object per
  piece, so a piece is a single draw call.
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

# The primitives, the material helper and the turntable renderer are shared with
# the character pipeline on purpose: one loft, one renderer, one place to fix a
# bug.  These are siblings in tools/, so this is a plain sibling import.
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import gen_characters as gc  # noqa: E402

ROOT = os.path.dirname(HERE)
OUT_GLB = os.path.join(ROOT, "assets", "environment")
# Editable sources live inside a directory Godot is told to ignore, or headless
# import tries to load every .blend as a scene and errors out.
OUT_SRC = os.path.join(OUT_GLB, "src")
OUT_PREVIEW = os.path.join(ROOT, ".concept", "env")

PIECES = ["monument", "balloon", "checkpoint", "banner", "billboard"]


# --------------------------------------------------------------------------
# scene plumbing (thin wrappers over the character pipeline's helpers)
# --------------------------------------------------------------------------

def part(name, verts, faces, material, smooth=False, bevel=0.0, sub=0,
         recalc_=True):
    """One mesh object.  Bevel for hard-surface, subdivision for organic.

    `recalc_` is off for open sheets -- a cloth banner and the balloon's mark
    are single-thickness surfaces, and `normals_make_consistent` has no volume
    to reason about on those, so it will happily flip them to face into the
    thing they are covering.
    """
    obj = gc.mesh_object(name, verts, faces, material)
    if recalc_:
        recalc(obj)
    if sub > 0:
        m = obj.modifiers.new("Sub", 'SUBSURF')
        m.levels = sub
        m.render_levels = sub
    if bevel > 0.0:
        m = obj.modifiers.new("Bev", 'BEVEL')
        m.width = bevel
        m.segments = 2
        m.limit_method = 'ANGLE'
        m.angle_limit = math.radians(40.0)
    if sub > 0 or bevel > 0.0:
        gc.apply_modifiers(obj)
    gc.shade(obj, smooth=smooth,
             auto_angle=math.radians(38.0) if smooth else None)
    return obj


def recalc(obj):
    """Make every face wind outward.  Hand-built prisms get this wrong.

    Lighting is the only thing that reads a normal here (the kit is untextured),
    and a backwards face on a 17 m monument is a black panel in the middle of
    the plaza, which is exactly the sort of thing that is invisible until
    someone walks past it.
    """
    gc.activate(obj)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')


def box(name, centre, size, material, yaw=0.0, pitch=0.0, bevel=0.0,
        smooth=False):
    rot = Matrix.Rotation(math.radians(yaw), 3, 'Z') @ \
        Matrix.Rotation(math.radians(pitch), 3, 'X')
    v, f = gc.box_mesh(centre, size, rot)
    return part(name, v, f, material, bevel=bevel, smooth=smooth)


def tube(name, a, b, radius, material, sides=12, profile=1.0, smooth=True,
         radius_b=None):
    """A cylinder (or a taper) between two world points."""
    a, b = Vector(a), Vector(b)
    rb = radius if radius_b is None else radius_b
    sections = [(a, radius, radius), (b, rb, rb)]
    v, f = gc.loft(sections, sides=sides, cap=True, profile=profile)
    return part(name, v, f, material, smooth=smooth)


def face_outward(obj, away_from):
    """Flip a whole open shell if its average normal points at `away_from`.

    Cheaper than reasoning about winding order for every parametrisation, and
    it fails loudly instead of shipping a lit-from-behind banner.
    """
    away_from = Vector(away_from)
    score = 0.0
    for p in obj.data.polygons:
        score += (p.center.to_3d() - away_from).dot(p.normal)
    if score < 0.0:
        gc.activate(obj)
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.mesh.flip_normals()
        bpy.ops.object.mode_set(mode='OBJECT')
        print("   ! flipped %s: shell was facing its own centre" % obj.name)
    return obj


def plate(name, poly, thickness, material, matrix=None, smooth=False):
    """A flat polygon extruded along Z, then placed by `matrix`.

    `poly` is a list of 2D points in the plate's own plane.  Fins, emblems,
    gussets and stiffeners all come out of this one function.
    """
    n = len(poly)
    h = thickness * 0.5
    verts = [Vector((p[0], p[1], -h)) for p in poly] + \
            [Vector((p[0], p[1], h)) for p in poly]
    faces = []
    for k in range(1, n - 1):
        faces.append((0, k + 1, k))
        faces.append((n, n + k, n + k + 1))
    for k in range(n):
        k2 = (k + 1) % n
        faces.append((k, k2, n + k2, n + k))
    if matrix is not None:
        verts = [matrix @ v for v in verts]
    return part(name, verts, faces, material, smooth=smooth)


def cloth(name, material, width, top_z, bottom_z, folds=6, amp=0.14,
          billow=0.30, y0=0.0, nx=None, nz=14, taper=0.86):
    """A hanging sheet with vertical fold ribs, in the XZ plane, facing +Y.

    This is the single most repeated shape in the kit -- the banner on the
    monument, the banner on the checkpoint beam, the hung facade banner -- so it
    is worth doing properly rather than as a flat box.  The fold amplitude and
    the outward billow both grow towards the hem, and the sheet narrows a little
    towards the bar, which is what makes it read as cloth rather than card.
    """
    nx = nx or max(12, folds * 6)
    verts, faces = [], []
    for iz in range(nz + 1):
        v = iz / nz                              # 0 at the bar, 1 at the hem
        z = top_z + (bottom_z - top_z) * v
        w = width * (taper + (1.0 - taper) * v)
        gather = 0.34 + 0.66 * v
        for ix in range(nx + 1):
            u = ix / nx
            x = (u - 0.5) * w
            y = y0 + billow * v + amp * gather * math.sin(folds * math.tau * u)
            verts.append(Vector((x, y, z)))
    stride = nx + 1
    for iz in range(nz):
        for ix in range(nx):
            a = iz * stride + ix
            faces.append((a, a + 1, a + stride + 1, a + stride))
    obj = part(name, verts, faces, material, smooth=True, recalc_=False)
    centre = Vector((0.0, 0.0, 0.0))
    for v in verts:
        centre += v
    centre /= max(1, len(verts))
    return face_outward(obj, centre - Vector((0.0, 1.0, 0.0)))


def lettering(name, body, material, size=0.6, depth=0.04, matrix=None):
    """Real lettering, from a Blender text object converted to mesh.

    Signage has to be geometry, not a texture: the kit ships no image files, so
    a word on a sign is either extruded letters or nothing.
    """
    bpy.ops.object.text_add()
    obj = bpy.context.object
    obj.name = name
    tc = obj.data
    tc.body = body
    tc.size = size
    tc.extrude = depth
    tc.align_x = 'CENTER'
    tc.align_y = 'CENTER'
    obj.data.materials.append(material)
    gc.activate(obj)
    bpy.ops.object.convert(target='MESH')
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    if matrix is not None:
        obj.matrix_world = matrix
    gc.shade(obj, smooth=False)
    return obj


def facing_matrix(location, yaw_deg=0.0, roll_deg=0.0):
    """Place a +Y-facing flat thing (lettering, a plate) in the world.

    Text objects and `plate` both author themselves facing +Z, so getting them
    onto a wall is two rotations: -90 about X stands them upright facing +Y,
    and the extra 180 about Z is what stops the word reading backwards.
    """
    m = Matrix.Translation(Vector(location))
    m = m @ Matrix.Rotation(math.radians(yaw_deg), 4, 'Z')
    m = m @ Matrix.Rotation(math.radians(roll_deg), 4, 'Y')
    m = m @ Matrix.Rotation(math.radians(180.0), 4, 'Z')
    m = m @ Matrix.Rotation(math.radians(90.0), 4, 'X')
    return m


# --------------------------------------------------------------------------
# materials
# --------------------------------------------------------------------------

def env_materials():
    """Baked palette.  Deliberately narrow: pale stone and dark steel, with the
    occupier's red the only saturated thing in the kit."""
    M = {
        "stone":     gc.mat("env_stone", (0.640, 0.628, 0.588), roughness=0.80),
        "stone_pale": gc.mat("env_stone_pale", (0.760, 0.748, 0.706), roughness=0.74),
        "stone_dk":  gc.mat("env_stone_dark", (0.330, 0.325, 0.310), roughness=0.86),
        "granite":   gc.mat("env_granite", (0.185, 0.188, 0.196), roughness=0.58,
                            coat=0.2),
        "concrete":  gc.mat("env_concrete", (0.430, 0.428, 0.418), roughness=0.92),
        "steel":     gc.mat("env_steel", (0.175, 0.183, 0.198), roughness=0.42,
                            metallic=0.92),
        "steel_pale": gc.mat("env_steel_pale", (0.300, 0.310, 0.325),
                             roughness=0.38, metallic=0.88),
        "rust":      gc.mat("env_rust", (0.280, 0.155, 0.092), roughness=0.78,
                            metallic=0.45),
        "red":       gc.mat("env_red", (0.400, 0.042, 0.046), roughness=0.86,
                            sheen=0.35),
        "red_dk":    gc.mat("env_red_dark", (0.205, 0.026, 0.030), roughness=0.88,
                            sheen=0.3),
        "yellow":    gc.mat("env_yellow", (0.820, 0.632, 0.070), roughness=0.46,
                            metallic=0.20),
        "canvas":    gc.mat("env_canvas", (0.318, 0.302, 0.262), roughness=0.94,
                            sheen=0.3),
        "wood":      gc.mat("env_wood", (0.235, 0.162, 0.108), roughness=0.86),
        "paint_w":   gc.mat("env_paint_white", (0.820, 0.822, 0.812),
                            roughness=0.72),
        "glass":     gc.mat("env_glass", (0.052, 0.062, 0.072), roughness=0.16,
                            metallic=0.25, coat=0.5),
        "lamp":      gc.mat("env_lamp", (0.900, 0.860, 0.760), roughness=0.22,
                            emission=(1.0, 0.94, 0.80), emission_strength=7.0),
    }
    return M


# --------------------------------------------------------------------------
# the monument
# --------------------------------------------------------------------------
#
# The video's plaza has one pale landmark in it, carrying the occupier's red
# banner.  This is that building: a stepped plinth, a tapering pale pylon, the
# banner draped down its face, and the service ring the occupation has built
# around the base of it -- floodlights, a steel fence, sandbags.  Nothing here
# is a real monument: it is a 17 m pale mass with a red thing on it, which is
# what the frames actually show.

MONUMENT_MOTTO = "ALLAH|IS GREAT"


def build_monument(M, motto=MONUMENT_MOTTO):
    parts = []
    D = {}
    H = 16.9

    # --- plinth: three steps, then the die the pylon stands on -------------
    steps = [(13.0, 0.46), (11.3, 0.44), (9.7, 0.58)]
    z = 0.0
    for i, (w, h) in enumerate(steps):
        parts.append(box("Step%d" % i, (0, 0, z + h * 0.5), (w, w, h),
                         M["stone_dk" if i % 2 else "granite"], bevel=0.012))
        z += h
    die_h = 2.3
    parts.append(box("Die", (0, 0, z + die_h * 0.5), (7.3, 7.3, die_h),
                     M["stone"], bevel=0.02))
    die_top = z + die_h
    D["die_top"] = die_top
    D["die_half"] = 3.65

    # cornice over the die, and the recessed tablets on all four faces
    parts.append(box("Cornice", (0, 0, die_top + 0.20), (8.05, 8.05, 0.40),
                     M["stone_pale"], bevel=0.02))
    pylon_base = die_top + 0.40
    for yaw in (0.0, 90.0, 180.0, 270.0):
        a = math.radians(yaw)
        out = Vector((math.sin(a), math.cos(a), 0.0))
        parts.append(box("TabletEdging", out * 3.62 + Vector((0, 0, die_top - 1.15)),
                         (1.96, 0.10, 1.26), M["stone_dk"], yaw=yaw))
        parts.append(box("Tablet", out * 3.60 + Vector((0, 0, die_top - 1.15)),
                         (1.72, 0.10, 1.04), M["granite"], yaw=yaw))

    # --- pylon: a square loft with entasis ---------------------------------
    # Section half-width falls from 3.0 to 1.02, but not linearly: a monument
    # pylon that tapers in a straight line reads as a roof, and one that tapers
    # on a curve reads as stone.  profile < 1 rounds the corners off a square
    # cross-section, which is what a chiselled pylon is.
    top = H - 1.5
    secs = []
    rows = 12
    for i in range(rows + 1):
        u = i / rows
        zz = pylon_base + (top - pylon_base) * u
        r = 3.02 + (1.02 - 3.02) * (u ** 0.78)
        secs.append((Vector((0.0, 0.0, zz)), r, r))
    v, f = gc.loft(secs, sides=20, cap=True, profile=0.44)
    parts.append(part("Pylon", v, f, M["stone"], smooth=True))
    D["pylon_top"] = top

    # corner ribs and the two string courses
    for i in range(9):
        u = i / 8.0
        zz = pylon_base + 0.45 + (top - pylon_base - 1.1) * u
        r = 3.02 + (1.02 - 3.02) * (u ** 0.78)
        s = r * math.sqrt(2.0) * 0.995
        for yaw in (45.0, 135.0, 225.0, 315.0):
            a = math.radians(yaw)
            parts.append(box("Rib", (math.cos(a) * s, math.sin(a) * s, zz),
                             (0.26, 0.26, (top - pylon_base - 1.3) / 8.0 * 1.15),
                             M["stone_pale"], yaw=yaw, bevel=0.01))
    for zz, w, mat in ((pylon_base + 0.30, 6.34, "stone_pale"),
                       (top - 1.35, 2.42, "stone_pale")):
        parts.append(box("Course", (0, 0, zz), (w, w, 0.34), M[mat], bevel=0.015))

    # --- capstone ----------------------------------------------------------
    cap = []
    for i in range(4):
        u = i / 3.0
        cap.append((Vector((0.0, 0.0, top + 0.17 + u * 1.35)),
                    1.30 - 1.02 * u, 1.30 - 1.02 * u))
    v, f = gc.loft(cap, sides=18, cap=True, profile=0.44)
    parts.append(part("Capstone", v, f, M["stone_pale"], smooth=True))
    D["height"] = top + 1.55

    # --- the banner --------------------------------------------------------
    # Hung off a bracket at 10.2 m and dropping to 2.8 m, so it covers the
    # pylon's whole readable face: this is the shape the camera sees from the
    # plaza floor.
    bz_top, bz_bot, bw = 10.2, 2.80, 4.30
    by = 3.05
    parts.append(tube("BannerBar", (-bw * 0.62, by, bz_top + 0.10),
                      (bw * 0.62, by, bz_top + 0.10), 0.075, M["steel"], sides=10))
    for sx in (-1.0, 1.0):
        parts.append(tube("Bracket", (sx * 0.35, 1.30, bz_top + 0.10),
                          (sx * bw * 0.60, by, bz_top + 0.10), 0.055,
                          M["steel"], sides=8))
        parts.append(box("BracketPlate", (sx * bw * 0.58, by, bz_top + 0.10),
                         (0.16, 0.30, 0.42), M["steel"], bevel=0.01))
    parts.append(cloth("Banner", M["red"], bw, bz_top, bz_bot, folds=5,
                       amp=0.13, billow=0.34, y0=by))
    parts.append(box("BannerHem", (0, by + 0.34, bz_bot + 0.05),
                     (bw * 0.99, 0.16, 0.20), M["red_dk"], bevel=0.01))
    # --- the motto ---------------------------------------------------------
    # The banner carried the star emblem, which was the closest the source
    # pixels supported.  It carries the contingent's words now, as real lettering
    # from a text object converted to mesh: the kit ships no image files, so a
    # word on cloth is either extruded letters or nothing.
    if motto:
        def cloth_y_at(z):
            """The cloth's outermost y at a height, fold peak included.

            The sheet billows and its fold ribs deepen towards the hem, so one
            fixed y buries an upper line in the cloth and floats a lower one off
            it.  Each line is placed against the surface it actually sits on.
            """
            v = max(0.0, min(1.0, (bz_top - z) / max(1e-3, bz_top - bz_bot)))
            return by + 0.34 * v + 0.13 * (0.34 + 0.66 * v)

        lines = [l.strip() for l in motto.split("|") if l.strip()]
        size, step = 0.60, 0.78
        z0 = 6.40 + step * (len(lines) - 1) * 0.5
        made = []
        for i, line in enumerate(lines):
            zz = z0 - i * step
            obj = lettering("Motto%d" % i, line, M["yellow"], size=size,
                            depth=0.035,
                            matrix=facing_matrix(
                                (0.0, cloth_y_at(zz) + 0.03, zz)))
            parts.append(obj)
            made.append((line, zz, obj))
        # Report where the letters actually landed.  Extruded text on a hanging
        # banner is the one thing here that can be authored correctly and still
        # be buried in the cloth in engine, so the numbers go in the log: the
        # letters have to be inside the sheet's width, inside its z range, and
        # in front of the fold peaks at their own height.
        for line, zz, obj in made:
            xs, ys, zs = [], [], []
            for v in obj.data.vertices:
                w = obj.matrix_world @ v.co
                xs.append(w.x)
                ys.append(w.y)
                zs.append(w.z)
            print("   motto %-11s x %+.2f..%+.2f (sheet +-%.2f)  "
                  "y %+.3f..%+.3f (cloth peak %+.3f)  z %.2f..%.2f (banner %.2f..%.2f)"
                  % ('"%s"' % line, min(xs), max(xs), bw * 0.5, min(ys), max(ys),
                     cloth_y_at(zz), min(zs), max(zs), bz_bot, bz_top))
    # a second, smaller banner on the side face, so the plaza reads from either
    # approach rather than only from the spawn side
    side = cloth("BannerSide", M["red"], 3.0, 9.6, 3.6, folds=4, amp=0.11,
                 billow=0.26, y0=0.0, nx=26, taper=0.88)
    # the sheet is authored facing +Y, so it takes -90 about Z to face +X
    side.rotation_euler = (0.0, 0.0, math.radians(-90.0))
    side.location = Vector((2.85, 0.0, 0.0))
    parts.append(side)

    # --- occupation: fence ring, floodlights, sandbags ---------------------
    ring = 11.6
    for i in range(28):
        a = math.tau * i / 28.0
        if abs(math.cos(a)) < 0.22 or abs(math.sin(a)) < 0.22:
            continue                      # leave the two approaches open
        p = (math.cos(a) * ring, math.sin(a) * ring, 0.0)
        parts.append(tube("FencePost", (p[0], p[1], 0.0), (p[0], p[1], 2.35),
                          0.05, M["steel"], sides=8))
        parts.append(box("FenceRail", (p[0] + math.cos(a + 0.11) * 1.28,
                                       p[1] + math.sin(a + 0.11) * 1.28, 2.20),
                         (2.58, 0.05, 0.07), M["steel"],
                         yaw=math.degrees(a + 0.11) + 90.0))
        parts.append(box("FenceRail", (p[0] + math.cos(a + 0.11) * 1.28,
                                       p[1] + math.sin(a + 0.11) * 1.28, 0.80),
                         (2.58, 0.05, 0.07), M["steel"],
                         yaw=math.degrees(a + 0.11) + 90.0))
    for i in range(4):
        a = math.radians(45.0 + 90.0 * i)
        p = Vector((math.cos(a) * 4.55, math.sin(a) * 4.55, D["die_top"] + 0.42))
        parts.append(box("FloodBase", p, (0.36, 0.30, 0.24), M["steel"]))
        parts.append(box("FloodHead", p + Vector((0, 0, 0.34)), (0.46, 0.34, 0.38),
                         M["steel"], yaw=math.degrees(a) + 180.0, pitch=-28.0))
        parts.append(box("FloodLens", p + Vector((0, 0, 0.34))
                         + Vector((math.cos(a), math.sin(a), 0)) * 0.19,
                         (0.34, 0.30, 0.06), M["lamp"],
                         yaw=math.degrees(a) + 180.0, pitch=-28.0))
    for i in range(16):
        a = math.radians(200.0 + 140.0 * i / 16.0)
        p = Vector((math.cos(a) * 9.2, math.sin(a) * 9.2, 0.0))
        parts.append(box("Sandbag", p + Vector((0, 0, 0.17 + 0.22 * (i % 2))),
                         (0.78, 0.46, 0.34), M["canvas"],
                         yaw=math.degrees(a) + 90.0 + (7.0 if i % 2 else -5.0),
                         bevel=0.05, smooth=True))
    D["parts"] = parts
    return parts, D


# --------------------------------------------------------------------------
# the balloon
# --------------------------------------------------------------------------
#
# A tethered airship over the plaza: the one element a human commenter
# independently confirms in the source video.  Whole assembly in one piece --
# envelope, fins, the flank mark, the tethers and the mooring rig -- with its
# origin on the ground, so the level places it with a single position and the
# cable cannot silently disconnect from the balloon.

B_LEN = 8.20       # half-length along X
B_RAD = 4.20       # max radius
B_Z = 52.0         # envelope centre height


def _envelope_r(t):
    """Radius at normalised length t in [-1, 1].  A blunt exponent, because a
    true ellipsoid tapers to a point and reads as a dart, not a blimp."""
    t = max(-1.0, min(1.0, t))
    return B_RAD * ((1.0 - t * t) ** 0.42)


def _envelope_point(t, a, off=0.0):
    """Surface point at (t, a); `a` is measured from +Y."""
    r = _envelope_r(t)
    ry, rz = r + off, r * 0.96 + off
    return Vector((B_LEN * t, math.cos(a) * ry, B_Z + math.sin(a) * rz))


def build_balloon(M):
    parts = []

    # --- envelope ----------------------------------------------------------
    secs = []
    rows = 22
    for i in range(rows + 1):
        t = -1.0 + 2.0 * i / rows
        r = _envelope_r(t)
        secs.append((Vector((B_LEN * t, 0.0, B_Z)), r, r * 0.96))
    v, f = gc.loft(secs, sides=28, cap=True, profile=1.0)
    parts.append(part("Envelope", v, f, M["red"], smooth=True))

    # --- the mark: a decal shell, not a flat disc --------------------------
    parts.append(mark_shell(M))
    frac, cu = crescent_stats()
    print("   mark: %.1f%% of the flank window painted, centroid u=%+.2f "
          "(a disc would be 29%% centred on u=0)" % (100.0 * frac, cu))

    # --- fins --------------------------------------------------------------
    # `plate` authors a polygon in XY and extrudes it along Z, so each fin is
    # first stood up into the XZ plane (thickness along Y), then swung round
    # the hull's long axis into its quadrant.  The fin polygon's own +y becomes
    # +Z after that first rotation, which is what the swing angles assume.
    fin_poly = [(4.10, 0.55), (7.75, 0.95), (7.05, 3.55), (4.75, 1.85)]
    root_poly = [(3.85, 0.30), (5.10, 0.62), (4.55, 1.30), (3.80, 0.95)]
    stand = Matrix.Rotation(math.radians(90.0), 4, 'X')
    for label, swing in (("Up", 0.0), ("Down", math.pi),
                         ("Fore", -math.pi * 0.5), ("Aft", math.pi * 0.5)):
        m = Matrix.Translation(Vector((0, 0, B_Z))) @ \
            Matrix.Rotation(swing, 4, 'X') @ stand
        parts.append(plate("Fin_%s" % label, fin_poly, 0.14, M["red"], matrix=m))
        # a root fairing, so a fin does not meet the hull on a bare edge
        parts.append(plate("FinRoot_%s" % label, root_poly, 0.22, M["red_dk"],
                           matrix=m))

    # --- nose valve and tail cap ------------------------------------------
    parts.append(tube("NoseValve", (-B_LEN - 0.10, 0, B_Z), (-B_LEN - 0.55, 0, B_Z),
                      0.42, M["red_dk"], sides=14, radius_b=0.30))
    parts.append(tube("TailCap", (B_LEN - 0.05, 0, B_Z), (B_LEN + 0.34, 0, B_Z),
                      0.30, M["steel"], sides=12, radius_b=0.22))

    # --- banners under the belly ------------------------------------------
    for sx in (-3.4, 0.0, 3.4):
        parts.append(cloth("BellyBanner", M["red"], 2.60, 0.0, -5.40, folds=3,
                           amp=0.10, billow=0.22, nz=10, taper=0.95))
        o = parts[-1]
        o.rotation_euler = (0, 0, math.radians(90.0))
        o.location = Vector((sx, 0.0, B_Z - 3.55))

    # --- tethers -----------------------------------------------------------
    # Four cables from the hull's belly to the winch drums: two shallow, two
    # long, which is what stops the balloon reading as floating on a string.
    for sx, sy in ((1.0, 1.0), (1.0, -1.0), (-1.0, 1.0), (-1.0, -1.0)):
        # a = -pi/2 is the belly of the hull, so tilting off it by +-0.55 rad
        # walks the four anchors fore-and-aft along the underside
        top = _envelope_point(sx * 0.30, -math.pi * 0.5 + sy * 0.55, off=0.03)
        foot = Vector((sx * 1.35, sy * 1.05, 1.55))
        parts.append(tube("Tether_%d%d" % (sx, sy), top, foot, 0.032,
                          M["steel"], sides=6))

    # --- mooring rig -------------------------------------------------------
    parts.append(box("MoorBase", (0, 0, 0.24), (4.60, 3.60, 0.48),
                     M["concrete"], bevel=0.03))
    for i, (sx, sy) in enumerate(((1, 1), (1, -1), (-1, 1), (-1, -1))):
        parts.append(box("Winch", (sx * 1.35, sy * 1.05, 0.80),
                         (0.86, 0.72, 0.64), M["steel"], bevel=0.02))
        parts.append(tube("WinchDrum", (sx * 1.35 - 0.44, sy * 1.05, 1.28),
                          (sx * 1.35 + 0.44, sy * 1.05, 1.28), 0.22,
                          M["rust"], sides=12))
        parts.append(tube("StripePost", (sx * 2.05, sy * 1.70, 0.0),
                          (sx * 2.05, sy * 1.70, 1.90), 0.11,
                          M["paint_w" if i % 2 else "red"], sides=10))
        parts.append(tube("StripePostCap", (sx * 2.05, sy * 1.70, 1.90),
                          (sx * 2.05, sy * 1.70, 2.40), 0.08,
                          M["red" if i % 2 else "paint_w"], sides=10))
    parts.append(box("MoorShed", (0.0, 2.35, 1.32), (2.60, 1.20, 2.64),
                     M["concrete"], bevel=0.02))
    parts.append(box("ShedRoof", (0.0, 2.35, 2.72), (2.94, 1.54, 0.18),
                     M["steel_pale"], bevel=0.02))
    parts.append(box("ShedGlass", (1.13, 2.35, 1.70), (0.10, 0.90, 0.80),
                     M["glass"]))
    parts.append(box("ShedLamp", (0.0, 2.95, 2.40), (0.60, 0.24, 0.20),
                     M["lamp"]))
    for i in range(14):
        a = math.tau * i / 14.0
        parts.append(box("MoorBag", (math.cos(a) * 3.1, math.sin(a) * 3.1,
                                     0.17 + 0.22 * (i % 2)),
                         (0.76, 0.44, 0.34), M["canvas"],
                         yaw=math.degrees(a) + (6.0 if i % 2 else -6.0),
                         bevel=0.05, smooth=True))
    D = {"height": B_Z + B_RAD * 0.96 + 0.2, "envelope_z": B_Z}
    return parts, D


def mark_shell(M, off=0.09, nu=46, nv=40):
    """The painted mark, as a proud shell over the hull with material regions.

    A flat disc on a 4.2 m hull would bury its own rim 1.1 m inside the
    envelope, so the mark is a second, 9 cm-proud shell that follows the same
    surface and the shape is a material region on it -- which is also how the
    paint would actually be applied.
    """
    t0, t1 = -0.40, 0.40
    aw = 0.86                                 # half-width of the window, rad
    out = []
    tally = []
    for side, label in ((1.0, "Far"), (-1.0, "Near")):
        mid = 0.0 if side > 0 else math.pi
        verts, faces, mats = [], [], []
        for j in range(nv + 1):
            v = (j / nv - 0.5) * 2.0
            ang = mid + side * (v * aw)
            for i in range(nu + 1):
                t = t0 + (t1 - t0) * i / nu
                verts.append(_envelope_point(t, ang, off=off))
        stride = nu + 1
        for j in range(nv):
            for i in range(nu):
                k = j * stride + i
                faces.append((k, k + 1, k + stride + 1, k + stride))
                u = (i / nu - 0.5) * 2.0
                vv = (j / nv - 0.5) * 2.0
                mats.append(_hull_mark(u, vv, M))
        # report what the region test actually produced on the mesh, because a
        # shape that is right on paper and absent in the shell is exactly how a
        # material-region decal fails
        painted = sum(1 for m in mats if m == M["yellow"])
        if painted == 0:
            print("   !! the %s flank of the mark has no painted faces" % label)
        tally.append((label, painted, len(mats)))
        obj = part("Mark_%s" % label, verts, faces, M["red"], smooth=True,
                   recalc_=False)
        # Material slots are per-object in Blender, so the region list becomes
        # the slot list and the per-face index is written afterwards.
        obj.data.materials.clear()
        names = []
        for m in mats:
            if m not in names:
                names.append(m)
        for m in names:
            obj.data.materials.append(m)
        for p, m in zip(obj.data.polygons, mats):
            p.material_index = names.index(m)
        face_outward(obj, Vector((0.0, 0.0, B_Z)))
        out.append(obj)
    for label, painted, total in tally:
        print("   mark shell %-4s %d/%d faces painted (%.1f%%)"
              % (label, painted, total, 100.0 * painted / max(1, total)))
    return _join_soft(out, "HullMark")


def _join_soft(objs, name):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    j = bpy.context.view_layer.objects.active
    j.name = name
    return j


# The painted window is not square in the hull's own (u, v) parameters: `u`
# spans 0.8 of the half-length (8.20 m), `v` spans 0.86 rad of arc on a 4.2 m
# hull radius.  So half the window is 3.28 m fore-aft and 3.61 m around.  A
# crescent drawn as circles in `u, v` would come out 10% tall, which is the
# sort of error that reads as "slightly wrong" without ever being identifiable.
MARK_HALF_U, MARK_HALF_V = 3.28, 3.61


def crescent_stats(n=140):
    """What fraction of the flank window is painted, and where its mass sits.

    A disc fills 29% of this window and its centroid is the window centre.  A
    crescent does neither, so these two numbers are how the shape gets checked
    without anyone looking at it.
    """
    hits = 0
    su = 0.0
    for j in range(n):
        v = (j / (n - 1.0) - 0.5) * 2.0
        for i in range(n):
            u = (i / (n - 1.0) - 0.5) * 2.0
            if _in_crescent(u, v):
                hits += 1
                su += u
    if not hits:
        return 0.0, 0.0
    return hits / float(n * n), su / hits


def _in_crescent(u, v) -> bool:
    """Inside the outer disc and outside the inner one, in metres on the hull."""
    r_out, r_in, off = 2.10, 1.79, 0.95
    d_out = ((u * MARK_HALF_U) / r_out) ** 2 + ((v * MARK_HALF_V) / r_out) ** 2
    d_in = (((u * MARK_HALF_U) - off) / r_in) ** 2 + ((v * MARK_HALF_V) / r_in) ** 2
    return d_out <= 1.0 and d_in >= 1.0


def _hull_mark(u, v, M):
    """Which painted region a point on the balloon's flank is in.  `u` runs
    fore-aft along the hull, `v` around it, positive upwards.

    The flank carried a generic statesman's portrait, reconstructed from the
    source frames' caption "large red balloon with a man's face".  It carries the
    contingent's crescent now: a shape the pixels never had to settle, and one
    that ties the balloon to the rest of the faction rather than to a likeness
    no frame supports.  Both flanks are painted, because the balloon hangs over
    a square that is crossed in both directions.
    """
    return M["yellow"] if _in_crescent(u, v) else M["red"]


# --------------------------------------------------------------------------
# the checkpoint
# --------------------------------------------------------------------------
#
# The plaza's controlled entry: a gantry you walk under, a booth, two boom
# barriers, concrete chicane, and a watchtower.  The gantry spans 11 m, which
# is the gate over a road; the level extends the barrier line across whatever
# it needs beyond that with the procedural kits, so this piece does not have to
# know how wide the street is.

def build_checkpoint(M):
    parts = []
    span = 11.0
    half = span * 0.5

    # --- gantry ------------------------------------------------------------
    for sx in (-1.0, 1.0):
        x = sx * half
        parts.append(box("Foot", (x, 0.0, 0.28), (1.30, 1.30, 0.56),
                         M["concrete"], bevel=0.03))
        parts.append(tube("Post", (x, 0, 0.50), (x, 0, 6.55), 0.30,
                          M["steel"], sides=16, radius_b=0.26))
        parts.append(box("PostBrace", (x, 0.0, 1.60), (0.72, 0.20, 0.72),
                         M["steel"], bevel=0.02))
    parts.append(box("Beam", (0.0, 0.0, 6.72), (span + 0.75, 0.46, 0.50),
                     M["steel"], bevel=0.02))
    parts.append(box("BeamTop", (0.0, 0.0, 7.02), (span + 0.30, 0.36, 0.14),
                     M["steel_pale"], bevel=0.02))
    for i in range(5):
        x = -half * 0.62 + half * 0.62 * 2.0 * i / 4.0
        parts.append(box("BeamRib", (x, 0.0, 6.44), (0.16, 0.52, 0.30),
                         M["steel_pale"], yaw=0.0, bevel=0.01))
    # a small emblem plate on the beam, and the gantry's own identifiers
    for sx in (-1.0, 1.0):
        plate_pts = []
        n = 10
        for k in range(n):
            a = math.pi * 0.5 + math.tau * k / n
            r = 0.30 if k % 2 == 0 else 0.126
            plate_pts.append((math.cos(a) * r, math.sin(a) * r))
        parts.append(plate("BeamEmblem", plate_pts, 0.05, M["yellow"],
                           matrix=facing_matrix((sx * 3.6, 0.25, 6.72))))

    # --- banner across the gantry ------------------------------------------
    parts.append(cloth("GateBanner", M["red"], 8.20, 6.42, 5.05, folds=6,
                       amp=0.11, billow=0.24, nz=8, taper=0.94))
    parts.append(lettering("GateMark", "CHECKPOINT",
                           M["paint_w"], size=0.40, depth=0.03,
                           matrix=facing_matrix((0.0, 0.30, 5.72))))
    for sx in (-1.0, 1.0):
        parts.append(lettering("GateMark2", "AUTHORISED PERSONNEL",
                               M["paint_w"], size=0.24, depth=0.025,
                               matrix=facing_matrix((sx * 3.35, 0.30, 6.05))))

    # --- booth -------------------------------------------------------------
    bx = half + 2.30
    parts.append(box("BoothBase", (bx, 1.10, 0.14), (3.10, 2.70, 0.28),
                     M["concrete"], bevel=0.02))
    parts.append(box("Booth", (bx, 1.10, 1.72), (2.70, 2.30, 2.88),
                     M["concrete"], bevel=0.02))
    parts.append(box("BoothRoof", (bx, 1.10, 3.28), (3.14, 2.74, 0.24),
                     M["steel_pale"], bevel=0.02))
    parts.append(box("BoothGlass", (bx - 1.30, 1.10, 1.96), (0.12, 1.70, 1.10),
                     M["glass"]))
    parts.append(box("BoothGlassF", (bx, -0.02, 1.96), (1.70, 0.12, 1.10),
                     M["glass"]))
    parts.append(box("BoothLight", (bx, -1.05, 3.05), (0.35, 0.22, 0.22),
                     M["lamp"]))
    parts.append(box("BoothStep", (bx - 1.55, 1.10, 0.10), (0.60, 1.30, 0.20),
                     M["granite"]))

    # --- boom barriers -----------------------------------------------------
    # One arm up (the lane that is open) and one down (the lane that is shut),
    # each a run of short striped segments.  A segment's box is rotated by the
    # same angle its centre is placed along, or the stripes stack upwards while
    # lying flat, which reads as a broken barrier rather than a raised one.
    for sx, raised in ((-1.0, True), (1.0, False)):
        x = sx * (half - 0.55)
        parts.append(box("BoomBase", (x, -0.10, 0.66), (0.66, 0.66, 1.32),
                         M["steel"], bevel=0.02))
        parts.append(tube("BoomPivot", (x, -0.10, 1.16), (x + 0.42 * sx, -0.10, 1.16),
                          0.13, M["steel_pale"], sides=10))
        pitch = 62.0 if raised else 0.0
        arm_len = 5.4
        n = 8
        for k in range(n):
            seg = arm_len / n
            u = (k + 0.5) * seg
            col = M["paint_w"] if k % 2 == 0 else M["red"]
            zz = 1.16 + math.sin(math.radians(pitch)) * u
            yy = math.cos(math.radians(pitch)) * u
            parts.append(box("BoomStrip", (x + 0.42 * sx, -0.10 + yy, zz),
                             (0.16, seg * 1.02, 0.16), col,
                             pitch=pitch))

    # --- chicane of concrete blocks ---------------------------------------
    for i, (cx, cz, yaw) in enumerate(((-3.6, 3.4, 12.0), (3.4, 3.4, -12.0),
                                       (-3.6, -3.2, -10.0), (3.4, -3.2, 10.0))):
        parts.append(box("JerseyFoot", (cx, cz, 0.16), (2.90, 1.02, 0.32),
                         M["concrete"], yaw=yaw, bevel=0.03))
        parts.append(box("JerseyBody", (cx, cz, 0.60), (2.72, 0.72, 0.56),
                         M["concrete"], yaw=yaw, bevel=0.05))
        parts.append(box("JerseyTop", (cx, cz, 0.96), (2.56, 0.46, 0.22),
                         M["concrete"], yaw=yaw, bevel=0.04))

    # --- watchtower --------------------------------------------------------
    tx, tz = -half - 2.10, -2.30
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            parts.append(tube("TowerLeg", (tx + sx * 1.05, tz + sz * 1.05, 0.0),
                              (tx + sx * 0.72, tz + sz * 0.72, 5.30), 0.085,
                              M["steel"], sides=8))
    for zz in (1.65, 3.35, 5.05):
        w = 2.10 - (zz / 5.30) * 0.33
        parts.append(box("TowerRing", (tx, tz, zz), (w * 2.0, 0.07, 0.07),
                         M["steel"]))
        parts.append(box("TowerRing", (tx, tz, zz), (0.07, w * 2.0, 0.07),
                         M["steel"]))
        for sx in (-1.0, 1.0):
            parts.append(tube("TowerDiag", (tx + sx * w, tz - w, zz - 0.85),
                              (tx - sx * w, tz + w, zz), 0.04, M["steel"],
                              sides=6))
    parts.append(box("TowerDeck", (tx, tz, 5.38), (2.60, 2.60, 0.16),
                     M["wood"]))
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            parts.append(box("TowerPost", (tx + sx * 1.24, tz + sz * 1.24, 6.10),
                             (0.11, 0.11, 1.44), M["steel"]))
    parts.append(box("TowerRoof", (tx, tz, 6.92), (2.92, 2.92, 0.14),
                     M["steel_pale"], bevel=0.02))
    parts.append(box("TowerRail", (tx, tz - 1.24, 5.92), (2.50, 0.09, 0.09),
                     M["steel"]))
    parts.append(box("TowerRail", (tx - 1.24, tz, 5.92), (0.09, 2.50, 0.09),
                     M["steel"]))
    parts.append(box("TowerLamp", (tx, tz - 1.10, 6.62), (0.40, 0.26, 0.24),
                     M["lamp"]))
    for i in range(11):
        zz = 0.35 + i * 0.47
        parts.append(box("TowerRung", (tx + 1.32, tz, zz), (0.10, 0.62, 0.07),
                         M["steel_pale"]))
    for sx in (-1.0, 1.0):
        parts.append(tube("TowerStile", (tx + 1.32 + sx * 0.28, tz, 0.10),
                          (tx + 1.32 + sx * 0.28, tz, 5.32), 0.045,
                          M["steel_pale"], sides=8))

    # --- floodlights on the gantry ----------------------------------------
    for sx in (-1.0, 1.0):
        parts.append(box("GantryLamp", (sx * 3.9, 0.0, 7.32), (0.62, 0.42, 0.30),
                         M["steel"]))
        parts.append(box("GantryLens", (sx * 3.9, 0.24, 7.32), (0.52, 0.10, 0.24),
                         M["lamp"]))

    # --- sandbag shoulders -------------------------------------------------
    for sx in (-1.0, 1.0):
        for i in range(9):
            zz = 0.17 + 0.22 * (i % 2)
            parts.append(box("Bag", (sx * (half + 1.15), -5.0 + i * 1.05, zz),
                             (1.06, 0.62, 0.34), M["canvas"],
                             yaw=(9.0 if i % 2 else -7.0) * sx,
                             bevel=0.05, smooth=True))
    D = {"height": 7.30, "span": span}
    return parts, D


# --------------------------------------------------------------------------
# hung facade banner, and the billboard
# --------------------------------------------------------------------------

def build_banner(M, slogan=""):
    parts = []
    w, top, bot = 4.60, 9.40, 1.60
    parts.append(tube("Bar", (-w * 0.58, 0, top + 0.14), (w * 0.58, 0, top + 0.14),
                      0.075, M["steel"], sides=10))
    for sx in (-1.0, 1.0):
        parts.append(box("BarBracket", (sx * w * 0.56, -0.34, top + 0.14),
                         (0.20, 0.70, 0.24), M["steel"], bevel=0.01))
        parts.append(tube("BarStay", (sx * w * 0.52, -0.66, top + 0.34),
                          (sx * w * 0.30, -0.66, top + 1.15), 0.045, M["steel"],
                          sides=8))
        parts.append(box("BarStayPlate", (sx * w * 0.30, -0.66, top + 1.20),
                         (0.22, 0.22, 0.22), M["steel"]))
    parts.append(cloth("Cloth", M["red"], w, top, bot, folds=6, amp=0.15,
                       billow=0.38, nz=20))
    parts.append(box("Hem", (0, 0.38, bot - 0.05), (w * 0.99, 0.18, 0.22),
                     M["red_dk"], bevel=0.01))
    if slogan:
        for i, line in enumerate(slogan.split("|")):
            parts.append(lettering("Slogan%d" % i, line, M["yellow"],
                                   size=0.42, depth=0.03,
                                   matrix=facing_matrix((0.0, 0.42,
                                                         5.4 - i * 0.72))))
    D = {"height": top + 1.4, "width": w, "grounded": False}
    return parts, D


def build_billboard(M):
    parts = []
    w, h = 5.80, 3.60
    base_z = 3.10
    for sx in (-1.0, 1.0):
        x = sx * (w * 0.32)
        parts.append(box("LegFoot", (x, 0.0, 0.22), (0.94, 0.94, 0.44),
                         M["concrete"], bevel=0.03))
        parts.append(box("Leg", (x, 0.0, 1.70), (0.30, 0.30, 3.00),
                         M["steel"], bevel=0.02))
        parts.append(tube("Brace", (x, 0.0, 1.10), (sx * w * 0.05, -0.9, 3.20),
                          0.05, M["steel"], sides=8))
        parts.append(box("PanelBracket", (x, 0.0, base_z + h * 0.5),
                         (0.22, 0.60, 0.24), M["steel"]))
    parts.append(box("PanelBack", (0.0, 0.22, base_z + h * 0.5),
                     (w, 0.24, h), M["steel_pale"], bevel=0.02))
    parts.append(box("Panel", (0.0, 0.37, base_z + h * 0.5), (w - 0.22, 0.10, h - 0.22),
                     M["red"]))
    n = 10
    poly = []
    for k in range(n):
        a = math.pi * 0.5 + math.tau * k / n
        r = 0.72 if k % 2 == 0 else 0.30
        poly.append((math.cos(a) * r, math.sin(a) * r))
    parts.append(plate("PanelEmblem", poly, 0.06, M["yellow"],
                       matrix=facing_matrix((-1.55, 0.45,
                                             base_z + h * 0.5 + 0.35))))
    for i, line in enumerate(("ORDER", "AND", "COMPLIANCE")):
        parts.append(lettering("Poster%d" % i, line, M["paint_w"],
                               size=0.30, depth=0.03,
                               matrix=facing_matrix((1.25, 0.45,
                                                     base_z + h * 0.72
                                                     - i * 0.62))))
    parts.append(box("Catwalk", (0.0, -0.55, base_z - 0.10), (w + 0.5, 0.60, 0.10),
                     M["steel"], bevel=0.01))
    for i in range(9):
        parts.append(box("CatwalkRail", (-w * 0.5 + i * (w / 8.0), -0.82, base_z + 0.42),
                         (0.06, 0.06, 0.94), M["steel"]))
    parts.append(box("CatwalkTop", (0.0, -0.82, base_z + 0.90), (w + 0.5, 0.07, 0.07),
                     M["steel"]))
    for sx in (-1.0, 1.0):
        parts.append(box("Lamp", (sx * (w * 0.5 + 0.24), -1.30, base_z + h * 0.85),
                         (0.30, 0.44, 0.24), M["lamp"], yaw=sx * -22.0))
    D = {"height": base_z + h + 0.3, "width": w}
    return parts, D


# --------------------------------------------------------------------------
# studio, audit, export
# --------------------------------------------------------------------------

def frame_aspect(size) -> float:
    """The frame the piece wants, clamped so nothing goes letterbox-crazy.

    The studio renders at a fixed 700x900, which is right for a standing person
    and wrong for everything here: a 26 m wide, 17 m tall monument in a portrait
    frame occupies 12% of the image, which is what the first pass of this file
    actually produced.
    """
    a = max(size.x, size.y) / max(size.z, 1e-6)
    return max(0.60, min(1.90, a))


def setup_studio_env(span, aspect=0.78, centre=None):
    """Lighting scaled to the piece, and *around* it.

    The character studio's lamps sit 2.6 m from the origin and 420 W, which
    lights a boot on a 17 m monument.  Scaling them out fixes the ground
    pieces, but the lit point has to move too: a balloon whose envelope hangs
    at 52 m with the lamps still at the origin renders almost black, lit only
    by the sky, and "the piece is a dark smear" is exactly what a preview is
    supposed to rule out.
    """
    pivot = Vector((0.0, 0.0, 0.0)) if centre is None else Vector(centre)
    sc = gc.pick_engine()
    sc = bpy.context.scene
    sc.render.resolution_y = 820
    sc.render.resolution_x = int(round(820 * aspect))
    for tf in ("AgX", "Filmic", "Standard"):
        try:
            sc.view_settings.view_transform = tf
            break
        except TypeError:
            continue
    world = bpy.data.worlds.new("EnvSky")
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        # a flat overcast: the reference's plaza shots are grey-blue and the
        # kit is untextured, so a gradient here would be the only colour in frame
        bg.inputs[0].default_value = (0.075, 0.085, 0.105, 1.0)
        bg.inputs[1].default_value = 1.0

    k = max(1.0, span / 6.0)

    def lamp(name, loc, energy, color, size, rot):
        d = bpy.data.lights.new(name, type='AREA')
        d.energy = energy * k * k
        d.color = color
        d.size = size * k
        o = gc.link(bpy.data.objects.new(name, d))
        o.location = pivot + Vector(loc) * k
        o.rotation_euler = tuple(math.radians(a) for a in rot)
        return o

    # Energies are scale-invariant by construction (lamp distance and power
    # both go as k), so these numbers set the absolute exposure: the first pass
    # ran at 900 W and rendered pale stone as blown-out white, which hides the
    # very silhouette the turntable exists to show.
    lamp("Key", (2.6, 3.0, 2.6), 420.0, (1.0, 0.95, 0.88), 2.2, (58, 0, 140))
    lamp("Fill", (-2.8, 2.0, 1.5), 130.0, (0.72, 0.82, 1.0), 3.0, (72, 0, -135))
    lamp("Rim", (-0.6, -3.2, 2.4), 300.0, (0.85, 0.90, 1.0), 1.4, (120, 0, -10))
    return sc


def audit(piece, parts, D, note):
    """Report what was built, in numbers, because nobody here can look at it."""
    objs = [o for o in parts if o is not None]
    tris = 0
    mats = set()
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        me = o.data
        tris += sum(len(p.vertices) - 2 for p in me.polygons)
        for m in me.materials:
            if m is not None:
                mats.add(m.name)
        for v in me.vertices:
            w = o.matrix_world @ v.co
            lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    print("   objects=%d  tris~%d  materials=%d" % (len(objs), tris, len(mats)))
    print("   bounds  x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f"
          % (lo.x, hi.x, lo.y, hi.y, lo.z, hi.z))
    print("   footprint %.1f x %.1f m, height %.1f m, note=%s"
          % (hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, note))
    # Every ground piece sits on the ground it is placed on.  A hero piece
    # floating a few centimetres up is the kind of thing that only shows up as
    # a shadow seam under it in engine, so it is checked here instead.  A hung
    # banner is exempt: it is mounted on a wall and its z is the mount height.
    if not D.get("grounded", True):
        print("   wall-mounted at z=%.2f (not a ground piece)" % lo.z)
    elif abs(lo.z) > 0.02:
        print("   ! piece does not sit on z=0: lowest point %.3f" % lo.z)
    return {"tris": tris, "mats": len(mats), "lo": lo, "hi": hi,
            "size": Vector((hi.x - lo.x, hi.y - lo.y, hi.z - lo.z))}


def export(piece, parts, D, note):
    # Audit first: joining frees the individual objects, so walking `parts`
    # afterwards reads mesh data Blender has already thrown away.
    stats = audit(piece, parts, D, note)
    gc.join_parts(parts, "Env_%s" % piece)
    os.makedirs(OUT_GLB, exist_ok=True)
    out = os.path.join(OUT_GLB, "%s.glb" % piece)
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB',
                              export_yup=True, export_animations=False,
                              export_apply=True)
    print("   wrote", out, os.path.getsize(out), "bytes")
    os.makedirs(OUT_SRC, exist_ok=True)
    gd = os.path.join(OUT_SRC, ".gdignore")
    if not os.path.exists(gd):
        with open(gd, "w", encoding="utf-8"):
            pass
    bpy.context.preferences.filepaths.save_version = 0
    blend = os.path.join(OUT_SRC, "%s.blend" % piece)
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    print("   wrote", blend, os.path.getsize(blend), "bytes")
    return stats


# The close-up: how close to stand, and what height to aim at.  A close-up is
# *meant* to be cropped -- a 17 m monument at turntable range is just a shape,
# and the banner on its face is the thing that carries the art direction -- so
# the render checker does not ask these views to fit.
DETAIL = {
    "monument": (18.0, 7.0),
    "balloon": (26.0, 52.0),
    "checkpoint": (14.0, 3.5),
    "banner": (7.0, 5.8),
    "billboard": (9.0, 4.6),
}
DETAIL_ASPECT = 1.0


def half_angles(aspect=0.78, lens=85.0, sensor=36.0):
    """Horizontal and vertical half-angles of the studio camera.

    Blender's default `sensor_fit` is AUTO, which maps the sensor width to the
    **longer** image dimension.  So in a landscape frame the 36 mm sensor is
    horizontal and it is the *vertical* angle that binds a tall piece -- the
    opposite of the obvious reading, and the reason the first pass of this file
    walked the camera 30% too close and clipped every single view.
    """
    half = sensor * 0.5 / lens
    if aspect >= 1.0:
        return math.atan(half), math.atan(half / aspect)
    return math.atan(half * aspect), math.atan(half)


def fit_distance(lo, hi, aspect=0.78, lens=85.0, sensor=36.0, pad=1.06):
    """Stand the camera back until every corner of the piece is in frame.

    Solved against the real bounding box rather than from the size, for two
    reasons that both showed up as clipped previews: the camera aims at the
    piece's true centre height, which is not `size.z / 2` for anything that
    does not start at z = 0 (the hung banner starts at 1.4 m); and a wide, low
    object seen from a horizontal camera projects its *near* edge far below the
    far one, so a 26 m-wide base needs more room than its own width suggests.
    """
    h_half, v_half = half_angles(aspect, lens, sensor)
    tan_h, tan_v = math.tan(h_half) / pad, math.tan(v_half) / pad
    mid = Vector(((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, (lo.z + hi.z) * 0.5))
    corners = [Vector((sx, sy, sz))
               for sx in (lo.x, hi.x) for sy in (lo.y, hi.y)
               for sz in (lo.z, hi.z)]
    views = [math.radians(a) for a in VIEW_YAW]
    d = max(max(hi.x - lo.x, hi.y - lo.y), hi.z - lo.z) * 2.0
    for _ in range(600):
        fits = True
        for yaw in views:
            cam = Vector((mid.x + math.sin(yaw) * d, mid.y + math.cos(yaw) * d,
                          mid.z + 0.22))
            fwd = (mid - cam).normalized()
            right = fwd.cross(Vector((0.0, 0.0, 1.0))).normalized()
            up = right.cross(fwd).normalized()
            for c in corners:
                v = c - cam
                depth = v.dot(fwd)
                if depth <= 0.05 or abs(v.dot(right) / depth) > tan_h \
                        or abs(v.dot(up) / depth) > tan_v:
                    fits = False
                    break
            if not fits:
                break
        if fits:
            return d
        d *= 1.03
    print("   ! could not frame the piece; using %.1f m" % d)
    return d


VIEW_YAW = [90.0, 40.0, 0.0, -90.0]


VIEWS = [("front", 90.0), ("threeq", 40.0), ("side", 0.0), ("back", -90.0)]

# What the turntable frames when the piece's own bounding box is the wrong
# answer.  A tethered balloon is 15% envelope and 85% empty air, so framing the
# whole assembly -- envelope, cables, mooring rig -- puts a 17 m hull in the top
# fifth of a 56 m frame and shows the cables end-on.  The turn pass frames the
# envelope instead, and the assembly gets its own single view.
FRAME_BOX = {
    "balloon": (Vector((-8.9, -4.4, 45.4)), Vector((8.7, 4.4, 56.6))),
}
# Pieces framed tighter than their own bounds get their turn views named for
# what is actually in them, so a file called `balloon_hull_side` is not read as
# a failed assembly view.
FRAME_NAME = {"balloon": "hull"}
ASSEMBLY_VIEW = {"balloon"}


def render(piece, size, lo, hi):
    """Turntable the piece so it can be judged without launching the game.

    Two passes: the whole piece, then the part of it that carries the art --
    the banner, the portrait, the gate markings.
    """
    flo, fhi = FRAME_BOX.get(piece, (lo, hi))
    fsize = fhi - flo
    tag = "%s_%s" % (piece, FRAME_NAME[piece]) if piece in FRAME_NAME \
        else piece
    aspect = frame_aspect(fsize)
    setup_studio_env(max(fsize.x, fsize.y, fsize.z), aspect,
                     centre=(flo + fhi) * 0.5)
    d = fit_distance(flo, fhi, aspect=aspect)
    mid_z = (flo.z + fhi.z) * 0.5
    gc.render_views(OUT_PREVIEW, tag, views=VIEWS, distance=d, height=mid_z)
    sc = bpy.context.scene
    sx, sy = sc.render.resolution_x, sc.render.resolution_y
    sc.render.resolution_x, sc.render.resolution_y = sx // 2, sy // 2
    gc.render_views(OUT_PREVIEW, tag, views=VIEWS, distance=d, height=mid_z,
                    silhouette=True)
    sc.render.resolution_x, sc.render.resolution_y = sx, sy

    if piece in ASSEMBLY_VIEW:
        asize = hi - lo
        setup_studio_env(max(asize.x, asize.y, asize.z), frame_aspect(asize),
                         centre=(lo + hi) * 0.5)
        gc.render_views(OUT_PREVIEW, "%s_assembly" % piece,
                        views=[("side", 0.0)],
                        distance=fit_distance(lo, hi,
                                              aspect=frame_aspect(asize)),
                        height=(lo.z + hi.z) * 0.5)

    # The close-up gets its own frame and aspect: inheriting the assembly's
    # would put an 8.4 m envelope inside a 56 m-tall frame and clip both flanks.
    dd, hh = DETAIL.get(piece, (d * 0.4, mid_z))
    setup_studio_env(max(size.x, size.y, size.z), DETAIL_ASPECT,
                     centre=(0.0, 0.0, hh))
    gc.render_views(OUT_PREVIEW, "%s_detail" % piece,
                    views=[("front", 90.0), ("threeq", 40.0)],
                    distance=dd, height=hh)
    print("   rendered to", OUT_PREVIEW,
          "(turn %.1f m in %d x %d, detail %.1f m)" % (d, sx, sy, dd))
    print("   check them with: python3 tools/check_renders.py .concept/env %s"
          % piece)


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

def build_one(piece, motto, slogan, do_render):
    print("== %s" % piece)
    gc.reset_scene()
    M = env_materials()
    # `note` is only what the log reports, so each piece says what it was asked
    # to carry: the monument its motto, the hung banner its slogan, the rest
    # nothing.
    note = ""
    if piece == "monument":
        parts, D = build_monument(M, motto)
        note = motto.replace("|", " / ")
    elif piece == "balloon":
        parts, D = build_balloon(M)
        note = "crescent"
    elif piece == "checkpoint":
        parts, D = build_checkpoint(M)
    elif piece == "banner":
        parts, D = build_banner(M, slogan)
        note = slogan.replace("|", " / ")
    elif piece == "billboard":
        parts, D = build_billboard(M)
    else:
        print("   ! no such piece: %s (have %s)" % (piece, ", ".join(PIECES)))
        return
    stats = export(piece, parts, D, note)
    if do_render:
        render(piece, stats["size"], stats["lo"], stats["hi"])


def main():
    names = PIECES if gc.flag("--all") else \
        [str(gc.arg("--piece", "monument"))]
    motto = str(gc.arg("--motto", MONUMENT_MOTTO))
    slogan = str(gc.arg("--slogan", ""))
    do_render = gc.flag("--render")
    built = 0
    for piece in names:
        if built:
            print("")
        build_one(piece, motto, slogan, do_render)
        built += 1
    print("== done (%d piece%s)" % (built, "" if built == 1 else "s"))


if __name__ == "__main__":
    main()
