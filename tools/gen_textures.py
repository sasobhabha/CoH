#!/usr/bin/env python3
"""Generate the CENTURY OF HUMILIATION texture library.

Every surface in the game is authored here rather than sourced, so the whole
look is reproducible from this one file.  Noise is built in the frequency
domain, which makes every map tile seamlessly by construction -- there is no
seam blending pass and no wrap-around artefact when a 40 m wall uses a 2 m
texture.

Outputs, per material:
    assets/textures/<name>_alb.png     sRGB albedo
    assets/textures/<name>_nrm.png     tangent-space normal (OpenGL, +Y up)
    assets/textures/<name>_rgh.png     roughness, stored in the red channel
    assets/textures/manifest.json      tile size in metres + shading params

Run:  python3 tools/gen_textures.py
"""

import json
import math
import os
import struct
import zlib

import numpy as np

S = 512
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "textures")


# --------------------------------------------------------------------- output

def to_srgb(x):
    """Linear -> sRGB.

    This matters more than anything else in this file.  Godot decodes albedo
    textures from sRGB to linear (samplers are declared `source_color`), so
    writing raw linear values into an albedo PNG makes every surface in the game
    roughly five times darker than it was authored -- which in practice means
    over-lighting everything and wondering why the shots look flat.

    Normals and roughness are sampled raw and must NOT be encoded.
    """
    x = np.clip(x, 0.0, 1.0)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1.0 / 2.4) - 0.055)


def write_png(path, arr):
    """Minimal PNG writer so the pipeline needs nothing but numpy."""
    arr = np.ascontiguousarray(np.clip(arr, 0.0, 1.0))
    if arr.dtype != np.uint8:
        arr = (arr * 255.0 + 0.5).astype(np.uint8)
    h, w, c = arr.shape
    ctype = {1: 0, 3: 2, 4: 6}[c]
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw += arr[y].tobytes()

    def chunk(tag, data):
        body = tag + data
        return (struct.pack(">I", len(data)) + body
                + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ctype, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 6))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


# ---------------------------------------------------------------------- noise

def fbm(seed, beta, size=S):
    """Tileable fractal noise: white noise shaped by a 1/f^beta spectrum.

    Working in the frequency domain means the result is periodic by
    construction, which is exactly what a repeating texture needs.
    """
    rng = np.random.default_rng(seed)
    n = rng.standard_normal((size, size))
    fy = np.fft.fftfreq(size)[:, None]
    fx = np.fft.fftfreq(size)[None, :]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = f[0, 1]
    amp = 1.0 / np.power(f, beta)
    amp[0, 0] = 0.0
    out = np.real(np.fft.ifft2(np.fft.fft2(n) * amp))
    out -= out.mean()
    sd = out.std()
    return out / (sd if sd > 1e-9 else 1.0)


def n01(x):
    """Normal-ish noise -> 0..1 centred on 0.5."""
    return np.clip(0.5 + x * 0.24, 0.0, 1.0)


