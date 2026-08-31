# StoryArc Design System

The visual and interaction contract for both apps. Values live in
[`packages/design-tokens`](../packages/design-tokens); this document is the
*reasoning* — what the values mean, when to use them, and what is forbidden.

Read [`native-experience`](openspec/specs/native-experience/spec.md) for
the requirements this document serves.

---

## 1. Direction

**Editorial darkroom.**

StoryArc is a room you read in, not a product that wants attention. Its job is
to disappear behind a page of artwork someone else drew. Every decision below
follows from that.

| Principle | What it means in practice |
| --- | --- |
| **The artwork is the loudest thing** | Chrome is translucent, auto-hides, and never tints. Nothing on screen competes with a cover. |
| **Neutral, but not cold** | Every grey carries a warm tilt (OKLCH hue ~70). Light theme is book stock, not office paper. Dark theme is ink, not void. |
| **Colour is information** | The accent means *this is interactive* or *this is your progress*. It is never decoration. Downloaded, offline and unread are the only states allowed a badge. |
| **Type has one moment of voice** | System sans for all chrome, so the app reads as stock. A serif on publication titles — that is the whole of StoryArc's typographic personality, and it is enough. |
| **Depth comes from the platform** | iOS gets Liquid Glass. Android gets Material 3 Expressive elevation. Neither gets an invented shadow system. |

### What this is not

- Not a dark-mode-only app. Light is a first-class theme, and a reader who wants
  a paper-white page inside a dark app gets exactly that.
- Not a Tailwind-shaped card grid. Spacing is uneven on purpose (§4).
- Not a neutral wrapper around a system component set. The system components are
  used *and* composed with intent — the cover grid, the reader chrome and the
  source list each have a considered form.

---

## 2. Colour

Authored in OKLCH, generated to sRGB. See
[`tokens/color.json`](../packages/design-tokens/tokens/color.json).

### Brand

| Token | Value | Where it is allowed |
| --- | --- | --- |
| `brand/ember` | `#EC7C27` | Primary accent on dark surfaces. Reading-lamp amber. |
| `brand/emberStrong` | `#D2600C` | Pressed state; the light-theme accent, where 70 % lightness would fail on paper. |
| `brand/emberMuted` | `#7C4521` | Accent at rest: progress rails, unselected indicators. |
| `brand/ink` | `#4A54A6` | Secondary. Links, informational chips. |
| `brand/clay` | `#C87C5E` | The **Natural** theme's accent on its dark variant. |
| `brand/clayStrong` | `#98492C` | Natural's accent on its light variant, where clay would fail on warm paper. |

Amber, not blue. Every comic and reading app defaults to blue or purple;
StoryArc's accent is the colour of the lamp you read under. It also sits far
from every status colour, so an accent and a warning are never confused.

**The accent is chrome-only.** Inside a publication's context — its detail
screen, its reader — the accent derives from the cover art instead. See §7.

Clay exists so that **Natural is a theme and not the same app in beige.** A warm
surface ramp under an amber accent reads as a tint; a warm surface ramp under an
earthier accent reads as a different material.

### Surfaces

Five roles, run identically by every ramp. Values in
[`tokens/color.json`](../packages/design-tokens/tokens/color.json).

| Role | Purpose |
| --- | --- |
| `surfaceCanvas` | App background |
| `surfaceRaised` | Cards, list rows, sheets |
| `surfaceOverlay` | Menus, popovers, **and the opaque fallback behind Liquid Glass under Reduce Transparency** |
| `surfaceReader` | The reader. Never pure black: it smears on OLED during a page turn and gives glass nothing to refract. |
| `surfaceSunken` | Inset wells: search fields, empty states, cover letterboxing |

### Appearance ramps

Four appearances and one theme, five ramps. Every one passes the same gate.

| Ramp | Canvas | What it is |
| --- | --- | --- |
| `light` | `#F8F6F4` | Warm paper neutrals. |
| `dark` | `#0F0D0B` | Warm ink neutrals. |
| `oledDark` | `#000000` | True black chrome, for panels where black draws no power. |
| `naturalLight` | `#F4EEE3` | Natural's light variant. Cream stock, clay accent. |
| `naturalDark` | `#16100C` | Natural's dark variant. Warm ink, clay accent. |

