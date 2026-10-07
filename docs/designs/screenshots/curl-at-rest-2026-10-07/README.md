# Curl at rest draws the normal page body, 2026-10-07

Task 8.16 of `close-the-audited-gaps`, decision D33. At rest, Curl draws the page the way
Slide does: the chosen fit, the pinch, the marks. The shader runs only while a turn runs.

The comic is `Tall Pages 01.cbz`, built for this proof: four pages of 500 x 1500 pixels, with a
white line every 150 pixels. A tall page tells Fit to Width from Fit to Screen.

## Android, emulator `storyarc-ci`

| Frame | What it proves |
| --- | --- |
| `android-curl-rest-fit-width.png` | Curl at rest, Fit to Width. The page fills the width and runs past the screen. |
| `android-curl-rest-zoomed.png` | The same page after a double tap: zoomed. |
| `android-curl-rest-zoomed-panned.png` | After a sideways drag. The page panned, and the reader stayed on page 1 of 4 (read with uiautomator). It did not turn. |
| `android-curl-rest-pdf-light.png`, `-dark.png` | A PDF page in Curl, after one highlight was saved. |
| `android-slide-rest-pdf-control.png` | The control: the same PDF page in Slide. |

**An Android PDF paints no highlight.** The highlight is saved (the Highlights list shows it),
and neither Curl nor Slide draws it on the page. This is the same in both modes, so Curl at
rest matches Slide. Whether Android should paint a PDF highlight is a separate question.

The dark appearance gave an identical comic frame, so none is kept.

## iOS, simulator iPhone 17 Pro Max, iOS 26.4

| Frame | What it proves |
| --- | --- |
| `ios-curl-rest-fit-width-light.png`, `-dark.png` | Curl at rest, Fit to Width requested. |
| `ios-slide-rest-fit-width-control-light.png` | The control: Slide, the same fit. The two frames match. |
| `ios-curl-rest-zoomed-light.png` | After a double tap at the centre: zoomed. |
| `ios-curl-rest-zoomed-panned-light.png` | After a sideways drag. The page panned and did not turn (it is still the orange first page). |
| `ios-curl-rest-pdf-marks-light.png` | A PDF page in Curl at rest. The saved yellow highlight on "Field" shows. |

**An open question on iOS.** In the two fit frames the page sits right of centre, with matte
on its left, and it does not fill the width. Slide shows the same, so Curl did not cause it.
It may mean that the Width choice did not apply to this tall page. Nobody has checked.

## How to repeat

```bash
python3 <build Tall Pages 01.cbz>   # four 500 x 1500 PNG pages, stored in a ZIP
node scripts/capture-ios.mjs --out <dir> --only CurlWalkTests/testCaptureCurlAtRestFitWidth --device <udid>
# also testCaptureSlideRestFitWidth, testCaptureCurlAtRestZoomedAndPanned, testCaptureCurlRestPdfMarks
# Android: reader menu > Page turn > Curl, Fit > Fit to width; double tap; swipe sideways.
```
