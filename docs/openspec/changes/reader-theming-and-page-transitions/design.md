# Design — reader theming and page transitions

## The split

Research divides this change cleanly, and the division is the whole design.

| Concern | Answer | Confidence |
| --- | --- | --- |
| Every typographic axis | **Readium**, both platforms | Known |
| Background and text colour | **Readium** (`backgroundColor`, `textColor`) | Known |
| Scroll mode | **Readium** (`scroll`) | Known |
| Slide, curl, fast fade | **Ours.** Readium exposes no transition preference | Known |
| Reader brightness | **Ours.** Not a renderer concern | Known |
| Preset definitions | **Ours.** Apple's values are not published | Known |

## Readium covers the typography completely

Readium Swift **3.11.x** and Readium Kotlin **3.3.x** expose a `Preferences` API
whose EPUB axes map one-to-one onto what the user asked for.

| StoryArc axis | Readium preference | Requires `publisherStyles = false` |
| --- | --- | --- |
| Font size | `fontSize` | no |
| Font family | `fontFamily` | no |
| Bold text | `fontWeight` | no |
| Line spacing | `lineHeight` | **yes** |
| Character spacing | `letterSpacing` | **yes** |
| Word spacing | `wordSpacing` | **yes** (LTR only) |
| Paragraph spacing | `paragraphSpacing` | **yes** |
| Margins | `pageMargins` | no |
| Text alignment | `textAlign` | **yes** |
| Background colour | `backgroundColor` | no |
| Text colour | `textColor` | no |
| Scroll vs paginated | `scroll` | no |
| Columns (tablet) | `columnCount` | no |
| Reading direction | `readingProgression` | no |
| Spread (fixed-layout) | `spread` | no |

Also available and worth exposing later, not in this change: `ligatures`,
`typeScale`, `textNormalization`, `paragraphIndent`, `imageFilter`.

`hyphens` was on that list and has since been built, as the tenth axis. It is
mapped nil rather than false when the reader has not asked for it, so a
publication that hyphenates itself goes on doing so; and it sits with the axes
`publisherStyles` overrides, which the table above already had it doing.

**The `publisherStyles` coupling is the design constraint here, not a footnote.**
Seven of the eleven axes are inert while publisher styles are on. That is exactly
why the *Original* preset exists as its own thing: Original means publisher
styles on, and the spec requires the dependent controls to say so rather than sit
there doing nothing. Readium's `PreferencesEditor` exposes an `isEffective` flag
per preference, which is the signal the UI binds to — no bespoke tracking.

A preset is therefore just a named `EPUBPreferences` / `EpubPreferences` value.
No preset machinery to build.

## The curl is ours, and it costs something

Readium paginates reflowable EPUB inside a `WKWebView` on iOS and a `WebView` on
Android, using CSS multi-column. There is no transition hook and no preference.

A finger-tracked curl over live web content is not possible: the deforming
surface has to be a texture, so each page must be rastered and the raster
animated. **During a turn, text is an image.** The spec states this
(`page-transitions` → "Curl on reflowable content") rather than leaving it to be
discovered: no reflow or shift during the turn, and interaction resumes the
instant it completes.

Comics do not pay this cost — the page is already a decoded image, which is why
`comic-reader` has a scenario saying to use it directly.

### iOS

- `UIPageViewController.TransitionStyle.pageCurl` exists and is interactive, but
  it wants to own the view controller hierarchy, and reports since iOS 16
  describe stutter when combined with additional transforms. **Assumed
  unsuitable** for hosting a Readium navigator; a spike decides.
- The path with headroom: raster to a texture and deform it in a **Metal**
  vertex shader, projecting the mesh onto a virtual cylinder — the approach the
  established open implementations take. Drag translation drives the cylinder
  angle directly; the spring governs only the release.
- Slide and fast fade need none of this and are plain SwiftUI transitions.

### Android — AGSL, gated at API 33