**`oledDark` does not make the reader pure black.** Chrome does —
`surfaceCanvas` is `#000000`. `surfaceReader` sits at
`#010101`, deliberately above it, because pure black
smears on OLED during a page turn and a page turn is the motion this app is built
around. The setting is honoured where it helps and explained where it does not.

**Natural is a theme, not an appearance.** It carries texture and an earthier
accent rather than a light/dark polarity, so it has both variants of its own.
Its accents reach the whole app so the theme is coherent; its **grain is confined
to reading surfaces**, because texture behind a dense settings list reads as
noise rather than as paper. The grain is procedural noise, not a bundled asset —
cheaper, resolution-independent, and it disables itself under Reduce Transparency
or Increase Contrast, since grain lowers effective contrast.

### Status

| Token | Meaning |
| --- | --- |
| `status/success` | Sync succeeded, source reachable |
| `status/warning` | Stale cache, partial download |
| `status/danger` | Auth failure, unreadable file, destructive action |
| `status/offline` | Source disconnected — **neutral grey, never red.** Offline is a normal state, not a failure. |
| `status/downloaded` | Available offline. The one badge permitted to compete with cover art. |

### Reading themes

Six named presets, per
[`reading-themes`](openspec/specs/reading-themes/spec.md). A preset is a
background, a text colour, a typeface and a spacing character applied in one tap.

| Preset | Background | Text | Ratio | Character |
| --- | --- | --- | --- | --- |
| **Original** | `#FCFCFA` | `#131110` | swatch only | Publisher styles **on**. Nothing overridden but size. |
| **Quiet** | `#161310` | `#C7C3BF` | 10.6:1 | Soft off-white on deep neutral, tightened spacing. |
| **Paper** | `#F5F1EC` | `#1D1A17` | 15.4:1 | Book stock, serif, comfortable default. |
| **Bold** | `#FCFCFC` | `#060606` | 19.8:1 | Heavier weight, wider spacing. Low vision without leaving the aesthetic. |
| **Calm** | `#3F3329` | `#E5D9C4` | 8.8:1 | Cream on brown, generous line height. Long evenings. |
| **Focus** | `#040303` | `#E7E4E0` | 16.3:1 | Narrow measure, minimal decoration. Fewest words per line. |

All six are held to **WCAG AAA (7:1)** by the build gate, because this text is
read for hours rather than glanced at.

**Original's pair is a swatch, not a setting.** Original leaves publisher styles
enabled and overrides no colour; those two values exist only to draw its card in
the preset grid.

That AAA floor has one visible consequence worth naming: **Quiet cannot be as
low-contrast as its name suggests.** It lands at 10.6:1 rather than the ~5:1 a
"low contrast" theme would reach unconstrained. Legibility wins; Quiet expresses
itself through softness of hue and tightened spacing instead.

Each preset is drawn **in its own colours** in the grid — six samples, not six
labels. That is the single decision that makes the grid readable at a glance.

### Rules

1. Never write a hex value in app code. Reference a token.
2. Never use colour as the sole carrier of state — pair it with an icon, a label
   or a shape.
3. A cover-derived colour is adjusted until it clears the contrast floor before
   it is used. Never used raw.
4. A user-chosen reading background gets a **derived** text colour at 7:1. An
   override below 4.5:1 is refused **with the measured ratio shown** — "not
   allowed" without a number is just an obstacle.

---

## 3. Typography

| Family | iOS | Android | Use |
| --- | --- | --- | --- |
| `ui` | SF Pro | Roboto | **All chrome.** Never overridden — this is what makes the app feel stock. |
| `editorial` | New York | Source Serif 4 (bundled) | Publication titles, series headers, About. Sparingly. |
| `reading` | user choice | user choice | Reflowable body. Five bundled families plus the publisher's own and the system faces — see below. |
| `mono` | SF Mono | Roboto Mono | Server URLs, file paths, diagnostics. |

Eleven roles, from `display` (34/41, serif, semibold) to `caption2` (11/13). All
scale with Dynamic Type and the Android font scale — the numbers in the tokens
are the size at the default setting, not a fixed size.

### Bundled reading families

