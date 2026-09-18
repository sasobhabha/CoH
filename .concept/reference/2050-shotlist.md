# Reference reconstruction — "American Century of Humiliation: The Game"

Source: `GORM_THE_OLD_-_American_Century_of_Humiliation_The_Game_A.I._Video_Ho8lzs.mp4`
(60.1 s, 1344x768) — GORM THE OLD, 26 Aug 2026.
Premise, per the video's own description: *"a scenario where America experiences its
own 'Century of Humiliation'"* — `#ai #scifi #dystopian #satire`.

**Version 2 — corrected.** v1 was written from whole frames at 1 fps. This pass
re-examined the frames v1 could not resolve by magnifying the specific regions
(3x crops), asking the vision model one focused question per region, and **measuring**
the two things that decide the art direction (the flag's design, and whether any
text is legible). Several v1 claims did not survive. Those are listed first.

## 0. How this was produced, and how much to trust it

Nobody who wrote this file can see an image. Everything here came from tools:

* `ffmpeg` — 120 frames at 2 fps, then full-resolution frames at exact timestamps.
* `PIL` — 3x magnified crops of the relevant region per shot.
* `moondream` (ollama, local) — one question per crop, 30 questions.
* `numpy` + `scipy.ndimage` — hue/luminance per region, connected-component shape
  analysis, flag-signature tests.
* `tesseract` — OCR, including on the magnified crops.

**The model confabulates, and it does so fluently.** Across these crops it produced
tie-dye shirts, a guitar, a sword, a mop, a bow and arrow, and a "colourful
explosion in a field" — none of which recur in any other crop, all of which are
the shared visual vocabulary of its training data. Only statements it repeated
independently across crops, or that a measurement corroborates, are trusted below.
Everything else is marked.

The magnified crops are in `.concept/reference/crops/`, named by timestamp, with
the unresolved ones suffixed `_UNRESOLVED`. **They are the fastest way to correct
this file, and you can see them and nobody here can.**

## 1. Corrections to v1

| v1 claim | status after checking | evidence |
|---|---|---|
| "buildings are red with Chinese characters" | **withdrawn** | Asked directly on six different crops, the model answered *"no Chinese characters in this image"* every time. OCR of the magnified crops returned **zero** legible characters (Latin or otherwise — only `eng` is installed, so Han could not be read even if present). The commenter's note about Chinese text almost certainly refers to the end-card watermark, not scenery. |
| "a giant white head on top of the building" | **withdrawn — unresolved** | The frame is nearly achromatic and bright (saturated red 0.03%, yellow 0.00%, vivid 7%, mean luminance 67%). All three magnified crops failed on it, giving contradictory answers ("man in a doorway", "person peering out"). What is measurable is: **a large pale, overexposed mass filling the frame, identity unknown.** See `10_t45_white_mass_UNRESOLVED.png`. |
| "a burning American flag" | **downgraded to probable, unverified** | Two crops independently said American flag with red/white/blue stripes, burning, blue sky. But measurement could find **no stripe structure**: rows that are mostly red+white number 179 of 768, and across them the red share never exceeds 0.19, so there are **zero** red/white bands. The largest dark-blue blob is 764x152 px, aspect 5.0 — a sky/dark band, not a canton. Plausible (it is the natural reading of the title) but *not* confirmed by pixels. |
| "a red flag on the white building" | **confirmed, design now measured** | See §3. |
| "white-and-black robot" | **upgraded — corroborated** | Two crops independently: an armed person facing a machine/cyborg in front of a burning house, yellow houses, smoke. |
| "log cabin interior, radio on a desk" | **partially confirmed** | 88% of the frame is saturated orange at 18% luminance — firelight and wood, unambiguous. The model adds "man at a desk, a woman and a child, wooden walls, a lantern". The *radio* specifically is single-source. |
| "desert with a large white sphere, trucks, a fortress" | **partially confirmed** | A "large white ball/dome" is repeated across crops; "castle" appears once. Palette (orange 9%, mean 57%) supports bright warm ground. The trucks and fortress came from v1's whole-frame pass only. |

## 2. Measurements (unchanged from v1, still the most trustworthy layer)

| t | luminance | dominant | reads as |
|---|---|---|---|
| 0–13 s | 122–128 | `#4878a8 #78a8d8` blue | bright, blue-dominant |
| 14–18 s | 101–114 | grey + blue | overcast / grey mass |
| 19–26 s | 113–116 | grey + white | pale facade against grey |
| 26–29 s | 115–145 | blue + `#d8d8d8` | bright, busy |
| 36–42 s | 46–50 | `#181818 #481818 #784818` | dark, warm |
| 44 s | 156 | `#a8a8a8 #d8d8d8` | blown-out white |
| 48–55 s | 90–96 | `#484818 #787848` | olive / green |
| 56–60 s | 9 | near black | end card |

