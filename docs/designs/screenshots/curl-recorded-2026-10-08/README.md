# The curl, taken from recordings - 2026-10-09

A curl at rest is a page, so a screenshot cannot show it. Every frame here was cut from a screen
recording: `adb shell screenrecord` on Android (720 x 1600, because the encoder refuses the full
size) and `xcrun simctl io <udid> recordVideo` on iOS (1206 x 2622, or 603 wide for the text book).
`scripts/record-android-turn.mjs` and `scripts/record-ios-walk.mjs` run the two recipes.

| Task | Frames | What they prove |
| --- | --- | --- |
| 7.5, Android curl mid-turn | `android-comic-curl-drag-1..4`, `android-epub-curl-drag-1..4` | A held forward drag on a comic page and on a text page. The fold moves from the trailing edge toward the middle across four frames and the page under it is the next page. |
| 7.5, interruption | `android-comic-curl-interrupt-1..3`, `android-epub-curl-interrupt-1..3`, `ios-comic-curl-interrupt-1..3`, `ios-epub-curl-interrupt-1..3` | A drag lifted past halfway, then a second touch put down while the settle runs and carried back. In every set the fold is carried from where the first drag left it: no frame shows the page back at its start or whole at its end between the two touches. |
| 8.5, last page | `ios-comic-curl-last-page-held-light.png`, `ios-comic-curl-last-page-held-dark.png` | A held forward drag on the last page of a comic: the end screen (*Finished*, the title, *First page* and *Library*) is under the lifting sheet, and nothing lifts into empty space. The Android frames are in `../curl-last-page-2026-10-07/`. |
| 4.3b, chapter end | `android-epub-curl-chapter-end-1..4`, `android-epub-curl-chapter-end-after.png` | See `../chapter-end-curl-2026-10-09/README.md`. |

Frames of a tap that curls on iOS are in `../a-tap-that-curls-2026-10-06/`.

## Limits

- A recording holds 30 to 60 frames a second at best, and the emulator's `screenrecord` less. A
  snap that lasts one display frame can fall between two recorded frames. The frames show no
  jump larger than the finger's own step. They do not prove there was none.
- The iOS text-book frames are of a page in the dark Quiet theme. The curl is the same on a
  light page. The comic pages are flat colour on purpose, so that the fold is readable.
- The interrupted drag on iOS is two `press(forDuration:thenDragTo:)` calls, which start about
  one frame apart. On Android the touches come from `cmd input motionevent`, 20 ms apart.

## Repeat

```bash
node scripts/record-android-turn.mjs tap|drag|interrupt --out /tmp/rec     # reader open, in Curl
node scripts/record-ios-walk.mjs --only CurlWalkTests/testCaptureCurlInterrupted \
    --out /tmp/rec --device <udid> --appearance light --fps 60
```

The iOS walks are `testCaptureCurlInterrupted` (comic), `testCaptureEpubCurlInterrupted` (text),
and `testCaptureCurlLastPageHeld` (last page).
