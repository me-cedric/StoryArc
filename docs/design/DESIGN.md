# StoryArc Design System

The visual and interaction contract for both apps. Values live in
[`packages/design-tokens`](../../packages/design-tokens); this document is the
*reasoning* — what the values mean, when to use them, and what is forbidden.

Read [`native-experience`](../../openspec/specs/native-experience/spec.md) for
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
[`tokens/color.json`](../../packages/design-tokens/tokens/color.json).

### Brand

| Token | Value | Where it is allowed |
| --- | --- | --- |
| `brand/ember` | `#EC7C27` | Primary accent on dark surfaces. Reading-lamp amber. |
| `brand/emberStrong` | `#D2600C` | Pressed state; the light-theme accent, where 70 % lightness would fail on paper. |
| `brand/emberMuted` | `#7C4521` | Accent at rest: progress rails, unselected indicators. |
| `brand/ink` | `#4A54A6` | Secondary. Links, informational chips. |

Amber, not blue. Every comic and reading app defaults to blue or purple;
StoryArc's accent is the colour of the lamp you read under. It also sits far
from every status colour, so an accent and a warning are never confused.

**The accent is chrome-only.** Inside a publication's context — its detail
screen, its reader — the accent derives from the cover art instead. See §7.

### Surfaces

Both themes run the same five roles. Values in
[`tokens/color.json`](../../packages/design-tokens/tokens/color.json).

| Role | Purpose |
| --- | --- |
| `surfaceCanvas` | App background |
| `surfaceRaised` | Cards, list rows, sheets |
| `surfaceOverlay` | Menus, popovers, **and the opaque fallback behind Liquid Glass under Reduce Transparency** |
| `surfaceReader` | The reader. Dark is `#0B0A09`-adjacent — deliberately not `#000`: pure black smears on OLED during a page turn and gives glass nothing to refract. |
| `surfaceSunken` | Inset wells: search fields, empty states, cover letterboxing |

### Status

| Token | Meaning |
| --- | --- |
| `status/success` | Sync succeeded, source reachable |
| `status/warning` | Stale cache, partial download |
| `status/danger` | Auth failure, unreadable file, destructive action |
| `status/offline` | Source disconnected — **neutral grey, never red.** Offline is a normal state, not a failure. |
| `status/downloaded` | Available offline. The one badge permitted to compete with cover art. |

### Reader themes

Paper, Sepia, Night, High Contrast — all four verified at **WCAG AAA (7:1)** by
the build gate. High Contrast is the only place pure black and pure white are
permitted.

### Rules

1. Never write a hex value in app code. Reference a token.
2. Never use colour as the sole carrier of state — pair it with an icon, a label
   or a shape.
3. A cover-derived colour is adjusted until it clears the contrast floor before
   it is used. Never used raw.

---

## 3. Typography

| Family | iOS | Android | Use |
| --- | --- | --- | --- |
| `ui` | SF Pro | Roboto | **All chrome.** Never overridden — this is what makes the app feel stock. |
| `editorial` | New York | Source Serif 4 (bundled) | Publication titles, series headers, About. Sparingly. |
| `reading` | user choice | user choice | Reflowable body. Ships Literata, a serif, the system sans, and Atkinson Hyperlegible. |
| `mono` | SF Mono | Roboto Mono | Server URLs, file paths, diagnostics. |

Eleven roles, from `display` (34/41, serif, semibold) to `caption2` (11/13). All
scale with Dynamic Type and the Android font scale — the numbers in the tokens
are the size at the default setting, not a fixed size.

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

### The page curl

The signature interaction, and the one thing worth over-engineering.

- **Driven by drag translation, not a timeline.** The page deforms and lifts
  under the finger in real time. The spring (response 0.35, damping 0.82)
  governs only the release.
- **Interruptible.** A new gesture during the settle takes over from the current
  position. The page never snaps.
- Past halfway completes; before halfway springs back; **flick velocity
  completes regardless of distance**, because that is how a real page behaves.
- Lit page edge, and a shadow cast on the page beneath.
- Target: the display's refresh rate, including 120 Hz ProMotion.

### Rules

1. Animate transform, opacity and clip only. Never animate layout.
2. **Reduce Motion replaces page curl and slide with a cross-dissolve**, and the
   mode picker says why rather than hiding the options.
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
| **Empty states** | Say what would be here and offer the one action that fills it. Never an illustration with no action. |

---

## 10. Accessibility floor

Not a section to check at the end. These are build and review gates.

- **Contrast** is verified by `pnpm tokens:check` in CI. 4.5:1 text, 3:1
  tertiary and accents, **7:1 for reader themes**.
- **Touch targets** ≥ 44 pt on iOS, ≥ 48 dp on Android — reader chrome included.
- **Dynamic Type / font scale** to maximum on every screen, no clipping. Library
  falls back to a list.
- **Reduce Transparency** → opaque fallbacks, stronger borders.
- **Reduce Motion** → cross-dissolves only.
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