Apple Books uses commercial faces — Canela among them. StoryArc cannot ship
those, so every bundled family is openly licensed and its licence appears in
acknowledgements.

| Family | Licence | Why it is in |
| --- | --- | --- |
| **Literata** | OFL | Designed for screen reading. Default for Paper. |
| **Source Serif 4** | OFL | Clean, wide weight range. Carries Bold. |
| **EB Garamond** | OFL | Classical. Gives Calm a genuinely different voice. |
| **Bitter** | OFL | Slab; holds legibility at small sizes and in Focus's narrow measure. |
| **Atkinson Hyperlegible** | OFL | Designed for low vision. |
| System serif | — | New York / Noto Serif. Zero bytes. |
| System sans | — | SF Pro / Roboto. Zero bytes. |

Roughly 2–3 MB across the five, subset to Latin, Latin Extended, Greek and
Cyrillic. Newsreader and Crimson Pro were considered and cut: they overlap EB
Garamond's role without adding a distinct one.

### Rules

1. **Hierarchy comes from scale contrast, not from weight everywhere.** A screen
   with three semibold sizes has no hierarchy. `display` next to `footnote` does.
2. `editorial` appears at most twice per screen. It is a seasoning.
3. Every screen must survive the largest accessibility text size. The library
   drops from a cover grid to a list rather than truncating titles.
4. Atkinson Hyperlegible is labelled in the UI as designed for low vision — it
   is an accessibility affordance, not a style option.

---

## 4. Spacing and rhythm

4 pt base grid. `hair` 2 → `huge` 64, plus `gutter` 20, `section` 32,
`coverGap` 14.

**Spacing is deliberately uneven.** A cover grid breathes at `xl`; the metadata
stack under a title tightens to `xs` so title, series and year read as one
object. Uniform padding everywhere is the single fastest way to look like a
template — it is the thing this system exists to avoid.

### Radius

`cover` 4 · `sm` 6 · `md` 10 · `lg` 16 · `xl` 22 · `sheet` 28 · `capsule` 999

**Cover radius stays at 4 pt on purpose.** A comic cover is printed stock.
Rounding it like an app icon reads as wrong, and every reader app that does it
looks like a music player.

### Cover grid

- Aspect ratio 2:3 — the North American comic trim.
- Manga volumes and EPUB covers vary. The cell crops to a consistent shape and
  **letterboxes onto `surfaceSunken` rather than distorting art.**
- Minimum cover width scales by size class: 104 / 132 / 158 pt.
- **The two platforms measure different things, and this is not yet a decided
  divergence.** iOS passes the *shelf's* own width
  (`coverMinimumWidth(shelfWidth:textSize:)`); Android passes the *window's*
  (`rememberCoverColumns`), because 600 and 840 are Material's window size-class
  breakpoints and a content pane measured against them reads a 900 dp window
  behind a navigation rail as a medium one. The cost is visible: on a 1067 dp
  tablet the Android library sits in the list pane of a `ListDetailPaneScaffold`,
  reads the whole window, and takes the 158 pt tier: a pane with under 328 pt of
  content room then fits a single 168 pt cover, where the same pane measured on
  its own width would take the 132 pt tier and fit two. Register #4 carries 600
  and 840 — it is the *pane count* it ties them to, not the cover width, and
  iOS's own 900 pt cover threshold (`confidentShelfWidth`) is in no register at
  all. Not a licence to copy the shape — a thing to settle.
- **A maximum as well as a minimum, always.** A lower bound on its own lets a
  narrow window stretch one cover edge to edge. Android caps at 168 pt; iOS
  derives 1.6 × the minimum, because SwiftUI's `adaptive(minimum:maximum:)`
  takes the pair and Android needed a `GridCells` written for it.
- **At an accessibility text size every tier steps once, by 1.4:** 146 / 185 /
  221, and the maximum steps with it. A step, not a scale that follows the
  font — what a cramped caption needs is one fewer column, and a column is a
  step; the artwork is the interface and does not shrink to make room for
  words. The boundary is font scale 1.3, where Android's ordinary Font size
  slider stops and where `DynamicTypeSize.isAccessibilitySize` becomes true.
