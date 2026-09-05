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
each platform's icon mask, or that the output must be byte-identical run to run.

**Twenty-four assets from one source**, and this sentence said fifteen until the chooser
needed tiles. Per face: an `.appiconset` PNG with its `Contents.json`, **and an ordinary
`.imageset` PNG with its `Contents.json`** — 5 × 4 = 20. Then `AccentColor.colorset`, the
Android adaptive foreground *and* its monochrome twin, and a plateless PNG for the docs.

The `.imageset` half is the part worth naming, because it is not obvious why a face needs its
art twice. An `.appiconset` is not readable as an image: `UIImage(named:)` cannot draw one, so
a chooser that offers five faces has nothing to put in its rows. The tile is the same
`renderPNG` call at the same inset, emitted beside the icon set two lines later, which is what
keeps the tile and the icon from drifting apart. `pnpm brand:check` prints the count it
actually wrote rather than a number in this document, so the two cannot silently disagree —
but the sentence a reader trusts about what the generator owns is this one, and it was wrong
for as long as the tiles existed.

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

**And that decision went further than this document noticed: there is no preference at all.**
The platform is the whole store on both sides — `alternateIconName` on iOS, the component
enabled states on Android — so there is nothing to keep in sync and no second record that can
disagree with the launcher. It also means the choice never reaches preferences, a backup, a
log or a diagnostic, which is the repo's rule about what may leave memory applied to a setting
that did not need to be stored in the first place.

**The delta had a scenario this made unimplementable, and the scenario is what moved.** "The
platform stops honouring it" asked for the stored preference to be "kept rather than erased,
so a launcher that supports it again restores what the reader picked" — which needs a store
this design deliberately does not have. It was rewritten rather than implemented, because
adding a preference to satisfy it would reverse the decision above and give the app exactly
the second record it avoids. In its place the delta now carries the refusal path that *is*
built — the chooser names the icon still in use, and the refusal is asked once rather than on
every visit — and a third scenario stating the platform-is-the-only-record rule outright, so
the next agent inherits the decision instead of the contradiction. Recorded here because a
delta rewritten to match its code is the move that needs an argument, not the one that needs
no comment.

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
  A test asserts the invariant rather than trusting the sequencing. **And the component the
  aliases point at is the sixth thing that can be zero**: it carries no launcher filter, is
  never written to, and disabling it stops all five aliases resolving at once. That is the
  rule which replaced the bullet below.
- **The default is its own alias, and this bullet used to say the opposite.** It said "the
  default alias is the manifest's own activity, not a sixth alias" — and the implementation
  found that shape unbuildable, because an `<activity-alias>` cannot target an activity that is
  itself a launcher entry without the launcher drawing two. So there are **five** aliases for
  five faces, `MainActivityInk` among them, the target activity is not one of them, and no face
  may name it — asserted twice, in `AppIconChoiceTest` and `AppIconManifestTest`.

  **The half of the old bullet that survives is the reason it was written**: a fresh install
  and a reset still land in the same state. `AppIconAliases.stateFor` writes
  `COMPONENT_ENABLED_STATE_DEFAULT` — not `ENABLED`, not `DISABLED` — to every component whose
  wanted state already equals the manifest's, so a reset leaves the component table holding
  exactly what a fresh install holds rather than an explicit override that happens to agree.
  Three-valued state is what `AppIconAliasState` exists for, and the only test that catches an
  explicit `ENABLED` written in `DEFAULT`'s place is the one asserting that.

- **No suppression of iOS's alert**, per above.
- **No gradient in chrome**, per the palette's direction.
- **No custom colours or user-supplied art.** A fixed set the app ships.
### `ink` had a second consumer, and retiring it forced a decision this document did not make

Recorded 2026-09-01 after `/opsx:update`, because the implementation found it and the artifact
should not be the last to know.

`brand.ink` was Material's `secondary` in **two** places, not one: the brand schemes in
`Theme.kt`, which this change expected, and **Natural's own schemes** in `NaturalTheme.kt`,
which it did not. Retiring the token therefore forced a choice about a theme this change
declares out of scope, and neither replacement in the new set fits:

- **The pink is wrong for Natural.** It sits at hue 2, which is 39° from `clay` at hue 41 —
  the same "one colour said twice" objection that moved the brand accent off `ink` in the
  first place. And a hot pink is the opposite of the earthier accent Natural exists to have.
- **The other clay fails its contrast.** Read across, `clay` reaches 2.80:1 on Natural's cream
  and `clayStrong` 2.99:1 on its ink, both under the 3.0 floor their own gated pairings clear
  at 5.47 and 5.84.

So each Natural variant's `secondary` is now **the accent it already gates**, flattening two
Material roles onto one value. Nothing in this app reads `colorScheme.secondary`, so it costs
nothing today, and it keeps the brand change out of Natural the way this document asks. Giving
Natural a real second pole means adding a token to `color.json` with a gated pairing, and that
is a decision for whoever owns the Natural theme — not one to invent while renaming the
brand's. The reasoning and the way back are at the call site.

### And `onPrimary` was gated by nothing, which the accent move turned into a real failure

The token table gates the accent **against** a canvas and never says what may be drawn **on**
it. So nothing checked the label on a primary button. On the old 70%-lightness amber a
near-black label measured 6.91:1 and nobody had to think about it; on the 58% violet it
measures **4.06:1**, under WCAG's 4.5 floor for the normal-size text a button label is.

Pure white is the only value in the set that clears it, at 4.77, so all three brand schemes
take it and `ACCENT_PAIRS` gained a row so it cannot drift back. Android had **no** test
asserting the brand `ColorScheme`'s wiring at all; `BrandSchemeTest` mirrors iOS's
`PaletteTests` so each platform's own gate catches a regression.

**The general form is worth keeping:** a contrast gate that only checks accents against
backgrounds is checking half of each pair. Any token that can be a *fill* needs its label
gated too.

## What is deliberately not built

- **The Natural theme is untouched as a theme.** `clay` and `clayStrong` are unchanged and
  Natural keeps its own accent. Only its `secondary` role moved, and that was **forced** by
  `ink` retiring rather than chosen here — see the section above.
  **This bullet used to say `brand.ink` was untouched too, and the review overruled that.**
  `ink` retires because it is Material's `secondary` in `Theme.kt`, and a violet accent at hue
  295 would sit 20° from it and read as the same colour said twice. The token table is the
  authority; this bullet predates the review and is corrected rather than deleted, so the next
  reader can see that the two once disagreed — which is how the Natural collision above went
  unnoticed until the compiler found it.