**Decided: `minSdk` stays 31 and the curl is gated at API 33.**

AGSL `RuntimeShader` needs API 33; the project floor is API 31 (ADR-0003). Rather
than raise the floor for one animation, or maintain a shader *and* a mesh
fallback, Curl is simply absent below API 33 and Slide is the default there.

This decision **removed** work rather than adding it. One curl implementation —
an AGSL shader mirroring the iOS Metal geometry — instead of two. It also means
the same cylindrical projection is authored once conceptually and expressed twice
rather than solved twice.

`page-transitions` already required Curl to be absent where it cannot be honest,
so the gate needed no new requirement: only a broadening of that scenario from
"cannot hold the frame rate" to "lacks the capability", plus a scenario ensuring
a stored Curl preference is not overwritten when the user opens the library on a
device that cannot honour it.

**`oleksandrbalan/pagecurl`** remains a geometry reference for the shader even
though its `graphicsLayer` mesh approach is no longer the implementation path.

### The escape hatch is specified, and Android already uses it

`page-transitions` states that Curl is absent from the picker where the device
cannot honour it, and that a stuttering curl never ships in preference to a slide
that works. Android below API 33 is the first real consumer of that path — which
is the point of writing it before it was needed. If the iOS spike comes back
negative, the product is still coherent.

## Presets

Six named `EPUBPreferences` values. Apple's exact numbers are not published, so
these are StoryArc's own interpretations carrying the requested names — which is
also why they can be authored in OKLCH and pushed through the existing contrast
gate rather than eyedropped from a screenshot.

| Preset | Background | Publisher styles | Character |
| --- | --- | --- | --- |
| Original | publication's own | **on** | Nothing overridden but size |
| Quiet | deep warm neutral | off | Soft off-white text, tightened spacing |
| Paper | book-stock white | off | Serif, comfortable default |
| Bold | high-contrast light | off | Heavier weight, wider spacing |
| Calm | warm cream on brown | off | Generous line height |
| Focus | near-black | off | Narrow measure, fewest words per line |

Concrete values land in `packages/design-tokens/tokens/color.json` under a new
`readingThemes` group, so the **existing AAA contrast gate** covers all six
automatically. A preset that fails 7:1 fails the build — which is the cheapest
possible enforcement of the spec's contrast requirement.

## App appearance: four plus one

`Light`, `Dark`, `OLED Dark` are appearances; `Natural` is a theme with its own
light and dark variants. That asymmetry is real, not a modelling wobble — Natural
is about texture and accent, not polarity.

Two new token ramps: `oledDark` and `natural`. Both go through the same gate.

**`OLED Dark` deliberately does not make the reader surface pure black.** App
chrome does; the reader stays marginally above it, because pure black smears on
OLED during a page turn — the exact motion this change is about. The spec says
the setting is honoured where it helps and explained where it does not.

**Decided: Natural's accents apply app-wide; its grain applies only to reading
surfaces.**

The warm palette and accent treatment reach the library, settings and source
list, so the theme is coherent rather than bolted onto the reader. Actual paper
grain appears only where text is read. Texture behind a dense settings list reads
as noise, not as paper, and it would drag every one of those surfaces into the
contrast gate for no reading benefit.

Natural's grain: **procedural noise in a shader** rather than a bundled tiling
asset. Cheaper, resolution-independent, no bytes. **Assumed** adequate; if it
reads as digital rather than paper, a bundled texture is the fallback.
`settings-and-about` already requires the grain to disable itself under Reduce
Transparency or Increase Contrast, since grain lowers effective contrast.

On Android the grain shader has the same API 33 constraint as the curl. Below it,
Natural keeps its palette and accents and drops the texture — the same
degrade-gracefully shape, and one already covered by the Reduce-Transparency
requirement.

## Fonts

Apple Books uses commercial faces — the reference screenshot shows Canela.
StoryArc cannot ship those. Bundled families must be openly licensed, and the
spec now requires each licence to appear in acknowledgements.