- **The two full shelves of the reader's own publications ask one function; they
  do not restate the ladder.** The library grid and the downloads destination,
  and the rule they ask lives in `:core:designsystem/grid/CoverColumns.kt` on
  Android and `LibraryFeature/CoverGrid.swift` on iOS. Both apps had already
  shipped the downloads shelf carrying a copy that laid the same window out
  differently. `:app`'s `ShelvesAskOneRuleTest` enforces this for those two by
  reading their call sites, because no test of the function can see who declined
  to call it. It enforces it for *those two only*, and names them — the surfaces
  in the table below are the ones it does not reach.
- **Five surfaces on Android read the accessibility step. Eight do not.** The
  five: the library grid and the downloads shelf (`rememberCoverColumns`), the
  library's continue-reading row (`128.dp.steppedForFontScale`), Home's plain
  shelf runs (`coverMinimumWidth` × 1.25) and Home's Keep reading card (its own
  200 / 240 / 280 dp tiers, the shared step). The eight, in full — this is the
  whole list and not a sample, found by grepping `apps/android`'s main sources
  for `GridCells.`, `BoundedAdaptive(`, `.width(` and `widthIn(`, and reading
  every hit:

  | File | What it states | Whose covers |
  | --- | --- | --- |
  | `CatalogueBrowserScreen.kt` | `GridCells.Adaptive(minSize = 140.dp)` | a remote catalogue's |
  | `KavitaBrowserScreen.kt` | `GridCells.Adaptive(minSize = 140.dp)` | a Kavita server's |
  | `KavitaShelfScreens.kt` | `GridCells.Adaptive(minSize = 140.dp)` | a Kavita server's |
  | `CatalogueGroups.kt` | `Modifier.width(140.dp)` | a remote catalogue's |
  | `ShelfCoverChoice.kt` | `BoundedAdaptive(92.dp, 140.dp)` | **the reader's own** |
  | `DetailSeriesShelf.kt` | `108.dp` | **the reader's own** |
  | `ShelvesScreen.kt` | `BoundedAdaptive(150.dp, 220.dp)` | a shelf's four-cover lattice |
  | `CoverList.kt` | `44.dp` row thumbnail | **the reader's own** |

  None of the eight reads the font scale at all, so none of them widens when the
  reader turns text size up and the library grid beside them does; the four
  `140.dp` ones are also a number that is none of 104 / 132 / 158, and the three
  `GridCells.Adaptive` ones have no maximum.
  The first four browse a *remote* source rather than the reader's library,
  which is the scope line that kept them out of the sweep — a scope line, not a
  reason. The last four have no such excuse: they are the reader's own covers
  and they are simply not done. `ShelvesScreen`'s lattice may genuinely want a
  floor of its own, being four covers rather than one; it should still step.
  Bringing any of them onto the rule changes what a reader sees and owes an
  emulator screenshot. The reader's page thumbnails (`ThumbnailStrip.kt`,
  `GridCells.Adaptive(88.dp)`) are deliberately not on this list: they are
  pages, not covers.
- **Neither cover grid spaces its columns with the token named for that gap.**
  `layout.json` defines `coverGap` 14 for it, and both grids use `md` 12 — the
  library grid already did, and the Downloads shelf was moved onto `md` to match
  its sibling rather than both being moved onto `coverGap`. What still calls
  `coverGap` is the two horizontal runs: Home's plain shelves and a publication
  page's series shelf. So the token now means "the gap in a row of covers" and
  `md` means "the gap in a grid of them", which nothing says out loud and nobody
  decided. Naming it here because a token abandoned quietly is the same drift
  this section exists to stop; settling which of the two is right is a separate
  change, and a visible one.
- `maxContentWidth` 720 pt for text-heavy screens, so a settings list on an iPad
  does not stretch to a 1200 pt line length.

---

## 5. Depth and materials

### iOS — Liquid Glass

- Floating chrome — reader bars, the library's search field, the tab bar
  accessory — uses `.glassEffect()`, grouped inside a `GlassEffectContainer`
  where several glass shapes sit together so they morph as one.
- **Chrome glass is untinted** (`chromeTintOpacity: 0`) so it picks up the cover
  art beneath it. Tinting it would defeat the point of the material.