**27 cuts in 60 s — 2.2 s average.** Plus, new in this pass, per-shot colour
profiles (in `/tmp/vidcrop_report.txt`), which is what pinned the cabin (orange
88%), the field (yellow 30% / green 15%, i.e. sunlit grass) and the white mass
(achromatic).

## 3. The flag — measured, because it decides the art direction

All 120 frames were swept for two flag signatures: a red/white striped panel with
a cornered blue canton (US), and a saturated red field with yellow stars in one
corner and no striping (occupier).

**Exactly one rectangular red panel exists in the whole 60 s**, and only between
t≈17.5 s and t≈23.0 s — the shots already identified as the pale building:

```
t=18.0s  red panel 0.38% of frame  bbox 34x40 px  fill=0.72  aspect=0.85
         in-box: red=72.4%  white=0.0%  blue=0.5%  yellow=1.0%
         row white-fraction: std=0.000   alternating bands = 0
```

* **No white striping anywhere in the video.** A US flag panel would be ~50% white.
* The panel is **red-dominant with a small yellow element** (~1% of its area).
* Aspect 0.85 — taller than wide. A flag on a pole is 1.5:1; this reads as a
  **hung banner**, or a flag seen partly folded or cropped.

So: the occupier's red banner is real and measurable; the *star pattern* is not
resolvable. At half resolution the banner is 34x40 px, which puts each star at
1–3 px. If the design matters to Chapter I, it must be settled by eye.

**Consequence for building:** the ancient-2026 reading of "invaded by foreigners"
is not something this video states in-frame. The video shows a red banner on a
pale building, a red balloon with a face, a burning flag and a burning tower —
and the spoken line *"largest mobilization since the death of Elon Musk last
March… resistance cells"*. The occupier's identity is carried by the **balloon**
and the **banner**, not by legible signage, because there is none.

## 4. Shot list, corrected

| t | content | how solid |
|---|---|---|
| 0–4 s | city skyline, clear blue sky, river, boats, tall towers | measured + 2 captions |
| 5–9 s | large **burning flag**, blue sky | 2 captions; pattern unverified |
| 10–13 s | **fire on a tall building**, smoke, blue sky, city below | 2 captions + palette |
| 14–18 s | **large red balloon with a man's face** over a plaza; tents and buildings below; people on the street, some armed | 3 captions agree on the balloon; "armed" is 1 crop |
| 17.5–23 s | **pale building carrying a red banner** with a small yellow motif; people in the street | measured shape, 3 captions |
| 26–29 s | suburban street: burning house, yellow houses, an armed person facing a **machine/cyborg** | 2 captions + palette |
| 30–35 s | bright warm ground, a **large white dome/ball**, a person beside it | 2 captions + palette |
| 36–42 s | **wooden interior by firelight**, a few people, objects on a table | palette certain, contents 1 caption |
| 43–47 s | a **large pale mass filling the frame, overexposed** | **unresolved** |
| 48–55 s | **person walking away across a green field**, trees | 2 captions + palette |
| 56–60 s | black card, **"THANKS FOR WATCHING!"** | OCR |

Recovered dialogue (the only speech in the video, from the audio captions):
> "What are you trying to do, **Copperfield**?" · "**That'll be 10 bucks.**" ·
> "**Largest mobilization since the death of Elon Musk last March.** We continue to
> see **resistance cells** find their ..."

Comment-sourced (human eyes, so more trustworthy than the model): GTA-style open
world ("Grand Theft Měi Guó"), Far Cry comparisons, **lasers that vaporize people
into coloured powder**, the balloon, and that the in-frame Chinese reads *"please
like and subscribe, this video is purely satirical"*.

## 5. Still open, and cheap for you to close

1. `01_t07_burning_flag.png` — is the flag the US one, and is it burned/mostly gone?
2. `05b_t21_flag_zoom.png`, `06b_t24_monument_zoom.png` — the red banner: plain red,
   or red with stars? This single answer sets the signage and banner art.
3. `10_t45_white_mass_UNRESOLVED.png` — what is it? Nothing measurable survives.
4. `03b_t16_balloon_zoom.png` — whose face, and is there any text on the balloon?
5. `08_t32_white_dome.png` — is that structure a dome, a sphere, or a building?

## 6. What Chapter I should be built from

The video's own geography, in order: skyline → burning flag → burning tower →
plaza under the balloon → pale monument with the red banner → the resistance.
So Chapter I is the **occupied plaza**: the approach past a burning tower, the
open square with the tethered balloon overhead, the pale monument draped with the
red banner, patrols and a checkpoint around it, and the way out to the resistance.

Kit, unchanged from v1 except that **signage is now Latin-only** (there is no Han
in frame to copy): modular US street facades, the pale monument + draped red
banner, the tethered balloon, checkpoints, hung banners, patrol vehicles, rubble
and props, and a wooden safehouse interior as a separate scene.
