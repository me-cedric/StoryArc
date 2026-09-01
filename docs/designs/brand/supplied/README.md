# The brand artwork as supplied

**Kept for reference. The mark itself is `../storyarc-mark.svg`**, which is this drop's
`svg/storyarc-mark.svg` verbatim and is what `scripts/brand-mark.swift` renders.

Supplied 2026-09-01. This is the **second** drop; it replaced a raster-only set and it changed
the method rather than just the pixels.

| | First drop | This drop |
| --- | --- | --- |
| Format | PNG crops from a composite sheet | hand-authored SVG plus rendered PNGs |
| The mark | had to be **reconstructed** from measured proportions | is **read** |
| Gradient | two ends, sampled through baked-in gloss, and the two renders disagreed | four stops, declared |
| Corners | recoverable only as one radius for all six tiles | 14-unit radii on the square corners, and a **different arc radius per tile** — 137, 123, 114, 108 |

No reconstruction from a crop was going to recover those per-tile radii, which is why the
generator now parses the SVG instead of authoring geometry.

## What is here

- `svg/storyarc-mark.svg` — the mark. **The source of truth**, copied to `../storyarc-mark.svg`.
- `svg/storyarc-mark-black.svg`, `svg/storyarc-mark-white.svg` — the same six paths, byte for
  byte, with a flat fill instead of the gradient. Verified identical: the app's monochrome
  layer is generated from the main file rather than from these, so there is one geometry.
- `app-icons/` — the designer's own renders. `ios-appicon-1024.png` is what the generated icon
  was measured against: **88.85% byte-identical**, 99.52% within 8/255, mean difference
  0.68/255, and the remaining 0.225% spans exactly the mark's bounding box, which is its
  anti-aliased outline.
- `lockups/` — the wordmark. Not yet used by either app; there is no surface that shows it.
- `web/` — favicons, PWA and maskable icons. Not used: this repository ships two native apps
  and no web surface. Kept because they are part of the identity and regenerating them from
  the SVG later is a one-line change to the generator's output map.

## What was taken from it

The geometry, verbatim. The gradient's four stops, converted to OKLCH for the token file and
checked to round-trip back to the designer's exact hex. And two measurements that are
composition rather than colour: the mark spans **0.564** of the icon's side, so the inset is
0.218; and the plate is **`#17171F`**, a near-black tinted toward the brand's violet at hue
285, where the app's own `dark.surfaceCanvas` is warm at hue 70. Both are honoured — the icon
is brand territory.

See [`brand-identity-and-app-icons/design.md`](../../../openspec/changes/brand-identity-and-app-icons/design.md).
