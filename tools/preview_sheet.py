#!/usr/bin/env python3
"""
Contact sheet for the character pipeline previews.

Collects every render in `.concept/chars` and writes `.concept/chars/gallery.html`
so the model can be reviewed in a browser next to the renders themselves.

    python3 tools/preview_sheet.py [--dir .concept/chars] [--title "..."]

Renders are grouped by the prefix before the first underscore (the variant) and
ordered so beauty views, silhouettes and close-ups read as separate rows.
"""

import argparse
import glob
import os
import re

GROUP_ORDER = ["front", "threeq", "side", "back", "head", "sil"]


def classify(filename: str) -> str:
    stem = os.path.splitext(os.path.basename(filename))[0]
    parts = stem.split("_")
    if parts[0] == "anim":
        return "motion"
    if parts[0] == "intro":
        return "intro"
    if "sil" in parts:
        return "silhouette"
    if "head" in parts:
        return "head"
    return "beauty"


def sort_key(filename: str):
    stem = os.path.splitext(os.path.basename(filename))[0]
    for i, token in enumerate(GROUP_ORDER):
        if token in stem.split("_") or stem.endswith(token):
            return (0 if "sil" not in stem else 1, i, stem)
    return (2, 0, stem)


def build(directory: str, title: str, out_path: str) -> str:
    files = sorted(
        (f for f in glob.glob(os.path.join(directory, "*.png"))
         if not os.path.basename(f).startswith("s_")),
        key=sort_key,
    )
    if not files:
        raise SystemExit("no previews found in %s" % directory)

    sections = {"beauty": [], "head": [], "motion": [], "intro": [],
                "silhouette": []}
    for f in files:
        sections[classify(f)].append(f)
    # frames read best in their own sequence order
    sections["motion"].sort()
    sections["intro"].sort()

    bodies = []
    for name, caption in (("beauty", "beauty"), ("head", "close-up"),
                          ("intro", "chapter I intro — camera drift"),
                          ("motion", "animation — sampled frames"),
                          ("silhouette", "silhouette (alpha, matted)")):
        group = sections[name]
        if not group:
            continue
        tiles = []
        for f in group:
            rel = os.path.relpath(f, directory)
            stem = os.path.splitext(rel)[0]
            # Keep the archetype in every caption: with five meshes in the
            # sheet, a caption of just "front" four times over says nothing
            # about which body you are looking at.
            label = stem.replace("_mesh", "").replace("_", " ")
            cls = "tile sil" if name == "silhouette" else "tile"
            tiles.append(
                '<figure class="%s"><a href="%s" target="_blank">'
                '<img src="%s" alt="%s" loading="lazy"></a>'
                '<figcaption>%s</figcaption></figure>' % (cls, rel, rel, label, label)
            )
        bodies.append(
            '<h2>%s <span>%d</span></h2>\n<div class="grid">%s</div>'
            % (caption, len(group), "".join(tiles))
        )

    html = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>%s</title><style>
:root{--bg:#0a0c0e;--fg:#c9d2d8;--dim:#6b7a84;--amber:#e0a05a;}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
     font:13px/1.45 ui-monospace,SFMono-Regular,Menlo,monospace}
header{position:sticky;top:0;z-index:9;background:#0a0c0e;border-bottom:1px solid #1d2429;
       padding:11px 18px;display:flex;gap:22px;align-items:baseline;flex-wrap:wrap}
h1{font-size:14px;letter-spacing:.2em;margin:0;font-weight:600}
h1 small{color:var(--dim);letter-spacing:.08em;font-weight:400}
.ctl{display:flex;align-items:center;gap:9px;color:var(--dim)}
input[type=range]{width:200px;accent-color:var(--amber)}
output{color:var(--amber);min-width:3.4em}
h2{font-size:12px;letter-spacing:.16em;text-transform:uppercase;color:var(--amber);
   margin:22px 18px 8px;font-weight:600}
h2 span{color:var(--dim);letter-spacing:0}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:12px;
      padding:0 18px 6px}
figure{margin:0;background:#101418;border:1px solid #1d2429;border-radius:3px;
       overflow:hidden}
figure.sil{background:repeating-conic-gradient(#15181b 0%% 25%%,#101316 0%% 50%%) 0/18px 18px}
img{display:block;width:100%%;height:auto;filter:brightness(var(--b,1))}
figcaption{padding:5px 8px;border-top:1px solid #1d2429;color:var(--dim);font-size:12px}
a{display:block}
p.note{color:var(--dim);padding:4px 18px 34px;max-width:940px}
code{color:var(--amber)}
</style></head><body>
<header><h1>CENTURY OF HUMILIATION <small>%s</small></h1>
<div class="ctl"><label for="b">exposure</label>
<input id="b" type="range" min="1" max="5" step="0.1" value="1">
<output id="bo">1.0&times;</output></div></header>
%s
<p class="note">Built by <code>tools/preview_sheet.py</code> from <code>%s</code>.
Silhouette tiles are rendered with a transparent film so the alpha is the outline --
use them to judge proportion and readability, not shape detail. Click any tile to
open the full-size render.</p>
<script>
const b=document.getElementById('b'),bo=document.getElementById('bo');
b.addEventListener('input',()=>{document.documentElement.style.setProperty('--b',b.value);
  bo.textContent=Number(b.value).toFixed(1)+'\\u00d7';});
</script>
</body></html>""" % (title, title, "".join(bodies), directory)

    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(html)
    return out_path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=".concept/chars")
    ap.add_argument("--title", default="character previews")
    args = ap.parse_args()
    out = os.path.join(args.dir, "gallery.html")
    print("wrote", build(args.dir, args.title, out))


if __name__ == "__main__":
    main()
