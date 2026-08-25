# @storyarc/design-tokens

Single source of truth for StoryArc's colour, typography, spacing, radius and
motion values. Authored once as JSON, generated into Swift and Kotlin so neither
app can drift from the palette by hand-editing a hex code.

## Files

| Path | Purpose |
| --- | --- |
| `tokens/color.json` | Brand accents, five surface ramps (light, dark, OLED dark, Natural light/dark), status colours, and the six reading-theme presets. Authored in OKLCH. |
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

`build.mjs` exits non-zero when a text-on-surface pair falls below its WCAG
floor: 4.5:1 for primary and secondary text, 3:1 for tertiary and accents, and
**7:1 (AAA) for every reading theme** — that text is read for hours, not glanced
at.

The pair list is **derived, not repeated**: every text role is checked on every
surface ramp, so adding a ramp cannot ship an untested palette. 37 pairs today.

It also reports any token that falls outside the sRGB gamut. A clipped colour is
not the colour you authored, so treat a gamut warning as a bug in the token, not
as noise.

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
