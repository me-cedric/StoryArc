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

**This changed after a design review on 2026-09-01, and the review was right.** The first
version made the *pink* the UI accent, because it is the arc's first stop. The review argued
for one accent taken from the middle of the arc, applied to tab bars, chips, sliders and
progress ticks. Two facts decided it:

- **A single value clears both themes.** `#8A4DF0` measures 4.06:1 on `dark.surfaceCanvas` and
  4.43:1 on `light.surfaceCanvas`, both against a 3.0 floor. The pink measures 7.24:1 on dark
  and **2.48:1 on light** — it fails the light gate and needs a second token to exist at all.
- **"Chrome recedes" is this palette's stated direction.** Hot pink on every chip, slider and
  progress tick is not receding. A violet from the middle of the mark is unmistakably the same
  brand and does not shout.

**And it resolved a collision rather than creating one.** `brand.ink` — `oklch(48% 0.130 275)`
— is Material's `secondary` in `Theme.kt`. A violet accent at hue 295 sitting 20° from it would
read as the same colour said twice. So the pink takes the secondary role instead: a two-pole
identity wants primary and secondary to *be* its two poles, not a near-neighbour of one of
them. `ink` retires.

| Token | Value | sRGB | Role | Gate | Measured |
| --- | --- | --- | --- | --- | --- |
| `accent` | `oklch(58% 0.2304 295.4)` | `#8A4DF0` | Material `primary`. Tab bars, chips, sliders, progress ticks, links. **One value, both themes.** | ≥3.0 dark *and* light | **4.06** / **4.43** |
| `accentMuted` | `oklch(45% 0.10 295.4)` | `#5A4886` | Rails at rest | ungated | 2.50 dark |
| `secondary` *(replaces `ink`)* | `oklch(72.4% 0.185 2)` | `#FF6B9D` | Material `secondary` on dark. The arc's first stop, so mark and palette cannot drift | ≥3.0 dark | **7.24** |
| `secondaryStrong` | `oklch(62% 0.185 2)` | `#DA497D` | The same on light, where the pink fails | ≥3.0 light | **3.72** |
| `arcMid` | `oklch(71.2% 0.195 347.7)` | `#F566B8` | The arc's second stop | identity only | — |
| `arcLate` | `oklch(62.7% 0.233 304)` | `#A855F7` | The arc's third stop | identity only | — |
| `arcEnd` | `oklch(54.1% 0.2415 278.8)` | `#5B4BF5` | The arc's last stop | identity only | — |
| `iconPlate` | `oklch(20.8% 0.016 285)` | `#17171F` | The icon's own plate, sampled from the designer's render | identity only | — |

Every value round-trips to its exact hex **through the token pipeline's own converter**, not
merely a similar one. That took a search: the naive conversions landed a unit out in a channel
for four of them, and a token whose hex differs by one from the artwork is a token somebody
eventually "fixes" in the wrong direction.

`secondary` is flagged out of gamut, and that is correct rather than a problem to solve:
`#FF6B9D` has red at 255, on the sRGB boundary, so *any* OKLCH mapping to it clips. The build
treats it as a warning. Nudging the brand to silence a warning would be backwards.

### One thing the review got wrong about Android, and it is worth writing down

The review read Android as "running blue/purple". It is not running a token: `Theme.kt` calls
`dynamicDarkColorScheme`/`dynamicLightColorScheme` by default, so on a Material You device the
scheme is **derived from the reader's wallpaper** — which `native-experience` asks for by name,
with a setting to use the StoryArc palette instead. The purple was the wallpaper.

The mismatch is still real, because it is exactly what a reader sees with dynamic colour turned
off, and because iOS has no equivalent excuse. But the fix is the token, not the dynamic-colour
behaviour, and the two must not be confused: removing dynamic colour to make the brand
consistent would break a requirement to make a screenshot look tidier.

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
