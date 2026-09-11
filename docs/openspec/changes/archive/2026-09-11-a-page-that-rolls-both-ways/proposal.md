# A page that rolls, both ways

**Platforms: both.** One projection expressed twice, as ADR-0009 already
requires: `PageCurl.kt` (AGSL) and `PageCurl.metal` are line-for-line
counterparts and stay that way. The gesture change is mirrored in
`CurledPages.kt` and `CurledPages.swift`.

## Why

Two things a reader found on a real device, on the same screen.

**The page will not turn back.** `CurlTurn.progress` clamps to `0f..1f` from a
base of zero, and `onTurned()` is the only completion the gesture has. A drag
towards the previous page is arithmetically incapable of moving the sheet. The
reader is not meeting a bug in the maths; there is no backwards turn to meet.
`page-transitions` never asked for one, which is why nothing caught it — but a
page turn that only goes one way is not a page turn, and every other mode in the
picker moves in both directions.

**The turn reads flat.** That one is by design, and the design is being changed.
ADR-0009 abandoned the cylinder it set out to build, on the argument that a
crease seen straight down is edge-on: "every point on the cylinder projects to a
position that the flat turned sheet, being higher, also covers. **The crease
contributes no pixels.**" That is true of a crease with no radius. A magazine
does not fold — its sheet bends over a rounded spine of real width, and that
width is exactly what a reader recognises: a curved leading edge instead of a
straight one, a band of the page's back that widens as the sheet lifts, and a
shadow that follows the curve rather than a line. The owner has asked for the
magazine, having seen the fold.

## What Changes

- **The turned sheet is a roll, not a fold.** Its leading edge is a curve, the
  back of the sheet is revealed as a band whose width follows the roll's radius,
  and the shadow cast on the page beneath follows that curve. The three regions
  ADR-0009 names survive; what changes is that the boundary between them is no
  longer a straight line and the crease now draws pixels.
- **The curl turns backwards.** A drag away from the direction of reading lifts
  the *previous* page in from the opposite edge and lays it down over the
  current one, with the same release rule — past halfway it completes, before it
  it springs back, a flick completes it regardless of distance.
- **Both directions obey reading direction.** A right-to-left publication
  mirrors both, as the forward turn already does.
- **The 120 Hz floor is unchanged and is the constraint on the roll.** The spec
  already refuses a curl that stutters in preference to a slide that does not,
  and a roll that cannot hold the display's refresh rate is not shipped as one.
- **BREAKING for ADR-0009's fold section only.** The decision "it is a fold, and
  the crease draws nothing" is superseded. Everything else that ADR decides —
  one fragment shader over two decoded page textures, no mesh, no re-raster for
  comics, expressed twice — is untouched and is what makes this change small.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `page-transitions`: *The page follows the finger* gains what the sheet looks
  like as it lifts, which the requirement does not currently say — it asks only
  that the page "deforms and lifts", which a fold satisfies. A new scenario
  gives the curl a backwards turn, which no requirement asks for today.

## Impact

- `apps/android/feature/reader`: `PageCurl.kt` (the shader), `CurledPages.kt`
  (the gesture and the two page textures), `CurlTurn` inside it.
- `apps/ios/Packages/StoryArcKit/Sources/ReaderFeature`: `PageCurl.metal`,
  `CurledPages.swift`.
- `docs/decisions/0009-page-curl-as-a-fragment-shader.md`: superseded in part,
  with the reason recorded rather than the section deleted.
- The reader's page source must be able to hand the *previous* page's bitmap to
  the shader, where today it hands the current page and the one beneath.
- No change to progress, storage, or any format.

## Non-goals

- **No new curl mode in the picker.** Roll replaces fold; a reader is not asked
  to choose between them.
- **No mesh, no re-raster.** ADR-0009's core decision stands. A roll that needs
  a vertex mesh is out of scope; if the projection cannot be expressed in the
  fragment shader at the refresh rate, that is a finding to bring back, not a
  licence to add geometry.
- **No change to slide or fade.**
- **Not the EPUB reflowable turn**, which is Readium's own paging.
