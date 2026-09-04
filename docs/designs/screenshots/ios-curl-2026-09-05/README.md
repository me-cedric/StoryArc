# The iOS page curl, verified — 2026-09-05

`reader-theming-and-page-transitions` §4.3 and §7.5. The curl shipped on both platforms and
only one was ever looked at: Android was driven frame by frame with held `motionevent` gestures
on the emulator, and iOS was recorded as **"built and compiles, and is not visually verified"**.
These are the frames that verify it.

Taken on `StoryArc-iPhone17Pro` (iOS 26.5, 402 pt wide, 1206 px), light appearance, over *Fine
Print* — a fixed-layout comic, because the curl needs the **incoming** page as a second texture
before it is on screen and reflowable text cannot supply one yet (`PageTransition.needsTwoRasters`;
§4.3b owns lifting that).

## The frames

| Frame | Fold position | What it shows |
| --- | --- | --- |
| `ios-curl-fold-84.png` | 83.6% | The turn just begun; the flipped band is still narrow |
| `ios-curl-fold-77.png` | 76.7% | The clearest frame — all four features at once |
| `ios-curl-fold-70.png` | 69.6% | The fold has travelled; the reveal has widened to match |
| `ios-curl-fold-62.png` | 62.5% | Past halfway, so this turn will complete on release |
| `ios-curl-settled.png` | — | After the lift: page 2, blue. The turn completed |

## What they establish, against Android's own description

The two platforms are judged against **one** description rather than two, because `design.md`
asks for one projection expressed twice rather than solved twice.

- **The fold tracks the finger.** 83.6% → 76.7% → 69.6% → 62.5% across four consecutive frames
  at 20 fps. A single frame cannot tell a fold that tracks from one painted at a fixed
  fraction; four consecutive ones can.
- **The turned sheet shows the page's back.** The band left of the fold is the same orange,
  dimmed — mirrored about the fold, so its left edge sits at `2f − W`. Measured on
  `ios-curl-fold-77.png`: flat page to 53.4%, flipped band 53.4% → 76.7%, which is exactly the
  mirror of the 23.3% of sheet that lay right of the fold. A mirrored image at full brightness
  reads as a reflection rather than as paper, which is why it is dimmed.
- **The leading edge catches light.** A pale strip at the fold itself, `rgb(250,208,192)`
  against the page's `rgb(230,154,126)`.
- **The revealed page is darkest against the fold.** The next page ramps from `rgb(73,86,107)`
  at the fold to `rgb(130,153,192)` in the open — the only place a lifted page can cast a
  shadow.
- **Releasing past halfway completes the turn.** `ios-curl-settled.png` is page 2.

## How to retake them

**A screenshot cannot catch this, and the first attempt at one produced a wrong answer.**
`XCUIElement`/`XCUICoordinate.press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)`
returns after the entire gesture — the hold **and the lift** — so a shutter after it always
photographs a settled page. Two such frames were read as proof that the curl did not track the
finger (a fold at 95.4% with the finger held at 50%, and at 2% with the finger at 22%) before
the arithmetic gave the harness away: 0.42 of a turn springs back and 0.70 completes, which is
precisely what `CurlTurn.settles` says. The shader was right and the walk was wrong.

XCUITest has no primitive that holds a touch down across a screenshot, so the curl is recorded
and the frames are pulled from the video:

```bash
UDID=11DFC984-7DF7-4E1A-99F6-B7B4BED091F8
xcrun simctl io $UDID recordVideo --codec h264 --force /tmp/curl.mov &
REC=$!
node scripts/capture-ios.mjs --out /tmp/curl \
  --only "CurlWalkTests/testCaptureCurlSettled" --appearance light
kill -INT $REC
ffmpeg -ss $(python3 -c "import subprocess;print(max(0,float(subprocess.check_output(
  ['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0','/tmp/curl.mov']))-14))") \
  -i /tmp/curl.mov -vf fps=20 -pix_fmt rgb24 /tmp/frames/f%04d.png
```

Then find the frames that hold both pages with a boundary away from either edge; the turn takes
about a fifth of a second, so there are four or five of them.

`CurlWalkTests.testCaptureCurlSettled` is the only walk here that photographs anything by
itself, and it photographs the *outcome*. The mid-turn frames come from the recording — which
is also what §7.5 asks for, since a still cannot show that a gesture is interruptible.

## What is not covered here

- **Right-to-left.** The shader mirrors the coordinate rather than being a second shader, and
  Android's pass verified the mirrored gesture on the emulator. No iOS frame yet: the corpus
  has no right-to-left publication, so it needs a fixture before a walk can reach it.
- **Interruption.** A second drag during the settle takes the page over from where it stands —
  `settle &+= 1` and `base = stand.value` in `CurledPages.turnGesture`. Asserted in
  `CurlTurnTests`, not photographed: two overlapping touches are beyond what a single recorded
  walk can drive.
- **Frame rate.** ADR-0009 lists it as unsettled and it stays unsettled. A recording of a
  simulator says nothing about a device's refresh rate, and `page-transitions` — "the app never
  ships a curl that stutters in preference to a slide that does not" — is a claim about
  hardware this repository has not run on.
- **Dark appearance**, and any theme but the default.
