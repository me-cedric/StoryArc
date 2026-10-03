# Page browser frames, 2026-10-03

These frames come from `page-browser-carousel` and `close-the-audited-gaps`. The iOS device
is the iPhone 17 Pro simulator (lane `0EAA863A-78F3-4839-A910-0B88071D99C2`), iOS 26.2.

| Frame | Task | What it shows |
| --- | --- | --- |
| `ios-comic-menu-chapter-ticks.png` | PB1.4 | Wave 6a. The reader menu on Quiet Machines, a comic with three chapter bookmarks. The page slider has a tick at each chapter start. The tick at page 1 is left out, because the thumb covers it. |
| `ios-page-browser-light.png` | PB3.2 | The carousel open on Quiet Machines, page 2 of 12, in light appearance. The chapter name sits above the carousel; the centred page is drawn larger than its neighbours. |
| `ios-page-browser-light-swiped.png` | PB3.2 | The same carousel after a slow swipe left: the centred preview has moved, the reader's own page has not. |
| `ios-page-browser-dark.png` | PB3.2 | The same open, in dark appearance. |
| `ios-page-browser-right-to-left.png` | PB3.2 | The same comic with its reading direction set to right-to-left from the menu's own Settings section: the carousel and the page-slider ticks mirror, page one at the right end. |
| `ios-thumbnails-light.png` | PB3.2 | `Fine Print`, a comic with no chapter markers: the carousel draws every page with no chapter name or badge, light appearance. |

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

Proven with a mutation: reverting the assignment back to `.toggle()` made
`ThumbnailBrowserTests."Opening the carousel is idempotent, not a toggle"` fail by name;
restoring it passed again. The UI reproducer passed on the lane simulator afterwards,
confirmed on a fresh build and a fresh install, five runs in a row.

## What is still open

- **Largest accessibility text size (`UICTContentSizeCategoryAccessibilityXXXL`)**: the
  capture test for it (and the pre-existing `testCaptureComicMenuAtLargestText`, untouched
  by this wave) skips on this lane with "the page offered no hittable way to open it" —
  the publication detail page's Read action does not become hittable within the wait. This
  reproduces on `Fine Print` as well as `Quiet Machines`, so it is a capture-environment gap
  that predates this wave, not a product defect PB-open or PB3.2 cover. Not captured.
- **Android**: not captured this wave. `ThumbnailStrip.kt`'s carousel (tasks 2.1–2.5) is
  built and unit-tested, but no emulator frame exists yet for light, dark, largest text or
  right-to-left.
