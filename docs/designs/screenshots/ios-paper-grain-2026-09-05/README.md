# The procedural paper grain, judged — 2026-09-05

`reader-theming-and-page-transitions` §0.5. That task asked for a prototype on both platforms
and a **judgement** of whether the grain reads as paper; §5.4 built the shader on both and wired
it to the page, and recorded that "0.5's own question is a *judgement*, and that still needs a
screen". No iOS frame of it existed. These two are that screen.

`StoryArc-iPhone17Pro`, light appearance, the reflowable reader over *The Long Field*, chrome
timed out so the frame is page only. The pair differs in one launch argument —
`-storyarc.appearance.natural` — so the difference between them **is** the texture.

| Frame | |
| --- | --- |
| `ios-reader-grain-on.png` | Natural on |
| `ios-reader-grain-off.png` | Natural off — the twin the texture is measured against |

## The judgement: it reads as paper. No bundled tile is needed.

**A pair, because grain at a plausible strength is invisible in isolation and obvious in
comparison.** Looking at either frame alone settles nothing — at these amplitudes a screenshot
viewed at page scale shows a flat page — so the answer is measured off the pair rather than
argued from one picture.

Over the page region (the middle half of the frame, excluding both chrome bands):

- **64% of pixels are modulated**, and modulated *gently*: 36% untouched, 22% by one level out
  of 255, 14% by two, tailing to six and beyond. A texture that reads as paper has to be
  present nearly everywhere and almost nowhere strong, and that is this distribution.
- **The tint is warm, not grey.** Mean signed delta R −1.61, G −1.86, B −2.00: the grain
  darkens, and it takes about 24% more blue than red. That is the whole point of §5.4's
  warm/dark tint pair — symmetric grey speckle reads as sensor noise, which is the one thing
  this must not look like, and a symmetric shader would show three equal means here.
- **The speckle is fibre-scale and has more than one frequency in it.** Run lengths along a
  scanline are a median of 2 px with a maximum of 14 px at 3×, so roughly 0.7 pt typical. A
  single-octave hash would produce a narrow spread of run lengths; the long tail is the second
  octave at 2.17× beating against the first, which is what §5.4 built it for.

So the fallback §0.5 held in reserve — pricing a bundled tiling texture — is **not needed**.
Procedural noise was the cheaper answer and it is also the right-looking one: no bytes, no
resolution ceiling, and a texture that survives a text-size change because it is not tied to a
bitmap's pixel grid.

## What this does not settle

- **Dark appearance.** Grain over a dark page is a different perceptual problem — the same
  modulation is a larger fraction of the available range — and there is no dark pair here.
- **Android.** `android-grain-1to1-light.png` in the 2026-09-02 sweep is the Android frame, and
  it has never been measured against a Natural-off twin the way this pair has. The shader is
  one texture expressed twice, so the numbers should match; nobody has checked.
- **A real display.** These are simulator frames. A modulation of one or two levels out of 255
  is exactly the range where a panel's own gamma and dithering could take it away, and no
  device has been looked at.
- **The refusals.** Reduce Transparency and Increase Contrast both turn the grain off, and
  neither is photographed here; `GrainWalkTests` has no launch argument for either.
