#!/usr/bin/env python3
"""
Measure rendered previews, because nobody here can look at them.

    python3 tools/check_renders.py .concept/env monument
    python3 tools/check_renders.py .concept/chars heavy
    python3 tools/check_renders.py .concept/caps ""

This exists because of a bug that shipped once already: the character beauty
renders were shot from the leftover death pose, so a review sheet full of
perfectly valid PNGs showed a 1.9 m character as 114 px of shoulder in the
corner of the frame.  Nothing errored.  The export was fine.  The images were
simply empty, and an empty image is not a crash.

So every preview is checked here for the three ways a render lies about having
worked: the subject is not in the frame at all, it is too small to judge, or it
is clipped by the frame edge.

Run this under the *system* python3: Blender's bundled interpreter has no PIL.

Exit code is 1 if any image is empty, so it can gate a build.
"""

import glob
import os
import sys

import numpy as np
from PIL import Image

# The studio backdrop is flat, so a piece is "present" where the luminance
# departs from the corner sample by more than the noise floor of the AO pass.
TOL = 0.045
MIN_PRESENT = 0.005      # < 0.5% of the frame: nothing useful is on screen
MIN_USEFUL = 0.030       # < 3%: present but too small to judge a silhouette
EDGE = 2                 # pixels; closer than this to the border means clipped


def backdrop_level(a, rgb):
    """Sample the flat studio background from the four corners."""
    h, w = a.shape
    k = max(4, min(h, w) // 20)
    patches = [a[:k, :k], a[:k, -k:], a[-k:, :k], a[-k:, -k:]]
    return float(np.median(np.concatenate([p.ravel() for p in patches])))


def largest_component(mask):
    """Keep only the biggest blob, so a bright reflection cannot count as the
    subject and the reported box stays honest."""
    try:
        from scipy import ndimage
    except Exception:                                    # noqa: BLE001
        return mask, 1
    labels, n = ndimage.label(mask)
    if n <= 1:
        return mask, n
    sizes = ndimage.sum(mask, labels, range(1, n + 1))
    keep = int(np.argmax(sizes)) + 1
    return labels == keep, n


def check(path):
    img = Image.open(path)
    rgb = np.asarray(img.convert("RGB"), dtype=np.float32) / 255.0
    a = np.asarray(img.convert("L"), dtype=np.float32) / 255.0
    h, w = a.shape

    alpha = None
    if img.mode in ("RGBA", "LA") or "transparency" in img.info:
        alpha = np.asarray(img.convert("RGBA"), dtype=np.float32)[..., 3] / 255.0

    if alpha is not None and float((alpha < 0.5).mean()) > 0.02:
        # a silhouette pass: the alpha channel *is* the answer, no thresholding
        mask = alpha >= 0.5
        kind = "sil"
        bg = 0.0
    else:
        bg = backdrop_level(a, rgb)
        mask = np.abs(a - bg) > TOL
        mask, _ = largest_component(mask)
        kind = "rgb"

    present = float(mask.mean())
    touches = False
    if present > 0.0:
        ys, xs = np.where(mask)
        y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
        touches = (y0 <= EDGE or x0 <= EDGE or y1 >= h - 1 - EDGE
                   or x1 >= w - 1 - EDGE)
        box = (x0 / w, x1 / w, y0 / h, y1 / h)
    else:
        box = (0.0, 0.0, 0.0, 0.0)

    # A close-up (`*_detail_*`) or a deliberately tight view of one part
    # (`*_hull_*`) is *meant* to run off the frame -- that is what makes it a
    # close-up -- so only "is there anything there at all" is asked of it.  For
    # a turntable view, "too small" has to mean small in both axes: a 56 m
    # tethered balloon is 2% of a portrait frame by area while correctly
    # filling its full height, and flagging that is the checker being wrong,
    # not the render.
    name = os.path.basename(path)
    close_up = "_detail" in name or "_hull_" in name
    span_x = box[1] - box[0]
    span_y = box[3] - box[2]
    notes = []
    if present < MIN_PRESENT:
        notes.append("EMPTY")
    elif not close_up:
        if span_x < 0.35 and span_y < 0.35:
            notes.append("TOO SMALL")
        if touches:
            notes.append("CLIPPED")

    mean_subject = 0.0
    if present > 0.0:
        mean_subject = float(a[mask].mean())

    return {
        "file": os.path.basename(path), "kind": kind, "present": present,
        "box": box, "subject_l": mean_subject, "bg": bg,
        "notes": notes,
    }


def main():
    args = [a for a in sys.argv[1:]]
    root = args[0] if args else ".concept/env"
    prefix = args[1] if len(args) > 1 else ""
    pattern = os.path.join(root, "%s_*.png" % prefix if prefix else "*.png")
    files = sorted(glob.glob(pattern))
    if not files:
        print("no images matched", pattern)
        return 1
    bad = 0
    worst = []
    for f in files:
        try:
            r = check(f)
        except Exception as exc:                          # noqa: BLE001
            print("%-38s ! unreadable: %s" % (os.path.basename(f), exc))
            bad += 1
            continue
        b = r["box"]
        print("%-38s %-3s present=%5.2f%%  box x%.2f-%.2f y%.2f-%.2f  L=%.2f  %s"
              % (r["file"], r["kind"], r["present"] * 100.0, b[0], b[1], b[2],
                 b[3], r["subject_l"], " ".join(r["notes"])))
        if r["notes"]:
            bad += 1
            worst.append(r["file"])
    print("-- %d image%s, %d flagged%s"
          % (len(files), "" if len(files) == 1 else "s", bad,
             (": " + ", ".join(worst)) if worst else ""))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
