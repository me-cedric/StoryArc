# The finger drives the curl over prose, and the end of a book — 2026-10-07

Tasks 8.12, 4.3b (`reader-theming-and-page-transitions`) and 9.7 of `close-the-audited-gaps`.

| Frame | Task | What it proves |
| --- | --- | --- |
| `android-epub-curl-held*.png` | 8.12 | A finger held at 50% of the width in Curl over *The Long Field*. The fold stands under the finger and is curved. The back of the lifted sheet shows mirrored, dimmed text. The next page is already under it. Emulator, an `adb shell input motionevent` drag (DOWN, five MOVE steps, hold, then UP). The reader page stays cream in dark mode because its own theme is Paper; only the system bars change. |
| `ios-epub-curl-held-light.png`, `-dark.png` | 8.12 | The same held drag on iOS, taken from a screen recording while the finger is down for 6 seconds. The sheet is lifted and the next page shows on the right of the fold. |
| `ios-epub-curl-held-settled-*.png` | 8.12 | The page after the finger lifted at 50%: it sprang back to chapter 1 page 1, which is the comic reader's release rule. |
| `ios-epub-curl-chapter-end-held-light.png` | 4.3b | A held drag on the last page of chapter 1 (text ends at 1.14). Under the fold is the first page of chapter 2, with its heading, from the first frame of the drag. No blank and no black. |
| `ios-epub-end-card*.png` | 9.7 | The end card of *Blue Harbour 01* (cover #255B97) takes the cover's adjusted blue. The label colour is the one chosen for that blue. |
| `ios-epub-end-card-no-cover*.png` | 9.7 | The control. *Harbour Lights 01* has no cover, so its card keeps the brand purple with white text. |

Devices: iPhone 17 Pro Max simulator (iOS 26.4) and the `storyarc-ci` emulator (API 35).

## Chapter-end timing on Android (4.3b, owner answer O14)

`ProseCurlProbe` logs `arrived_ms` for each turn (`adb shell settings put global storyarc_frame_probe 1`,
tag `StoryArcProseCurl`). Fourteen forward taps in *The Long Field* at the emulator's 60 Hz:

| Turn | arrived_ms | frames |
| --- | --- | --- |
| Inside a chapter (9 turns) | 143 to 154 | 9 |
| Across a chapter end (taps 3, 6, 9, 12) | 243, 226, 224, 213 | 13 to 15 |

The first tap read 193 ms (a warm-up). A chapter end costs about 75 ms more than a turn inside a
chapter, which is more than one frame. By O14 the Android curl should raster the arriving page
ahead, as iOS does. Android does not yet; the task stays open for that.

## A defect found on iOS, and the fix

A screen recording of ten forward taps showed black bands, one status-bar high above the text and
one below it, on the arriving page at a chapter end. Two causes: the neighbour's resource view is
shorter than the navigator view, so its raster had no pixels in the bands; and the raster taken
after the move was taken while Readium still swapped its views. `ProsePages.ahead` now draws the
neighbour on a canvas that starts as the leaving page, and `ProseCurlDriver.lift` keeps the raster
ahead instead of replacing it. The held chapter-end frame above is clean. Three recorded turns
still showed one black frame in one of three crossings, so the claim is "reduced", not "gone".
The simulator recorder does not keep the frames of a roll that lasts under a second, so the
recording cannot prove it either way; the held frame is the proof.

## What is not here

* **Android end card.** On the emulator the end card did not appear at the last page of either
  book, after 15 forward taps and a swipe. No frame exists. Tracked as task 23.4.
* **Android chapter-end frame.** The probe numbers above stand in for it.
* **Interrupted settle** (a second drag during a spring) was not driven by hand. A unit test
  covers it (`a spring that outlives its own sheet leaves the next turn alone`).

## How to repeat

* iOS held frames: `xcrun simctl io <udid> recordVideo --codec h264 <file>.mov` in one shell,
  `node scripts/capture-ios.mjs --out <dir> --only EpubCurlWalkTests/testCaptureEpubCurlHeldDrag --device <udid>`
  in another, then `ffmpeg -ss <t> -i <file>.mov -frames:v 1 <frame>.png` at the held part. The
  chapter-end frame uses `testCaptureEpubCurlHeldAtAChapterEnd`. The end cards use
  `testCaptureEpubEndCard` and `testCaptureEpubEndCardWithoutACover`. The blue book is two EPUBs
  built from `Harbour Lights 01` with a flat #255B97 cover, copied into the app's `Documents/Corpus`.
* Android: push the corpus into `/sdcard/Android/data/com.mecedric.storyarc.debug/files/`, run the
  route `"EPUB reader > Long Field curl chosen"` once, then
  `"EPUB reader > Long Field page"`, and drive `adb shell input motionevent DOWN 972 1200`,
  `MOVE 900 1200 … 540 1200`, wait, `adb exec-out screencap -p`, `UP 540 1200`.
