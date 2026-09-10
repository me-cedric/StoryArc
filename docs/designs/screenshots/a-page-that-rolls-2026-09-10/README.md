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

Captured on 2026-09-11, on an iPhone 17 Pro simulator (1206 × 2622, iOS 26.2),
from the same 3-page fixed-layout fixture the reader walk uses (*Fine Print*).

| Frame | Turned | What it shows |
| --- | --- | --- |
| `ios-roll-forward-early.png` | 0.20 | the fold near the trailing edge |
| `ios-roll-forward-light.png` | 0.53 | the half-turn |
| `ios-roll-forward-late.png` | 0.78 | the fold near the leading edge |
| `ios-roll-forward-detail.png` | 0.53 | the same frame, cropped to the lip |

Read the detail crop left to right and it is the Android crop's description word
for word: the page's unturned front; the crease, which **leans** rather than
standing vertical; the sheet's flat back face, dimmed; the lip, where the
artwork compresses towards the rim and the surface turns into the light; the
dark rim, which is the page's own thickness; and the page beneath, with the
lip's shadow on it.

The three frames together are the claim the reader made — *the curl follows the
finger* — because the fold is in a different place in each and the order is the
order the finger moved. Measured across the whole gesture the turn runs 0.03,
0.15, 0.20, 0.27, 0.34, 0.42, 0.53, 0.63, 0.78, 0.85, 0.94: monotonic, with no
jump and no spring-back.

### How, so the next person does not repeat the search

Three techniques failed before this one, and the note that replaced them named
the wrong blocker. It said the reader had to be put in Curl by hand and that
the chrome hid faster than two tool round trips could reach the button. The
answer was already in the repository: `UITests/CurlWalk.swift` drives the
picker to Curl itself and then drags.

```bash
node scripts/corpus.mjs --simulator <udid>          # or the walk skips: no Fine Print
xcrun simctl io <udid> recordVideo --force curl.mp4 &
xcodebuild test-without-building -project apps/ios/StoryArc.xcodeproj \
  -scheme StoryArc -destination "platform=iOS Simulator,id=<udid>" \
  -only-testing:StoryArcUITests/CurlWalkTests/testCaptureCurlSettled
kill -INT %1
ffmpeg -i curl.mp4 -vf "select='between(t,50.02,50.42)'" -fps_mode passthrough m-%02d.png
```

Two things cost the most time. The walk **skips rather than fails** when the
corpus is absent, and a skip reports exit code 0 — the first run recorded 72
seconds of a library with two books in it and looked like a success. And
`ffmpeg -ss` before `-i` seeks to a keyframe, which silently returned the wrong
four seconds; `select='between(t,...)'` returns the right ones.

**Still not captured on iOS**: the backward roll, and a dark-mode frame. Both
need a walk that does not exist yet — `CurlWalkTests` has one drag, forwards,
in whatever appearance the simulator is set to. `CurledPagesTests` asserts the
backward turn's arithmetic on that platform, and this sentence is the record
that no frame does.

## What it costs

`docs/designs/measurements/curl-frames-2026-09-10.md`.
