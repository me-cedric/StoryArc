# Page browser frames, 2026-10-03

These frames come from wave 6a: `page-browser-carousel` and `close-the-audited-gaps`. The device is the iPhone 17 Pro simulator, iOS 26.5, in light appearance.

| Frame | Task | What it shows |
| --- | --- | --- |
| `ios-comic-menu-chapter-ticks.png` | PB1.4 | The reader menu on Quiet Machines, a comic with three chapter bookmarks. The page slider has a tick at each chapter start. The tick at page 1 is left out, because the thumb covers it. |

This frame comes from the screen recording of the UI test `SweepComicReaderTests/testCaptureComicPageBrowser`, at full resolution. The test itself fails: from a UI test, the Contents tap does not open the carousel. Wave 6b fixes that, then captures the carousel in light and dark, at the largest text size, and on a right-to-left comic, on both platforms (task 3.2).
