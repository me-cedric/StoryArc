# A tap that curls, and a fold that bends — 2026-10-06

Two tasks of `close-the-audited-gaps` are photographed here, and the four frames are two
pairs. Read the pairs together: the earlier pair was captured before decision D12 landed, so
its fold is the straight one D12 replaces.

| Frame | Task | What it shows |
| --- | --- | --- |
| `android-curl-tap-light.png` | 8.3 | The fold mid-roll, with no finger on the screen. The olive page is turning away — its back dimmed, its leading edge lit — and the blue page beneath is revealed. **The crease is a straight slanted line.** |
| `android-curl-tap-dark.png` | 8.3 | A backwards turn in dark mode, with the reader chrome over the black matte. Its crease is straight and vertical. |
| `android-curl-fold-light.png` | 8.10 | The same reader after D12. The salmon page rolls away over the blue page beneath, and **the crease bends**: it leaves the top edge almost vertical and steepens towards the foot of the page. |
| `android-curl-fold-dark.png` | 8.10 | The same turn one page later in dark mode, blue over green. |

## Task 8.3 — a tap that curls

In Curl mode a tap, a key or a volume button set the page index and the next page appeared.
The fold ran only under a finger that dragged, so the mode a reader chooses *for* its fold
behaved like Fast fade for everyone who taps.

**No finger is on the screen in any of these frames, and that is the whole claim of the first
pair.** A curl at rest is a page, so a settled frame cannot tell Curl from Slide —
`CurlWalk.swift` carries the long version of that argument. What separates these from every
earlier reader frame is that nothing was touching the display: the roll is the spring
`Paging.Curled.goTo` runs after a tap on the leading edge.

## Task 8.10 — a fold that bends

`PageRoll` and both shaders make the fold position a non-linear function of y, so the roll's
leading edge and its cast shadow are curves rather than straight slanted lines. The Android
shader is `PageCurl.kt`:

```
float bow  = xy.y / size.y;
float fold = size.x * (1.0 - progress) + lean * radius * (0.5 - bow * bow);
```

The term in `bow` is quadratic, so the crease moves faster across the screen the further down
the page it is read. **That is what the second pair photographs, and it can be measured rather
than argued about.** Reading the crease's x position at each tenth of the page's height, in
the light frame of each pair:

| Height down the page | 0.1 | 0.2 | 0.3 | 0.4 | 0.5 | 0.6 | 0.7 | 0.8 | 0.9 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `android-curl-tap-light.png` (before D12) | 309 | 305 | 301 | 296 | 292 | 287 | 283 | 278 | 274 |
| `android-curl-fold-light.png` (after D12) | 312 | 309 | 305 | 301 | 296 | 290 | 283 | 275 | 267 |

The first row steps by 4 or 5 pixels every time, which is a straight line. The second steps by
3 at the top and by 8 at the foot, which is the quadratic. The dark frame of the new pair
measures the same curve, 312 down to 268.

**The two pairs are different publications, and that does not weaken the comparison.** The
claim is the shape of one line, and the shape is read off each frame on its own. The earlier
pair cannot be re-shot: the code that drew its straight crease is the code D12 replaced.

## The device, and what was on it

A `Pixel_7_Pro` emulator on Android 14, API 34, with the 19 publications `scripts/corpus.mjs`
builds pushed into the app's own external files directory. The 8.3 pair is *Broken Transfer*
and the 8.10 pair is *Fine Print*, both of which have pages of flat colour — which is what
makes a fold readable at all on a page with no artwork.

*Broken Transfer* is not the subject of the 8.10 pair because the page after its first cannot
be decoded on this corpus build: the curl revealed the matte and the *page could not be read*
notice, so the fold had no page beneath to cast its shadow on.

## How they were taken

`adb shell input tap` returns before the tap lands, and the spring is about three hundred
milliseconds, so a screenshot taken after the command is a picture of the settled page. The
frames come from a screen recording instead, which is the same method `CurlWalk.swift` records
for iOS:

```bash
node scripts/capture-android.mjs "Comic reader" --out /tmp/shot.png   # open the reader
# then, in the reader menu: Page turn › Curl
adb shell screenrecord --time-limit 5 --bit-rate 16000000 --size 720x1560 /sdcard/r.mp4 &
sleep 2 && adb shell input tap 1370 1560       # the leading third
adb pull /sdcard/r.mp4 && ffmpeg -i r.mp4 -vf fps=60 f%03d.png
```

Reaching Curl mode needs the reader menu driven by hand. The sheet opens at its smaller
detent, so the *Page turn* row is below the fold until the sheet is dragged up:

```bash
adb shell input tap 720 1560      # reveal the chrome
adb shell input tap 804 2798      # the ... button
adb shell input swipe 720 2600 720 1100 400   # the sheet's larger detent
adb shell input tap 720 2266      # Page turn
adb shell input tap 213 1384      # Curl
```

`screenrecord` refuses 1440×3120 on this emulator's encoder, so every frame here is 720 wide.
They are photographs of the running app, not renders.

## What is **not** photographed here, and why

**The text size.** A comic page carries no text, and the reader chrome in the dark frames is
two icons. `font_scale 2.0` changes nothing any of these frames could show.

**A difference between the appearances, in the 8.10 pair.** The reader's matte is black under
both appearances and the chrome is hidden in both new frames, so the dark frame differs from
the light one only in which two pages it caught. It is here because §6 of `AGENTS.md` asks for
both and not because it shows something the light frame does not.

**iOS.** `CurlWalkTests.testCaptureCurlTurnedByATap` was added for the 8.3 frame and compiles,
and it **skips** on this machine's simulator — with *"This device's shelf never showed a cover
for Fine Print"*. Its sibling `testCaptureCurlSettled`, which predates that change, skips in
the same place on the same device, after both `scripts/corpus.mjs --simulator` and `pnpm
seed:ios:ui`. So the skip is the seeding gap `AGENTS.md` §6 already records — *"Whatever the
comic path needs is not the corpus alone. Nobody has chased it"* — and not something either
change introduced. The iOS half of 8.3 is asserted by `CurlRequestTests`, and the iOS half of
8.10 by `PageRollTests`; both are unphotographed.

**The last page not lifting** (task 8.5, D10). That frame is an *absence*: the page stays flat
under a forward drag. Driving the emulator to the last page of a publication whose last page
decodes, and holding a drag across a screenshot, did not come off in this session.
`CurlTurnTests.lastPageCannotLiftOffNothing` and its Android twin assert the rule, and both
were proved able to fail.
