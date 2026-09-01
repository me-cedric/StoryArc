# The brand artwork as supplied

**Kept for reference, and not shipped.** These are the files the owner supplied on
2026-09-01, committed so the measurements taken from them can be re-checked and so the design
intent survives independently of anyone's memory of it.

**They are not the app's assets.** Every one is a raster crop from a larger composite sheet:

- `StoryArc-Icon-Transparent-1024.png` is not transparent. It carries a white rounded-rect
  plate with a speckled grey edge from the crop.
- The mark is off-centre in its own canvas — it occupies 528×660 of 1024, offset left and
  high.
- The two renders disagree at the violet end of the gradient: the icon finishes at hue 289
  and the lockup runs on to 267, which is blue.
- Gloss highlights and bevels are baked in, so the same petal reads as three colours.

What was taken from them is **the design**, and the numbers:

| Sample | sRGB | OKLCH |
| --- | --- | --- |
| Icon, pink end | `#FD5EA8` | `oklch(70.9% 0.205 355)` |
| Icon, violet end | `#6D33E9` | `oklch(51.6% 0.249 289)` |
| Lockup, pink | `#FE649A` | `oklch(71.3% 0.193 2)` |
| Lockup, violet | `#883FFB` | `oklch(57.1% 0.257 294)` |

Measured by decoding the PNGs and taking the median of a 28×28 patch inside each petal, away
from the gloss along each top edge and the bevel along each bottom.

The shipped mark is **generated** from geometry — see
[`brand-identity-and-app-icons/design.md`](../../../openspec/changes/brand-identity-and-app-icons/design.md).
