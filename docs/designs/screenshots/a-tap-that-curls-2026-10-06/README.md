# A tap that curls — 2026-10-06

Task 8.3 of `close-the-audited-gaps`. In Curl mode a tap, a key or a volume button set the
page index and the next page appeared. The fold ran only under a finger that dragged, so
the mode a reader chooses *for* its fold behaved like Fast fade for everyone who taps.

| Frame | What it shows |
| --- | --- |
| `android-curl-tap-light.png` | The fold mid-roll, with no finger on the screen. The olive page is turning away — its back dimmed, its leading edge lit — and the blue page beneath is revealed. |
| `android-curl-tap-dark.png` | The same turn in dark mode, with the reader chrome over the black matte. |

**No finger is on the screen in either frame, and that is the whole claim.** A curl at rest
is a page, so a settled frame cannot tell Curl from Slide — `CurlWalk.swift` carries the
long version of that argument. What separates these two from every earlier reader frame is
that nothing was touching the display: the roll is the spring `Paging.Curled.goTo` runs
after a tap on the leading edge.

## The device, and what was on it

A `Pixel_7_Pro` emulator on Android 14, API 34, with the 19 publications
`scripts/corpus.mjs` builds pushed into the app's own external files directory. The
publication is *Broken Transfer*, whose pages are flat colours — which is what makes the
fold readable at all on a page with no artwork.

## How they were taken

`adb shell input tap` returns before the tap lands, and the spring is about three hundred
milliseconds, so a screenshot taken after the command is a picture of the settled page. The
frames come from a screen recording instead, which is the same method `CurlWalk.swift`
records for iOS:

```bash
node scripts/capture-android.mjs "Comic reader" --out /tmp/shot.png   # open the reader
# then, in the reader menu: Page turn › Curl
adb shell screenrecord --time-limit 4 --bit-rate 16000000 /sdcard/r.mp4 &
sleep 1.5 && adb shell input tap 1370 1560       # the leading third
adb pull /sdcard/r.mp4 && ffmpeg -i r.mp4 -vf fps=20 f%03d.png
```

`screenrecord` refuses 1440×3120 on this emulator's encoder and falls back to 720×1280, so
both frames are at that size. They are photographs of the running app, not renders.

## What is **not** photographed here, and why

**The text size.** A comic page carries no text, and the reader chrome in the dark frame is
two icons. `font_scale 2.0` changes nothing either frame could show.

**iOS.** `CurlWalkTests.testCaptureCurlTurnedByATap` was added for exactly this frame and
compiles, and it **skips** on this machine's simulator — with *"This device's shelf never
showed a cover for Fine Print"*. Its sibling `testCaptureCurlSettled`, which predates this
change, skips in the same place on the same device, after both `scripts/corpus.mjs
--simulator` and `pnpm seed:ios:ui`. So the skip is the seeding gap `AGENTS.md` §6 already
records — *"Whatever the comic path needs is not the corpus alone. Nobody has chased it"* —
and not something this change introduced. The iOS half of task 8.3 is asserted by
`CurlRequestTests` and is unphotographed.

**The last page not lifting** (task 8.5, D10). That frame is an *absence*: the page stays
flat under a forward drag. Driving the emulator to the last page of a publication whose
last page decodes, and holding a drag across a screenshot, did not come off in this session.
`CurlTurnTests.lastPageCannotLiftOffNothing` and its Android twin assert the rule, and both
were proved able to fail.