- Scroll edge effects mark content boundaries. No hairline separators under a
  navigation bar.
- **Every glass surface declares its opaque fallback.** Under Reduce
  Transparency it becomes `surfaceOverlay`, with `borderStrong` restored.
- No custom drop shadows anywhere.

### Android — Material 3 Expressive

- `MaterialExpressiveTheme` with the Expressive motion scheme.
- Elevation `flat`/`raised`/`floating`/`overlay`/`modal` maps to Material's own
  tonal elevation — a tint of the surface, not a shadow.
- Edge to edge, always, with window insets handled rather than avoided.
- Dynamic colour from wallpaper by default; a setting switches to the StoryArc
  palette.

**The two platforms do not converge here.** An iOS screenshot and an Android
screenshot of the same view should be recognisably the same product and
recognisably different platforms. That is the goal, not a compromise.

---

## 6. Motion

| Token | ms | Use |
| --- | --- | --- |
| `instant` | 100 | State flips: selection, toggle |
| `fast` | 180 | Hover, press, small reveals |
| `normal` | 260 | Sheets, navigation |
| `slow` | 380 | Large surfaces, full-screen transitions |
| `chromeFade` | 220 | Reader chrome in and out |
| `pageTurn` | 450 | Page-turn release settle |

Easing `standard` `cubic-bezier(0.2, 0, 0, 1)`. Springs for anything a finger
touches — response 0.42, damping 0.86.

### Page transitions

Four modes, per
[`page-transitions`](openspec/specs/page-transitions/spec.md). A transition
belongs to the **container**, not the content, so a comic page and an EPUB page
turn identically.

| Mode | What it is |
| --- | --- |
| **Curl** | Interactive page turn following the finger. Lit leading edge, shadow cast on the page beneath. |
| **Slide** | Paged translation along the reading axis. |
| **Fast fade** | Short cross-dissolve, no translation. |
| **Scroll** | Continuous, no discrete turn. Vertical by default for webtoons and reflowable text. |

### The curl

The signature interaction, and the one thing worth over-engineering.

- **Driven by drag translation, not a timeline.** The page deforms and lifts
  under the finger in real time. The spring (response 0.35, damping 0.82)
  governs only the release.
- **Interruptible.** A new gesture during the settle takes over from the current
  position. The page never snaps.
- Past halfway completes; before halfway springs back; **flick velocity
  completes regardless of distance**, because that is how a real page behaves.
- Mirrored for right-to-left publications — the curl originates from the
  opposite edge.
- Target: the display's refresh rate, including 120 Hz ProMotion.

**It is ours, not a library's.** Readium exposes every typographic preference and
no transition preference at all. Metal on iOS, AGSL on Android.

**On reflowable text the turning page is a raster.** Readium paginates EPUB
inside a web view; a deforming surface has to be a texture, so each page is
rastered at display scale and the raster deformed. Nothing reflows or shifts
during the turn, and text interaction resumes the instant it completes. Comics
do not pay this — the page is already a decoded image.

**Curl is absent where it cannot be honest.** AGSL needs API 33 and StoryArc's
floor is API 31, so on Android 12 the picker has no Curl and Slide is the
default, with the reason stated in plain language and the user's stored Curl
preference left intact. Same path if a device cannot hold the frame rate. A
stuttering curl never ships in preference to a slide that works.

### Rules

1. Animate transform, opacity and clip only. Never animate layout.
2. **Reduce Motion replaces Curl and Slide with Fast fade**, and the mode picker
   lists them as unavailable *with the reason* rather than hiding them. A control
   that vanishes teaches the user nothing.
3. No purely decorative animation. Motion clarifies where something came from or
   where it went, or it does not ship.

---

## 7. Dynamic colour

Three layers, in priority order:

1. **Cover-derived** — inside a publication's context. The accent and background
   tint derive from the cover art, then are lightness-adjusted until they clear
   the contrast floor. Raw extracted colour is never used.
2. **Material You** — Android only, outside publication context, when the user
   has dynamic colour on.
3. **StoryArc brand** — everywhere else, and the fallback for both of the above.

This is what makes a library of covers feel like a library rather than a grid of
thumbnails: each publication brings its own colour to its own screen, inside a
chassis that stays constant.

