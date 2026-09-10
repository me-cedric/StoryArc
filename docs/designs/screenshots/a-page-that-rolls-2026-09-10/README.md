# A page that rolls, both ways — 2026-09-10

The page curl, on a OnePlus 7T Pro (`f7cee850`, 1440 × 3120, 90 Hz), in curl mode, on a
178-page comic held on the device. Change: `a-page-that-rolls-both-ways`, tasks 5.1
and 5.2. Every mid-gesture frame was taken with the finger still down, by holding an
`adb shell input motionevent` drag at a point and screenshotting before the release.

## The control: what a fold looked like

`android-fold-forward-light-before.png` — the same page, the same drag, the same phone,
with the lip's radius set to zero, which is exactly the shader this change replaces.

Three vertical lines: the crease, the sheet's free edge, and the shadow. Nothing about
the picture says a sheet is bending; it says one picture is being wiped over another,
which is what the reader reported as "the page turns flat".

## The roll

| Frame | Direction | Theme | Progress |
| --- | --- | --- | --- |
| `android-roll-forward-light.png` | forward | light | ≈ 0.5 |
| `android-roll-forward-dark.png` | forward | dark | ≈ 0.5 |
| `android-roll-backward-light.png` | backward | light | ≈ 0.5 |
| `android-roll-backward-dark.png` | backward | dark | ≈ 0.5 |
| `android-roll-forward-detail.png` | forward | light | ≈ 0.5, cropped to the lip |

The detail crop is the one to look at. Left to right: the sheet's flat back face, dimmed;
the lip, where the artwork compresses towards the rim because the texture is mapped by
arc length and the surface turns away from the light; the dark rim, which is the page's
own thickness; then the page beneath, with the lip's shadow falling on it. The fold leans,
so none of those edges is a vertical line.

`android-roll-at-rest.png` is the same reader with no finger on it: no lip, no shadow,
nothing. The radius is a sine of the progress, so a page at rest and a page just landed
are pixel-for-pixel the fold they were.

## Turning back

`android-roll-backward-*.png` is a drag the other way, which before this change did
nothing at all: the turn's progress was clamped at zero, so a backwards drag from a flat
page was arithmetically the same as no drag. There is no "before" frame for it, because
the before is an unchanged screen — the reader's own report is the control: "page curl
only seems to work in one direction, sliding to the previous page does nothing".

## iOS

**Not captured, and the reason is the simulator rather than the shader.** Three techniques,
and what each one hit:

1. **A held drag.** The simulator's injected touches complete before a `simctl` screenshot
   lands, at every timing tried — the frames come back as the page before the turn or the
   page after it, never the turn.
2. **Slow animations.** Toggled from the Simulator's own Debug menu, which needs a
   keystroke, which needs an accessibility permission this session will not ask the system
   for.
3. **Video capture, which works.** `xcrun simctl io … recordVideo` during a swipe, then
   `ffmpeg -vf fps=20` and pick the frame where both pages are on screen — that produced
   clean mid-transition frames. What it produced was a *slide*, not a roll: the simulator's
   reader is in Slide mode, and the mode is set from the reader menu, whose chrome hides
   faster than two tool round trips can reach the button.

**So the shortest path for whoever picks this up**: on the simulator, open a comic and set
*Page turn → Curl* by hand, then record and extract as in 3. The technique is proven; only
the mode was wrong.

What stands behind the iOS shader instead: `PageCurlShaderTests` asserts that the Metal
and the AGSL are the same code, expression by expression, and `PageRollTests` asserts the
projection's own arithmetic against the same table of numbers Android's `PageRollTest`
uses. Both are tripwires rather than proofs, and this paragraph is the honest statement
of what has not been seen.

## What it costs

`docs/designs/measurements/curl-frames-2026-09-10.md`.
