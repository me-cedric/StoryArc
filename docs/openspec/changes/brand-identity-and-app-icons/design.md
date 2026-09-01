# Design — brand identity and app icons

## The colours come from the designer's SVG

**A second artwork drop on 2026-09-01 replaced the first, and it changed the method.** The
first was raster only, so the mark's proportions and its gradient had to be *measured* out of
crops. The second is a hand-authored SVG, so both are simply *read*.

`docs/designs/brand/storyarc-mark.svg` is the source of truth. Its gradient runs across four
stops on a vector from (180,30) to (330,510):

| Stop | sRGB | OKLCH | On `dark.surfaceCanvas` | On `light.surfaceCanvas` |
| --- | --- | --- | --- | --- |
| 0.00 | `#FF6B9D` | `oklch(72.4% 0.185 2)` | **7.24:1** | 2.48:1 |
| 0.35 | `#F566B8` | `oklch(71.2% 0.195 347.7)` | 6.90:1 | 2.61:1 |
| 0.62 | `#A855F7` | `oklch(62.7% 0.233 304)` | 4.90:1 | 3.67:1 |
| 1.00 | `#5B4BF5` | `oklch(54.1% 0.2415 278.8)` | 3.48:1 | 5.17:1 |

Every OKLCH value above **round-trips to the designer's exact hex** through the token
pipeline's own converter, not merely through a similar one. That took a small search: the
naive conversion of three of the four landed one unit out in a channel, and a token whose hex
differs by one from the artwork's is a token somebody will eventually "fix" in the wrong
direction.

### The token set

| Token | Value | Role | Gate | Measured |
| --- | --- | --- | --- | --- |
| `accent` (was `ember`) | `oklch(72.4% 0.185 2)` → `#FF6B9D` | The UI accent, and the arc's first stop | ≥3.0 on `dark.surfaceCanvas` | **7.24:1** |
| `accentStrong` (was `emberStrong`) | `oklch(62% 0.185 2)` → `#DA497D` | The light-theme accent | ≥3.0 on `light.surfaceCanvas` | **3.72:1** |
| `accentMuted` (was `emberMuted`) | `oklch(45% 0.09 2)` → `#7D3E51` | Rails at rest | ungated | 2.48:1 |
| `arcMid` *(new)* | `oklch(71.2% 0.195 347.7)` → `#F566B8` | The arc's second stop | identity only | — |
| `arcLate` *(new)* | `oklch(62.7% 0.233 304)` → `#A855F7` | The arc's third stop | identity only | — |
| `arcEnd` *(new)* | `oklch(54.1% 0.2415 278.8)` → `#5B4BF5` | The arc's last stop | identity only | — |
| `iconPlate` *(new)* | `oklch(20.8% 0.016 285)` → `#17171F` | The icon's own plate | identity only | — |

`accent` doubles as the arc's first stop rather than being a fourth near-pink, so the UI accent
and the mark can never drift apart.

**`accent` is flagged out of gamut by the token build, and that is correct rather than a
problem to solve.** `#FF6B9D` has red at 255, on the sRGB boundary, so *any* OKLCH mapping to
it clips. The build treats out-of-gamut as a warning rather than a failure, and the honest
reading is that the designer picked a colour at the edge of the space. Nudging the brand to
silence a warning would be backwards.

**The lightness ladder still holds, which is what makes this cheap.** The old accent sat at
L=70% and the new one is L=72.4%, so this remains close to a hue rotation at constant
lightness and every contrast relationship the gate validates is preserved rather than
re-argued — 7.24:1 against the old 6.91:1 on dark, 3.72:1 against 3.59:1 on light.

**`iconPlate` is the designer's, not the app's.** Sampled from their own
`ios-appicon-1024.png`: a near-black tinted toward the brand's violet at hue 285, where the
app's `dark.surfaceCanvas` is warm at hue 70. Honoured rather than overridden — the icon is
brand territory, and a violet-tinted plate under a violet-ending arc is a choice. Making it a
token rather than a hex in the generator is what keeps it reviewable.

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

## The mark is rendered, not reconstructed

`scripts/brand-mark.swift` parses the designer's SVG and renders it. It used to *reconstruct*
the mark from proportions measured out of the raster crops, which was the right answer to a
raster-only drop and is the wrong answer to an SVG: the supplied paths carry 14-unit radii on
the "square" corners and a **different arc radius per tile** — 137, 123, 114, 108 — and no
reconstruction from a crop was going to recover those numbers.

### How faithful, in numbers

Rendered against the designer's own `ios-appicon-1024.png`, pixel for pixel across all
1,048,576:

| | |
| --- | --- |
| Byte-identical | **88.85%** |
| Within 8/255 | 99.52% |
| Beyond 96/255 | 0.225%, spanning exactly the mark's bounding box — the anti-aliased outlines |
| Mean channel difference | **0.68 / 255** |

Their composition was measured rather than guessed: the mark spans 0.564 of the icon's side,
so the inset is 0.218. That measurement also confirmed the parse independently — the rendered
aspect came out at 0.796 against the viewBox's 0.794.

### What the script still owns

The SVG cannot say which faces exist, what plate each sits on, how far the mark insets for
each platform's icon mask, or that the output must be byte-identical run to run. Fifteen
assets from one source: five iOS faces with their `Contents.json`, the Android adaptive
foreground *and* its monochrome twin, `AccentColor.colorset`, and a plateless PNG for the
docs.

**Android gets the designer's path data verbatim**, wrapped in a `<group>` that scales and
translates it into the 108dp viewport. Re-emitting the geometry would mean converting arcs to
cubics and hoping two renderers agree; a transform on the original leaves the numbers alone.

### Why Swift and CoreGraphics

There is no rasteriser on this machine — no ImageMagick, no `rsvg-convert`, no Pillow — and
the mark needs real anti-aliasing and a real four-stop gradient. CoreGraphics has both and
ships with the OS this repository already builds Swift against. The SVG arc-to-cubic
conversion is the specification's own appendix F.6, written against the general elliptical
case so a designer can put an ellipse in the file later and nothing here changes.

Verified before it was chosen: two runs produce byte-identical output, which is what makes
`pnpm brand:check` a gate rather than a coin toss. macOS-only for *writing*, the same trade
the audio fixtures make: the output is committed, so nothing that reads it needs the tool.

### The parse is verified, and the first version of that check had a hole

`--check` compares committed bytes, so it catches an asset that changed. It cannot catch a
parse that silently lost a segment — and that failure is invisible in a thumbnail, because a
path missing one arc closes across itself and fills a wedge that looks like part of the design.

So the artwork is verified on every run, in both modes, before anything is written: six paths,
each closed, their union matching the declared viewBox to within a unit, and the gradient's
stops sorted and in range.

**Ten mutations of the SVG, and the first version of the check missed the worst one.** It
scanned for ` d="` attributes rather than `<path>` elements, so renaming an element to
`<pathX` left its `d` in the document, six paths were still found, and *a dropped tile passed*.
An attribute is only a path if it is on a path. All ten are caught now: a dropped path, a path
with no `d`, an extra path, a missing `Z`, a removed gradient, a stop out of range, reordered
stops, a shrunk viewBox, and a changed arc radius.

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