def ramp(x):
    """Normal-ish noise -> 0..1 across the full range (for masks)."""
    return np.clip(0.5 + x * 0.40, 0.0, 1.0)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a + 1e-9), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def grid_lines(size, cols, rows, width, phase=0.0):
    """1.0 exactly on panel joints, 0.0 elsewhere.  Tiles by construction."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    u = (xx + 0.5) / size * cols
    v = (yy + 0.5) / size * rows
    du = np.abs((u % 1.0) - 0.5)
    dv = np.abs((v % 1.0) - 0.5)
    line = np.maximum(smoothstep(0.5 - width, 0.5, du),
                      smoothstep(0.5 - width, 0.5, dv))
    if phase:
        line = np.maximum(line, 0.0)
    return line


def ridge(x):
    """Ridged transform -- turns noise into crack-like filaments."""
    return 1.0 - np.abs(x)


def height_to_normal(h, strength):
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    nx = -dx * strength
    ny = dy * strength
    nz = np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / ln * 0.5 + 0.5,
                     ny / ln * 0.5 + 0.5,
                     nz / ln * 0.5 + 0.5], axis=-1)


def tint(h, lo, hi):
    """Map a 0..1 field onto a two-colour gradient."""
    lo = np.asarray(lo, dtype=np.float64)
    hi = np.asarray(hi, dtype=np.float64)
    return lo[None, None, :] + (hi - lo)[None, None, :] * h[..., None]


def tint3(h, lo, mid, hi):
    lo = np.asarray(lo, dtype=np.float64)
    mid = np.asarray(mid, dtype=np.float64)
    hi = np.asarray(hi, dtype=np.float64)
    a = lo[None, None, :] + (mid - lo)[None, None, :] * np.clip(h * 2.0, 0, 1)[..., None]
    b = mid[None, None, :] + (hi - mid)[None, None, :] * np.clip((h - 0.5) * 2.0, 0, 1)[..., None]
    w = smoothstep(0.35, 0.65, h)[..., None]
    return a * (1.0 - w) + b * w


def vstreak(seed, beta=2.4, squash=8.0):
    """Vertical streaking -- water running down a wall."""
    n = fbm(seed, beta)
    # squash along X so features are tall and thin, then re-normalise
    fy = np.fft.fftfreq(S)[:, None]
    fx = np.fft.fftfreq(S)[None, :] * squash
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = f[0, 1]
    rng = np.random.default_rng(seed + 7717)
    w = rng.standard_normal((S, S))
    out = np.real(np.fft.ifft2(np.fft.fft2(w) / np.power(f, beta)))
    out -= out.mean()
    sd = out.std()
    return out / (sd if sd > 1e-9 else 1.0)


# ---------------------------------------------------------------- materials

def mat_concrete(seed, base, panel=True):
    """Cast concrete panels.  `base` is the clean colour."""
    grime = fbm(seed, 2.9)
    fine = fbm(seed + 1, 1.25)
    blotch = fbm(seed + 2, 3.4)
    h = grime * 0.5 + fine * 0.22
    joints = grid_lines(S, 2, 2, 0.012) if panel else np.zeros((S, S))
    h -= joints * 1.4

    a = n01(grime) * 0.55 + n01(fine) * 0.45
    alb = tint(a, [c * 0.62 for c in base], [c * 1.12 for c in base])
    # soot / water staining
    stain = smoothstep(0.55, 0.85, ramp(blotch))
    alb *= (1.0 - 0.42 * stain)[..., None]
    streak = smoothstep(0.5, 0.95, ramp(vstreak(seed + 9)))
    alb *= (1.0 - 0.30 * streak)[..., None]
    alb *= (1.0 - 0.55 * joints)[..., None]

    rough = 0.80 + 0.10 * n01(fine) - 0.12 * stain
    return alb, h, rough


def mat_asphalt(seed):
    # Aggregate has to be *coarse*.  A 1/f^1 spectrum is per-pixel noise that
    # shimmers into a black-and-white haze at any distance; asphalt seen from
    # eye height is a broad mottle with a few sharp cracks.
    agg = fbm(seed, 1.75)
    patch = fbm(seed + 1, 3.2)
    tar = ridge(fbm(seed + 2, 2.6))
    crack = smoothstep(0.94, 1.0, tar)
    cracks2 = smoothstep(0.90, 1.0, ridge(fbm(seed + 6, 2.0)))

    h = agg * 0.22 + patch * 0.5 + crack * 1.2
    a = n01(agg) * 0.6 + n01(patch) * 0.4
    alb = tint(a, (0.055, 0.058, 0.062), (0.21, 0.215, 0.225))
    # resurfaced patches are lighter and smoother
    p = smoothstep(0.55, 0.9, ramp(patch))
    alb = alb * (1 - p[..., None]) + np.array([0.12, 0.125, 0.13]) * p[..., None]
    alb *= (1.0 - 0.75 * crack)[..., None]
    alb *= (1.0 - 0.35 * cracks2)[..., None]
    rough = 0.90 + 0.07 * n01(agg) - 0.16 * p
    return alb, h, rough


def mat_plaster(seed, base):
    grain = fbm(seed, 1.5)
    peel = smoothstep(0.45, 0.9, ramp(fbm(seed + 3, 2.7)))
    reveal = fbm(seed + 4, 2.2)
    h = grain * 0.22 - peel * 0.9 + reveal * 0.2

    a = n01(grain) * 0.5 + n01(reveal) * 0.5
    alb = tint(a, [c * 0.72 for c in base], [c * 1.10 for c in base])
    # where the render has fallen away the brick core shows through
    core = tint(n01(reveal), (0.30, 0.20, 0.16), (0.46, 0.31, 0.24))
    alb = alb * (1 - peel[..., None]) + core * peel[..., None]
    alb *= (1.0 - 0.25 * smoothstep(0.6, 0.95, ramp(vstreak(seed + 8))))[..., None]
    rough = 0.86 + 0.08 * n01(grain) + 0.06 * peel
    return alb, h, rough


def mat_brick(seed, base):
    cols, rows = 5, 14
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    v = (yy + 0.5) / S * rows
    row = np.floor(v)
    u = (xx + 0.5) / S * cols + (row % 2) * 0.5
    fu = u % 1.0
    fv = v % 1.0
    mortar = np.maximum(smoothstep(0.40, 0.5, np.abs(fu - 0.5)),
                        smoothstep(0.36, 0.5, np.abs(fv - 0.5)))
    mortar = np.clip(mortar, 0, 1)

    per = np.random.default_rng(seed).random((int(rows) + 2, int(cols) + 2))
    idx_r = (row.astype(int) % (per.shape[0])) 
    idx_c = ((np.floor(u)).astype(int) % per.shape[1])
    vary = per[idx_r.clip(0, per.shape[0] - 1), idx_c.clip(0, per.shape[1] - 1)]

    grain = fbm(seed + 5, 1.2)
    chip = smoothstep(0.78, 1.0, ramp(fbm(seed + 6, 1.9)))
    h = (1.0 - mortar) * 1.0 + grain * 0.25 - chip * 0.7

    a = np.clip(mortar * 0.5 + vary * 0.35 + n01(grain) * 0.3, 0, 1)
    alb = tint(a, [c * 0.62 for c in base], [c * 1.25 for c in base])
    mot = tint(n01(fbm(seed + 11, 1.6)), (0.36, 0.355, 0.335), (0.52, 0.505, 0.475))
    alb = alb * (1 - mortar[..., None]) + mot * mortar[..., None]
    alb *= (1.0 - 0.35 * chip)[..., None]
    rough = 0.88 + 0.06 * n01(grain) + 0.05 * mortar
    return alb, h, rough


def mat_metal_painted(seed, base, worn=0.55):
    scratch = smoothstep(0.80, 1.0, ridge(fbm(seed, 1.7)))
    dent = fbm(seed + 1, 2.6)
    panel = grid_lines(S, 3, 3, 0.006)
    h = dent * 0.35 + scratch * 0.5 - panel * 0.5

    a = n01(dent) * 0.7 + 0.3
    alb = tint(a, [c * 0.82 for c in base], [c * 1.08 for c in base])
    steel = tint(n01(fbm(seed + 2, 2.0)), (0.26, 0.27, 0.285), (0.44, 0.455, 0.47))
    wear = np.clip(scratch * worn + smoothstep(0.55, 0.95, ramp(fbm(seed + 3, 2.9))) * worn * 0.5, 0, 1)
    alb = alb * (1 - wear[..., None]) + steel * wear[..., None]
    alb *= (1.0 - 0.30 * panel)[..., None]
    rough = 0.42 + 0.22 * n01(dent) + 0.24 * wear
    return alb, h, rough


def mat_metal_rust(seed, steel=(0.30, 0.31, 0.325)):
    rust_mask = smoothstep(0.35, 0.95, ramp(fbm(seed, 2.5)))
    deep = smoothstep(0.55, 1.0, ramp(fbm(seed + 1, 3.1)))
    pit = fbm(seed + 2, 1.15)
    h = rust_mask * 0.6 + pit * 0.5 - deep * 0.3

    a = np.clip(n01(pit) * 0.5 + rust_mask * 0.6, 0, 1)
    alb = tint(a, (0.26, 0.145, 0.075), (0.62, 0.30, 0.13))
    dark = tint(n01(fbm(seed + 3, 3.0)), (0.16, 0.10, 0.06), (0.30, 0.17, 0.09))
    alb = alb * (1 - deep[..., None]) + dark * deep[..., None]
    bare = tint(n01(fbm(seed + 4, 1.9)), steel,
                tuple(min(1.0, c * 1.5) for c in steel))
    alb = alb * rust_mask[..., None] + bare * (1 - rust_mask)[..., None]
    rough = 0.58 + 0.30 * rust_mask + 0.08 * n01(pit)
    return alb, h, rough


def mat_wood(seed, base, planks=4, vertical=True):
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    along = xx if vertical else yy
    across = yy if vertical else xx
    v = (across + 0.5) / S * planks
    gap = smoothstep(0.44, 0.5, np.abs((v % 1.0) - 0.5))
    plank_id = np.floor(v)

    grain_raw = fbm(seed, 1.55)
    fy = np.fft.fftfreq(S)[:, None]
    fx = np.fft.fftfreq(S)[None, :]
    stretch = 7.0 if vertical else 1.0 / 7.0
    f = np.sqrt((fx * stretch) ** 2 + (fy / (stretch if stretch else 1.0)) ** 2)
    f[0, 0] = f[0, 1]
    rng = np.random.default_rng(seed + 31)
    w = rng.standard_normal((S, S))
    grain = np.real(np.fft.ifft2(np.fft.fft2(w) / np.power(f, 1.9)))
    grain = (grain - grain.mean()) / (grain.std() + 1e-9)

    knot = smoothstep(0.72, 1.0, ramp(fbm(seed + 7, 2.4)))
    h = grain * 0.5 + (1.0 - gap) * 0.3 - gap * 1.2 - knot * 0.5

    per = np.random.default_rng(seed + 3).random(planks + 2)
    shade = per[(plank_id.astype(int) % (planks + 2)).clip(0, planks + 1)]
    a = np.clip(n01(grain) * 0.7 + shade * 0.4, 0, 1)
    alb = tint(a, [c * 0.60 for c in base], [c * 1.20 for c in base])
    alb *= (1.0 - 0.7 * gap)[..., None]
    alb *= (1.0 - 0.45 * knot)[..., None]
    return alb, h, 0.78 + 0.10 * n01(grain)


def mat_ground(seed, base, pebbles=0.0, blades=0.0):
    clump = fbm(seed, 2.7)
    fine = fbm(seed + 1, 1.1)
    macro = fbm(seed + 2, 3.6)
    h = fine * 0.35 + clump * 0.4

    a = n01(fine) * 0.45 + n01(macro) * 0.55
    alb = tint3(a, [c * 0.55 for c in base], base, [min(1.0, c * 1.35) for c in base])
    if pebbles > 0.0:
        stone = smoothstep(0.80, 1.0, ramp(fbm(seed + 4, 1.05)))
        stone_col = tint(n01(fbm(seed + 5, 1.4)), (0.30, 0.295, 0.28), (0.60, 0.585, 0.555))
        alb = alb * (1 - stone[..., None] * pebbles) + stone_col * (stone * pebbles)[..., None]
        h += stone * pebbles * 1.2
    if blades > 0.0:
        b = smoothstep(0.62, 0.95, ramp(vstreak(seed + 6, 2.0, 16.0)))
        alb *= (1.0 + 0.30 * b)[..., None]
        h += b * blades * 0.6
    rough = 0.92 + 0.06 * n01(fine)
    return np.clip(alb, 0, 1), h, rough


def mat_rock(seed, base):
    lump = fbm(seed, 3.2)
    frac = smoothstep(0.72, 1.0, ridge(fbm(seed + 1, 2.2)))
    fine = fbm(seed + 2, 1.2)
    h = lump * 1.0 + fine * 0.2 - frac * 0.9
    a = n01(lump) * 0.6 + n01(fine) * 0.4
    alb = tint(a, [c * 0.55 for c in base], [c * 1.20 for c in base])
    alb *= (1.0 - 0.45 * frac)[..., None]
    moss = smoothstep(0.68, 1.0, ramp(fbm(seed + 3, 3.0)))
    alb = alb * (1 - moss[..., None] * 0.55) + np.array([0.18, 0.26, 0.11]) * (moss * 0.55)[..., None]
    return np.clip(alb, 0, 1), h, 0.90 + 0.06 * n01(fine)


def mat_fabric(seed, base):
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    weave = (np.sin(xx / S * math.tau * 128.0) * np.sin(yy / S * math.tau * 128.0)) * 0.5 + 0.5
    fiber = fbm(seed, 1.5)
    dirt = smoothstep(0.45, 0.95, ramp(fbm(seed + 1, 2.9)))
    h = weave * 0.35 + fiber * 0.35
    a = np.clip(weave * 0.35 + n01(fiber) * 0.5 + 0.15, 0, 1)
    alb = tint(a, [c * 0.70 for c in base], [c * 1.15 for c in base])
    alb *= (1.0 - 0.35 * dirt)[..., None]
    return alb, h, 0.90 + 0.05 * n01(fiber)


def mat_roof(seed):
    patch = fbm(seed, 2.8)
    agg = fbm(seed + 1, 1.05)
    seam = grid_lines(S, 1, 3, 0.014)
    h = patch * 0.6 + agg * 0.3 - seam * 0.8
    a = n01(patch) * 0.6 + n01(agg) * 0.4
    alb = tint(a, (0.045, 0.046, 0.050), (0.16, 0.155, 0.150))
    alb *= (1.0 - 0.4 * seam)[..., None]
    return alb, h, 0.93 + 0.05 * n01(agg)


def mat_grunge(seed):
    """RGBA decal: dark soot/water staining with a soft alpha edge."""
    blot = fbm(seed, 3.0)
    streak = vstreak(seed + 4, 2.2)
    fine = fbm(seed + 1, 1.3)
    m = np.clip(ramp(blot) * 0.7 + ramp(streak) * 0.5 + n01(fine) * 0.2 - 0.45, 0, 1)
    m = smoothstep(0.15, 0.85, m)
    a = m * 0.85
    rgb = tint(n01(fine), (0.03, 0.028, 0.026), (0.12, 0.11, 0.10))
    return np.concatenate([rgb, a[..., None]], axis=-1), m, None


# ------------------------------------------------------------------ registry

MATERIALS = [
    # name,            generator args,                                      tile_m, rough, metal, nrm
    ("concrete",      lambda: mat_concrete(101, (0.40, 0.405, 0.41)),        4.0, None, 0.0, 1.3),
    ("concrete_dark", lambda: mat_concrete(102, (0.235, 0.238, 0.245)),      4.0, None, 0.0, 1.5),
    ("concrete_floor", lambda: mat_concrete(103, (0.320, 0.322, 0.318), False), 4.0, None, 0.0, 1.1),
    ("asphalt",       lambda: mat_asphalt(104),                             10.0, None, 0.0, 1.1),
    ("plaster",       lambda: mat_plaster(105, (0.560, 0.505, 0.425)),       2.4, None, 0.0, 2.0),
    ("plaster_blue",  lambda: mat_plaster(106, (0.330, 0.400, 0.430)),       2.4, None, 0.0, 2.0),
    ("brick",         lambda: mat_brick(107, (0.400, 0.255, 0.205)),         1.4, None, 0.0, 2.4),
    ("steel_paint",   lambda: mat_metal_painted(108, (0.300, 0.345, 0.330)), 2.0, None, 0.35, 1.6),
    ("steel_red",     lambda: mat_metal_painted(109, (0.430, 0.180, 0.140), 0.7), 2.0, None, 0.35, 1.6),
    ("steel_rust",    lambda: mat_metal_rust(110),                           2.0, None, 0.45, 2.0),
    ("wood",          lambda: mat_wood(111, (0.290, 0.205, 0.130), 4, True), 1.6, None, 0.0, 1.8),
    ("wood_pale",     lambda: mat_wood(112, (0.480, 0.390, 0.270), 5, False), 1.8, None, 0.0, 1.6),
    ("dirt",          lambda: mat_ground(113, (0.255, 0.200, 0.140), 0.35),   3.0, None, 0.0, 2.0),
    ("gravel",        lambda: mat_ground(114, (0.300, 0.288, 0.265), 0.85),   6.0, None, 0.0, 1.3),
    ("grass",         lambda: mat_ground(115, (0.215, 0.320, 0.110), 0.0, 1.0), 4.0, None, 0.0, 2.2),
    ("roof",          lambda: mat_roof(116),                                 4.0, None, 0.0, 2.0),
    ("rock",          lambda: mat_rock(117, (0.330, 0.325, 0.310)),          3.0, None, 0.0, 2.6),
    ("canvas",        lambda: mat_fabric(118, (0.395, 0.355, 0.265)),        1.6, None, 0.0, 2.0),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest = {}
    total = 0
    for name, fn, tile, rough, metal, nrm in MATERIALS:
        alb, h, rgh = fn()
        write_png(os.path.join(OUT, f"{name}_alb.png"), to_srgb(alb))
        write_png(os.path.join(OUT, f"{name}_nrm.png"), height_to_normal(h, nrm))
        if rgh is not None:
            write_png(os.path.join(OUT, f"{name}_rgh.png"),
                      np.repeat(rgh[..., None], 3, axis=-1))
        entry = {"tile_m": tile, "metallic": metal, "normal_strength": 1.0}
        if rough is not None:
            entry["roughness"] = rough
        manifest[name] = entry
        total += 1
        print(f"  {name:16s} tile={tile:>4.1f}m")

    # one decal for wall-base grime
    g, _, _ = mat_grunge(210)
    write_png(os.path.join(OUT, "grunge_alb.png"),
              np.concatenate([to_srgb(g[..., :3]), g[..., 3:]], axis=-1))
    manifest["_decal_grunge"] = {"tile_m": 4.0}

    with open(os.path.join(OUT, "manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=1, sort_keys=True)
    print(f"\n{total} materials -> {OUT}")


if __name__ == "__main__":
    main()
