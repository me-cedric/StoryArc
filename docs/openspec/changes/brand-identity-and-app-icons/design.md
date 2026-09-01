# Design — brand identity and app icons

## The colours, measured rather than eyeballed

The supplied artwork is raster, and the token file is authored in OKLCH. One of the two has
to be converted and it is not the token file. Sampled on 2026-09-01 by decoding the PNGs
(a 40-line pure-Python reader, the inverse of the fixture corpus's own hand-written encoder)
and taking the median of a 28×28 patch inside each petal, away from the gloss highlight along
each top edge and the bevel along each bottom:

| Sample | sRGB | OKLCH |
| --- | --- | --- |
| Icon, pink end | `#FD5EA8` | `oklch(70.9% 0.205 355)` |
| Icon, violet end | `#6D33E9` | `oklch(51.6% 0.249 289)` |
| Lockup, pink | `#FE649A` | `oklch(71.3% 0.193 2)` |
| Lockup, magenta | `#EB4CC9` | `oklch(67.7% 0.233 338)` |
| Lockup, violet | `#883FFB` | `oklch(57.1% 0.257 294)` |
| Lockup, blue-violet | `#2B51FD` | `oklch(53.2% 0.256 267)` |

**The two renders disagree at the violet end** — the icon finishes at hue 289 and the lockup
runs on to 267, which is blue. They are separate generations of the same idea, so the arc is
taken as **pink 357 → violet 291** and the blue tail is treated as drift rather than as
intent.

### The one fact that makes this cheap

**The brand pink lands at L≈71% and the accent it replaces sits at L=70%.** So this is a hue
rotation at constant lightness, and every contrast relationship the token gate already
validates is preserved rather than re-argued.

| Token | Was | Becomes | Gate | Measured |
| --- | --- | --- | --- | --- |
| `accent` (was `ember`) | `oklch(70% 0.165 52)` → `#EC7C27`, 6.91:1 on dark | `oklch(70% 0.19 357)` → `#F662A0` | ≥3.0 on `dark.surfaceCanvas` | **6.63:1**, and 7.17:1 on OLED |
| `accentStrong` (was `emberStrong`) | `oklch(62% 0.165 48)` → `#D2600C`, 3.59:1 on light | `oklch(62% 0.19 357)` → `#D94788` | ≥3.0 on `light.surfaceCanvas` | **3.74:1** |
| `accentMuted` (was `emberMuted`) | `oklch(45% 0.090 52)` | `oklch(45% 0.09 357)` | ungated (rails at rest) | 2.48:1, as before |
| `arcEnd` *(new)* | — | `oklch(56% 0.23 291)` → `#7C4AED` | identity only, so ungated as a text colour | 3.75:1 on dark, 4.80:1 on light |

Every value is inside sRGB: a round trip back through OKLCH returns the same chroma, so none
of them is a clipped colour pretending to a saturation it does not have. `C 0.20 H357` at
L72% was checked too and is also in gamut; 0.19 is chosen because it sits nearer the two
renders' average than either.

### Why the violet is identity-only

`brand.ink` — the existing secondary — is `oklch(48% 0.130 275)`, sixteen degrees from the new
violet. Used as a UI accent they would read as the same thing said twice. And the palette's
stated direction is *"chrome recedes so cover art and pages are the loudest thing on
screen"*; a two-colour gradient across the chrome is the opposite of that. So the arc is the
**mark, the icon and brand surfaces**, and the UI keeps one accent. `ink` is untouched.

### The rename, and why it is worth 56 references

`ember` describes a colour that is about to stop being true, and a token called `ember`
holding a pink is a trap for the next reader. The new names say what the token is *for*, so
the next brand change is a value change and not a rename.

The cost was measured before it was decided: **56 real references across 14 files.** A naive
grep says 1125, and 1069 of those are Compose's `remember` — the count only means anything
with a word boundary on it. Of the 14 files, seven are generated (`dist/`, `Generated/`,
`tokens.resolved.json`) and regenerate; the hand-written ones are Android's `Theme.kt` (10),
iOS's `Palette.swift` (7), the token source (4), `docs/design.md` (3) and four test files.

## The mark, as geometry

Six petals on a 2×3 grid. Each is a square with **one** corner rounded to a full quarter-circle
and the other three square, and the arrangement of which corner is rounded is what makes the
shape read as an *S*:

| | Left column | Right column |
| --- | --- | --- |
| Top row | top-left rounded | top-right rounded |
| Middle row | bottom-left rounded | bottom-right rounded |
| Bottom row | **bookmark**: square top, notch cut up from the bottom edge | bottom-right rounded |

Measured from the supplied icon for proportion: the mark occupies 528×660 of a 1024 canvas,
so it is taller than wide at roughly **4:5**, and the gap between petals is about 3.5% of the
mark's width. The bookmark's notch rises about a third of that petal's height.

**This is authored, not traced.** The supplied art is one AI generation of the idea and its
petals are not quite congruent; a construction from exact squares and exact quarter-circles is
the same mark drawn properly, and it is the version that survives being rendered at 40 px.

### One definition, three outputs

`scripts/brand-mark.swift` holds the geometry once and emits:

- **iOS** — 1024×1024 PNGs, one per face, into the asset catalogue.
- **Android** — a `<vector>` drawable for the adaptive icon's foreground, which is
  resolution-independent and is what that platform actually wants.
- **Docs** — an SVG, so `docs/` and any future web surface use the same shape.

Three hand-maintained copies of one shape is three chances to drift, which is the whole
reason this is generated.

### Why Swift and CoreGraphics

There is no rasteriser on this machine — no ImageMagick, no `rsvg-convert`, no Pillow — and
the mark needs real anti-aliasing and a real linear gradient. CoreGraphics has both, ships
with the OS this repo already builds Swift against, and needs no dependency added.

**Verified before it was chosen**: a 20-line probe rendered a rounded rect with a diagonal
gradient and wrote a PNG through `ImageIO`, and two runs produced **byte-identical** files.
Determinism is the property that matters, because the output is committed and gated.

macOS-only for *writing*, and that is the same trade the audio fixtures already make: the
output is committed, so nothing that reads it needs the tool, and `--check` compares the
committed bytes rather than re-rendering.

## The five faces

Faces of one mark, not five marks — the constraint is that a reader picking any of them is
still recognisably holding StoryArc.

| Face | Plate | Notes |
| --- | --- | --- |
| **Ink** (default) | near-black, `dark.surfaceCanvas` | The default, and the one the artwork leads with |
| **Paper** | warm off-white, `light.surfaceCanvas` | For a light home screen |
| **Bloom** | pale lavender | The tint the artwork's third variant uses |
| **Arc** | saturated violet, `arcEnd` | The loud one |
| **Mono** | plate matching Ink, mark in a single ink | For a reader who wants it quiet, and the source of the Android monochrome layer |

**Mono is not decoration.** Android's adaptive icon already declares a `<monochrome>` layer
and currently points it at the coloured foreground, which is wrong: themed icons tint that
layer and a gradient tinted flat loses the mark's internal divisions. Mono is the correct
single-colour art for it, and shipping it also gives a reader a quiet option.

## iOS: `setAlternateIconName`

Alternate icons are declared in the asset catalogue as sibling `.appiconset`s with
`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`, and switched with
`UIApplication.shared.setAlternateIconName(_:)` — `nil` for the primary.

Three constraints the spec is written around:

- **It presents a system alert by default.** Suppressing it is undocumented and relies on
  overriding a private delegate method, so the app does **not** suppress it. The scenario says
  the app "does not present a system alert it did not ask for" — the platform's own alert is
  the platform's, and fighting it is how apps break on the next OS.
- **It can fail**, and the completion handler is where that arrives. The stored choice must
  not move until the platform confirms, which is why the spec says what the chooser shows is
  what was applied rather than what was stored.
- **`alternateIconName` is the truth**, not the preference. It is read on launch to reconcile,
  which is what makes the reinstall and restore scenario implementable at all.

## Android: `activity-alias`, because there is no API

Android has no equivalent of `setAlternateIconName`. The mechanism is one
`<activity-alias>` per face, each with its own `android:icon`, exactly one enabled at a time
via `PackageManager.setComponentEnabledSetting`.

Four consequences, all visible to a reader and all in the spec:

- **It is not instant.** Launchers re-read the component list on their own schedule, so the
  spec says the reader is told it appears the next time the launcher draws its list. Promising
  an instant change here would be promising something the platform does not do.
- **Disabling the currently-enabled alias can close the task**, so the enable must precede the
  disable and both must be `DONT_KILL_APP`.
- **Every alias needs the launcher intent filter**, and exactly one may be enabled — zero
  makes the app vanish from the launcher entirely, which is unrecoverable without a reinstall.
  A test asserts the invariant rather than trusting the sequencing.
- **The default alias is the manifest's own activity**, not a sixth alias, so a fresh install
  and a reset land in the same state.

## What is deliberately not built

- **No suppression of iOS's alert**, per above.
- **No gradient in chrome**, per the palette's direction.
- **No custom colours or user-supplied art.** A fixed set the app ships.
- **`brand.ink` is untouched**, and the Natural theme's `clay` pair with it — Natural is a
  separate theme with its own accent and the brand change does not reach into it.