---

## 8. Iconography

SF Symbols on iOS, Material Symbols on Android. **No custom icon set.**

A user recognises the platform's share icon instantly and would have to learn a
custom one. The only bespoke marks in the app are the app icon itself and the
source-type glyphs, where the platform sets offer nothing (there is no stock
"OPDS catalogue" icon).

Weight and scale follow the adjacent text, so an icon in a `footnote` row is
smaller than one in a `headline` row.

---

## 9. Component intent

Not a component list — the platforms provide those. These are the places where
StoryArc composes them with a specific intent.

| Surface | Intent |
| --- | --- |
| **Cover cell** | Art edge to edge, tight 4 pt radius, letterboxed not cropped. Progress as a thin rail across the bottom edge, never a ring over the art. Downloaded state as a small filled mark in one corner. Title *below* the cell, never over the artwork. |
| **Continue-reading row** | Wider cells than the grid, showing progress and the resume point. Absent, not empty, when nothing is in progress. |
| **Source row** | Name, type glyph, state dot, and last-sync in `footnote`. An offline source is dimmed, never reddened. |
| **Reader chrome** | Two floating glass bars over the page, page slider with a thumbnail that follows the drag. Fades after 4 s. The page never reflows when chrome appears. |
| **Publication detail** | Cover-derived background wash behind a large cover, `editorial` title, then a tight metadata stack. One primary action — *Continue* or *Read* — and everything else in a menu. |
| **Theme sheet** | Two depths. The first holds the six preset cards, the font-size stepper with step dots, the page-mode control and brightness — the things changed mid-chapter. The fine axes sit behind one *Customise* action. The page stays visible behind the sheet and updates live, so a change is judged on real text rather than only in the preview. |
| **Preset card** | Drawn **in its own colours** with "Aa" and its name, so the grid reads as six samples rather than six labels. Selected state visible; a preset deviated from is marked *modified*, never shown as cleanly active. |
| **Axis slider** | Value trailing on iOS, Material's own drag label on Android. Long-press resets to the preset value. An axis inert because publisher styles are on is marked unavailable **with its reason and a one-tap fix** — never a live control that does nothing. |
| **Empty states** | Say what would be here and offer the one action that fills it. Never an illustration with no action. |

---

## 10. Accessibility floor

Not a section to check at the end. These are build and review gates.

- **Contrast** is verified by `pnpm tokens:check` in CI across **all five
  appearance ramps**: 4.5:1 text, 3:1 tertiary and accents, and **7:1 for all six
  reading themes**. 37 pairs. A palette that fails does not build.
- **A user-chosen reading background cannot be made illegible.** Its text colour
  is derived at 7:1; an override below 4.5:1 is refused with the measured ratio
  shown.
- **Touch targets** ≥ 44 pt on iOS, ≥ 48 dp on Android — reader chrome included.
- **Dynamic Type / font scale** to maximum on every screen, no clipping. Library
  falls back to a list.
- **Reduce Transparency** → opaque fallbacks, stronger borders, and Natural's
  grain switches itself off, because grain lowers effective contrast.
- **Reduce Motion** → Fast fade only, with Curl and Slide still listed and their
  reason given.
- **Every axis slider** carries an accessibility value and increment actions, so
  VoiceOver and TalkBack can adjust it. The font-size stepper announces its
  position out of the total, not just "larger".
- **VoiceOver / TalkBack** → every control labelled, reading order matches
  visual order, reader announces page and total on each turn.
- **Colour is never the only signal.**

---

## 11. Proof

**A change a user can see owes a screenshot from a booted simulator or emulator.**

A SwiftUI `#Preview` and a Compose `@Preview` are development aids. Neither
exercises real data, real safe-area insets, real system materials, or a real
Dynamic Type setting — so neither is proof.

Every screen change is captured in light and dark, at default and largest text
size, and compared against its reference.

```bash
# iOS
xcrun simctl io booted screenshot shot.png

# Android
adb exec-out screencap -p > shot.png
```

Two exceptions, and the handoff must name which one applies: code behind a flag
that nothing renders yet, and a pure refactor whose screenshots are
byte-identical — where the identical screenshots *are* the proof.
