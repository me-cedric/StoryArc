# @storyarc/design-tokens

Single source of truth for StoryArc's colour, typography, spacing, radius and
motion values. Authored once as JSON, generated into Swift and Kotlin so neither
app can drift from the palette by hand-editing a hex code.

## Files

| Path | Purpose |
| --- | --- |
| `tokens/color.json` | Brand accents and the mark's own arc stops, five surface ramps (light, dark, OLED dark, Natural light/dark), status colours, and the six reading-theme presets. Authored in OKLCH. |
| `tokens/typography.json` | Font families per platform and the eleven type roles with size, line height, weight and tracking. |
| `tokens/layout.json` | Spacing scale, radius scale, Android elevation, motion durations and easing, cover-grid metrics, glass and touch-target rules. |
| `scripts/oklch.mjs` | OKLCH → sRGB conversion and WCAG contrast maths. No dependencies. |
| `scripts/build.mjs` | Resolves tokens, runs the contrast gate, emits Swift + Kotlin + a resolved JSON dump. |
| `dist/` | Generated output. Gitignored — rebuild, never edit. |

## Public API

```bash
pnpm tokens:build   # write dist/swift, dist/kotlin, dist/tokens.resolved.json
pnpm tokens:check   # run the contrast gate only, write nothing (CI uses this)
pnpm tokens:sync    # build, then copy the generated files into both apps
```

## Why OKLCH

Perceptual lightness is the only way to keep a dark ramp and a light ramp
feeling like the same family. `oklch(21% 0.007 70)` and `oklch(97.5% 0.004 75)`
are legibly the same neutral at two ends of a scale; their hex codes are not.
Neither Swift nor Kotlin reads OKLCH, so `build.mjs` converts once at build time
and both platforms consume plain sRGB.

## The contrast gate

`build.mjs` exits non-zero when a pair falls below its WCAG floor:

| Pair | Floor |
| --- | --- |
| Any text role on any surface it can be drawn on, tertiary included | 4.5:1 |
| A chrome accent read as a mark on its own canvas | 3:1 |
| The label drawn **on** the accent — text, not a mark | 4.5:1 |
| Every reading theme's background/text pair | 7:1 (AAA) |

Reading-theme text is read for hours rather than glanced at, hence AAA.

The pair list is **derived, not repeated**: every text role is checked on every
surface ramp, so adding a ramp cannot ship an untested palette. 58 pairs plus the
six themes today.

`brand.accent` takes **two** accent rows rather than one, because it is a single
value serving light and dark alike — a claim about two backgrounds needs two
readings. `brand.secondary` is the one role that still carries a light variant.

It also reports any token that falls outside the sRGB gamut. A clipped colour is
not the colour you authored, so treat a gamut warning as a bug in the token, not
as noise.

**`brand.secondary` is the one standing exception, and it is correct.** `#FF6B9D`
is the designer's own first gradient stop and holds red at 255 — on the sRGB
boundary — so *any* OKLCH value mapping to it clips. The warning is a true
statement about the colour space, not about the token. Do not nudge the brand to
silence it; the hex has to match the artwork.

## Consuming the output

Both apps copy `dist/` in during their build rather than committing it:

- iOS — `Packages/StoryArcKit/Sources/DesignSystem/Generated/StoryArcTokens.swift`
- Android — `core/designsystem/src/main/kotlin/app/storyarc/core/designsystem/tokens/StoryArcTokens.kt`

Run `pnpm tokens:sync` after changing any token, and commit the app-side copies
in the same change so a fresh checkout builds without Node installed.

## Adding a token

1. Add it to the matching file under `tokens/`, with a `use` string saying where
   it is allowed to appear. A token with no stated use gets misused.
2. Run `pnpm tokens:build`. Fix any gamut or contrast failure at the source.
3. Run `pnpm tokens:sync` and commit the regenerated app copies.
4. Document the intent in [`docs/design.md`](../../docs/design.md)
   if it introduces a new rule rather than a new value.

## Tests

```bash
pnpm --filter @storyarc/design-tokens check
```

The contrast gate is the test. It runs in CI on every pull request.
