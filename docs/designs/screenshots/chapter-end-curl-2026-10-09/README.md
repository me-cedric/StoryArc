# The curl across a chapter end, measured on both platforms - 2026-10-09

Task 4.3b of `reader-theming-and-page-transitions`, owner answer O14. The Android frames of the
chapter end are in `../curl-recorded-2026-10-08/` (`android-epub-curl-chapter-end-*`).

## Android: the raster ahead

Route 1 of O14 is built for Android (`ProseAhead.kt`): at a chapter end, the page that the turn
arrives at is rastered from Readium's view before the navigator moves. Measured on the
emulator (60 Hz) with `storyarc_frame_probe 1`, `adb logcat -s StoryArcProseCurl`, The Long Field
in Curl, one tap per 1.7 s. `ahead=true` is a chapter end. The number is the time to the raster
of the arriving page.

| Turn | Before (wave 2) | After |
| --- | --- | --- |
| Inside a chapter | 143 to 154 ms | 40 to 100 ms (3 to 6 frames; one first turn of 270 ms) |
| Across a chapter end | 213 to 243 ms (13 to 15 frames) | 9 to 18 ms (1 frame) in 11 of 12 turns, one of 51 ms |

The gap of about 75 ms at a chapter end is gone. `android-epub-curl-chapter-end-1..4` are four
frames of a recording of one such tap. The page under the fold is Chapter 6 from the first
frame (`6.1` to `6.5` show), and `android-epub-curl-chapter-end-after.png` is the settled page.
Frames 2, 3 and 4 are the same to the pixel. The recording has no new frame in that time, so
this set does not show that the fold moved without a stop there. A turn on a phone must
answer that.
The in-chapter number is the old figure for the raster taken after the move, and is a different
measure from the chapter-end one. It did not change.

## iOS: the black band

Wave 2 saw one black frame in one crossing in three. This lane measured it again, with
`EpubCurlWalkTests/testCaptureEpubCurlBlackFrameScan` (16 turns forward and 16 back, at every
chapter end of the book) under `simctl recordVideo`, 60 fps, scanned with `ffmpeg signalstats`
(10th-percentile luma; a black band over 10% of the frame reads 16).

- **Before the fix:** in 8 752 frames, 44 frames in 7 events had black bands above and below the
  page, 5 to 9 frames (80 to 150 ms) each. The events lie at the chapter ends.
  `ios-before-chapter-end-frames-dark.png` is one event, frame by frame.
- **Cause:** `ios-before-raster-ahead-bands.png` is the raster that `ProsePages.ahead` made
  (right of each pair) next to the page it was laid over (left). The neighbour's resource view
  paints black where its web view does not reach, and the raster drew the whole view.
- **Fix:** the neighbour is drawn through a window of its web view only
  (`ProsePages.window`). The leaving page fills the rest. `ProseCurlTests` asserts the window.
- **After:** in 9 111 frames the lowest 10th-percentile luma was 53. No black band.

`ProseCurlOnABookTests` (host test, no pixels) again: inside a chapter the move took 2 to 20 ms,
across the chapter end 117 ms (7 frames), which the raster ahead hides.

## Backward turns on Android

Readium scrolls a neighbour chapter to its arriving page only when it becomes current. A
previous chapter that loaded fresh shows its first page. So `ProseAhead.raster` rasters a
neighbour only when its web view cannot scroll toward the current page. In the other case the
curl waits for the navigator, as before. The measurements above are forward turns only.

## Repeat

iOS: `node scripts/record-ios-walk.mjs --only EpubCurlWalkTests/testCaptureEpubCurlBlackFrameScan
--out /tmp/scan --device <udid> --appearance light --fps 0`, then scan with `ffmpeg -i walk.mov
-vf "fps=60,scale=134:-1,signalstats,metadata=print:key=lavfi.signalstats.YLOW" -f null -`.
Android: arm the probe, open a reflowable book in Curl, tap the trailing third repeatedly, read
`adb logcat -d -s StoryArcProseCurl`.
