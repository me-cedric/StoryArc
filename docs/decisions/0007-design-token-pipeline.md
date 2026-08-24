---
status: accepted
date: 2026-08-24
deciders: Cédric Meyer
---

# ADR-0007 — One OKLCH token source, generated into Swift and Kotlin

## Context and problem statement

Two independent codebases ([ADR-0001](0001-independent-native-cores.md)) that
must look like the same product. The naive approach — a `Color.swift` and a
`Color.kt`, each hand-maintained — guarantees drift, and drift in a palette is
invisible until someone puts two screenshots side by side.

## Considered options

| Option | Why not |
| --- | --- |
| **Style Dictionary** | The standard answer, and a reasonable one. Rejected because it brings a dependency tree and a plugin model to generate two files, and because the contrast gate — the part that actually earns its keep — would be a custom action anyway. |
| **Figma variables as the source** | Better when a designer owns the palette in Figma. There is no separate designer here, and a JSON file in the repository is reviewable in a pull request. Revisit if a Figma library becomes the working surface. |
| **Hand-maintained per platform** | The thing this ADR exists to prevent. |
| **A token package with its own generator** | **Chosen.** One JSON source, ~40 lines of OKLCH arithmetic, a contrast gate in the same script. |

## Decision Outcome

`packages/design-tokens` holds the only definition of StoryArc's colour, type,
spacing, radius and motion values. `scripts/build.mjs` generates
`StoryArcTokens.swift` and `StoryArcTokens.kt` from it. Both apps commit the
generated file, so a fresh checkout builds in Xcode or Gradle with no Node
present, and `pnpm tokens:sync` is the only thing permitted to write them.

### Authored in OKLCH

Colours are authored as `oklch(L% C H)` and converted to sRGB at build time.
OKLCH's lightness is perceptual, so a dark ramp and a light ramp authored at
matching lightness steps genuinely look like the same family — something hex
values cannot express. The conversion is ~40 lines of arithmetic in
`scripts/oklch.mjs` with no dependencies.

### The build gates contrast

`build.mjs` exits non-zero when a text-on-surface pair falls below its WCAG
floor: 4.5:1 for primary and secondary text, 3:1 for tertiary and accents, and
**7:1 (AAA) for every reading theme**, since that text is read for hours.

The pair list is derived from the ramp list rather than enumerated, so adding an
appearance ramp automatically adds its rows. That is what let OLED Dark and
Natural land with no change to the gate itself — the six reading-theme presets
were held to AAA the moment they were authored. It also reports any token outside the sRGB gamut, because a clipped
colour is not the colour that was authored.

This runs in CI on every pull request. An inaccessible palette fails the build
rather than being noticed in review six weeks later.

### Every token carries a stated use

Each token has a `use` string saying where it is allowed to appear, and that
string is emitted as a doc comment in both generated files. A token with no
stated use gets misused; a token whose use appears in autocomplete does not.

## Consequences

- One place to change a colour; both platforms follow.
- Contrast is a build gate, not a review opinion.
- The generated files are committed, which means a token change touches three
  files in one commit. That is the point: the diff shows the source change and
  both consequences together.
- Node is needed to *change* tokens, never to *build* an app.
- Dynamic colour — Material You on Android, cover-derived accents on both — is
  layered on top of these tokens at runtime, not baked into them. The tokens
  define the floor and the fallback; see
  [`native-experience`](../openspec/specs/native-experience/spec.md).

## Links

- Spec: [`native-experience`](../openspec/specs/native-experience/spec.md),
  [`reading-themes`](../openspec/changes/reader-theming-and-page-transitions/specs/reading-themes/spec.md)
  (delta spec, not yet synced).
- Source and generator: `packages/design-tokens`, `scripts/build.mjs`,
  `scripts/oklch.mjs`. Commands: `pnpm tokens:build`, `pnpm tokens:sync`,
  `pnpm tokens:verify`.
- Design system: [`docs/design/DESIGN.md`](../design/DESIGN.md).
- Related decisions: [ADR-0001](0001-independent-native-cores.md) — generated
  tokens are one of the three artefacts the two apps share.