**Decided: five bundled families, plus the system faces, which cost nothing.**

| Family | Licence | Why it is in |
| --- | --- | --- |
| **Literata** | OFL | Designed for screen reading. The default for Paper. |
| **Source Serif 4** | OFL | Clean, wide range of weights. Carries Bold. |
| **EB Garamond** | OFL | Classical. Gives Calm a genuinely different voice. |
| **Bitter** | OFL | Slab; holds legibility at small sizes and in Focus's narrow measure. |
| **Atkinson Hyperlegible** | OFL | Designed for low vision. **Labelled as such in the UI** — an accessibility affordance presented as a style option gets missed by the people who need it. |
| System serif | — | New York / Noto Serif. Zero bytes. |
| System sans | — | SF Pro / Roboto. Zero bytes. |

Roughly 2–3 MB across the five, subset to Latin, Latin Extended, Greek and
Cyrillic. Newsreader and Crimson Pro were considered and left out: they overlap
EB Garamond's role without adding a distinct one.

Each licence goes into acknowledgements, which the spec requires. Task 6.4 keeps
the per-family binary cost visible rather than letting it accumulate silently.

## Platform presentation

The two sheets are **not** translations of each other. They are the same
information in each platform's own vocabulary.

| | iOS 26 | Android |
| --- | --- | --- |
| Container | Sheet on **Liquid Glass**, untinted so the page shows through | Material 3 **modal bottom sheet**, tonal elevation |
| Presets | Six glass cards, three by two | Six tonal cards, three by two |
| Font size | Segmented smaller/larger with step dots | Segmented button with a step indicator |
| Sliders | `Slider` with the value trailing | Material `Slider`, which shows its own value label on drag |
| Motion | Default spring | `MaterialTheme.motionScheme` — Expressive |
| Tablet | Popover anchored to its control, reader visible beside it | Anchored sheet at expanded width |

Both grids preview each preset **in its own colours** — six samples, not six
labels. That single decision is what makes the grid readable at a glance and is
why it is in the spec rather than left to implementation.

## Accessibility consequences

Not a checklist appended at the end — three of them change the design.

1. **Reduce Motion removes the feature this change is mostly about.** The spec
   requires Curl and Slide to be *listed as unavailable with the reason*, not
   hidden. A control that vanishes teaches the user nothing about why.
2. **Reduce Transparency removes Liquid Glass and Natural's grain.** Every glass
   surface declares its opaque fallback; the grain disables itself because it
   lowers effective contrast.
3. **A custom background can be made illegible, so it cannot be.** A derived
   text colour must clear 7:1; a user override below 4.5:1 is refused *with the
   measured ratio stated*, because "that is not allowed" without a number is
   just an obstacle.

Beyond those: every slider is a real slider with an accessibility value and
increment actions, so VoiceOver and TalkBack can adjust it; the preset grid reads
as a grid with the selected state announced; and the font-size stepper announces
its position out of the total rather than only "larger".

## What is still Assumed

Every user-facing question is decided. What remains is genuinely technical and
belongs to Phase 0, not to a conversation:

| Assumption | Falsified by | Fallback |
| --- | --- | --- |
| A Metal-deformed raster holds 120 Hz on iOS | Task 0.3's measurement | Curl absent on iOS via the same path Android below 33 uses |
| AGSL can express the same cylindrical projection | Task 0.4 | As above |
| `PreferencesEditor.isEffective` is bindable on both platforms | Task 0.2 | Track the `publisherStyles` dependency ourselves — more code, same UI |
| Procedural noise reads as paper | Task 0.5 | Bundled tiling texture, at a size cost |
| Two page rasters fit the memory budget during a turn | Task 0.3 / 0.4 | Lower raster scale during the turn only |

None of these changes what the user sees if it holds. Each has a stated fallback
that keeps the product coherent if it does not — which is the difference between
an assumption and a gamble.
