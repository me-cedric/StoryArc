# Page browser frames, 2026-10-03

These frames come from `page-browser-carousel` and `close-the-audited-gaps`. The iOS device
is the iPhone 17 Pro simulator (lane `0EAA863A-78F3-4839-A910-0B88071D99C2`), iOS 26.2.

| Frame | Task | What it shows |
| --- | --- | --- |
| `ios-comic-menu-chapter-ticks.png` | PB1.4 | Wave 6a. The reader menu on Quiet Machines, a comic with three chapter bookmarks. The page slider has a tick at each chapter start. The tick at page 1 is left out, because the thumb covers it. |
| `ios-page-browser-right-to-left.png` | PB3.2 | The carousel open on Quiet Machines, light appearance, with the reading direction set to right-to-left from the menu's own Settings section. Page one is at the right end, and the page-slider thumb and ticks mirror. The sheet is at its large detent. |
| `ios-page-browser-right-to-left-dark.png` | PB3.2 | The same comic, right-to-left, in dark appearance, at the medium detent. |
| `ios-thumbnails-light.png` | PB3.2 | `Fine Print`, a comic with no chapter markers, left-to-right: the carousel draws every page with no chapter name or badge, light appearance. |

| `ios-page-browser-light.png` | PB3.2 | Added at the wave 6b merge, on the iPhone 17 Pro simulator, iOS 26.5. Quiet Machines, left to right, light. Page 1 is centred with its "#1" badge, "Prologue" is above, and the page numbers sit on one line. |
| `ios-page-browser-swiped-light.png` | PB3.2 | The same walk after one swipe. Page 2 is the large page, the chapter is still "Prologue", and page 5 carries "#4", read from its bookmark "Quiet Machines #4". After a swipe, the large page sits a little left of the middle. |
| `ios-page-browser-dark.png` | PB3.2 | Left to right, dark. |

Not captured yet: the largest text size, and the Android carousel (task 3.2 stays open).

## Review correction

The worker's first set also held `ios-page-browser-light.png`, `ios-page-browser-light-swiped.png`
and `ios-page-browser-dark.png`, described as left-to-right. All three showed right-to-left.
The cause: the right-to-left walk chooses the direction from the menu, and the app keeps that
choice for the shelf. Later walks on Quiet Machines inherited it. The light frames were
removed, and the dark frame was renamed to what it shows.

The walks now launch with `freshShelfSettings: true`, so each one starts from the built-in
reader settings. `openPageBrowser(in:rightToLeft:)` asserts the direction: page 2 must be on
the right of page 1, or on the left for right-to-left. On the lane simulator, with
right-to-left stored for Quiet Machines, the light and dark walks passed as left-to-right.

## PB-open, the defect wave 6a left open

Wave 6a's README recorded that `SweepComicReaderTests.testCaptureComicPageBrowser` failed:
"from a UI test, the Contents tap does not open the carousel." A log line placed at the top
of `ReaderMenuProgress.openContents()` confirmed the method was never called — the tap never
reached it, with no error from the tap itself and the sheet already fully settled.

The cause: `contentsRow` is the first row of the sheet's `List`, directly under the grabber
that `.presentationDetents([.medium, .large])` uses to drag the sheet between its two
heights. With no competing recognizer on the row, that drag gesture sometimes won the
gesture arena for a tap that never left the row, and the `Button`'s own action never ran.
Every other row sits further from the grabber and was unaffected.

The fix (`ReaderMenuProgress.swift`) adds a `.simultaneousGesture(TapGesture())` to the row
that also calls `openContents()`, asking to recognize alongside the sheet's drag rather than
lose to it. `openContents()` now assigns `isBrowsingThumbnails = true` rather than toggling
it, because the row can call it twice for one tap (the `Button`'s action and the new
gesture, when both recognizers accept) and a toggle would net back to `false`.

Proven with two mutations:

- Without the `simultaneousGesture`, `testCaptureComicPageBrowser` and
  `testCaptureComicPageBrowserDark` both failed "Contents opened no page browser." on the
  lane simulator. With it restored, they passed.
- Back to `.toggle()`, `ThumbnailBrowserTests."Opening the carousel is idempotent, not a
  toggle"` failed by name. The same host test also fails when the gesture line is removed.

## What is still open

- **Left-to-right frames of a comic with chapter markers**, in light and in dark. Run
  `testCaptureComicPageBrowser` and `testCaptureComicPageBrowserDark` again to capture them.
- **Largest accessibility text size (`UICTContentSizeCategoryAccessibilityXXXL`)**:
  `testCaptureComicPageBrowserAtLargestText` skips with "the page offered no hittable way to
  open it". An element dump at the skip shows that the app is still on the shelf: the tap on
  the Quiet Machines cover did not open the publication page. The shelf at this size also
  shows the "2 couldn't be opened" banner and the alphabetical index. The pre-existing
  `testCaptureComicMenuAtLargestText` skips the same way. Look at the shelf at this text size
  to find what takes the tap. Not captured.
- **Android**: not captured. `ThumbnailStrip.kt`'s carousel (tasks 2.1–2.5) is built and
  unit-tested, but no emulator frame exists yet for light, dark, largest text or
  right-to-left.
