# The page beside the shelf — iPad, 2026-09-06

Three frames from `iPad Air 11-inch (M4)` (2360 × 1640 in landscape), taken with
`scripts/capture-ios.mjs --device 6FA19CF5-3287-48A3-96ED-22A713F773B0` and the
`SweepIpadPaneTests` walks, after `scripts/corpus.mjs --simulator <udid>` put the seventeen
generated publications on the device. `publication-detail` §4.1's iPad half.

| Frame | Walk | What it shows |
| --- | --- | --- |
| `ios-ipad-empty-pane.png` | `testCaptureIpadEmptyPane` | The Library split with nothing chosen: the shelf, and the detail column's one sentence |
| `ios-ipad-page-beside-shelf.png` | `testCaptureIpadPageBesideTheShelf` | A cover chosen: *Bright Panels*'s page in the detail column, the shelf where it was |
| `ios-ipad-second-choice.png` | `testCaptureIpadSecondChoiceKeepsTheShelfStill` | A second cover chosen: *Broken Transfer* replaces the page, the shelf has not moved |

## What these are the first proof of

The split landed on 2026-09-05 at 13:05 and **had never opened a page on any device until the
morning these were taken.** Its covers were value links in the leading column and the page was
registered in the detail column, on the documented belief that a link in an earlier column lands
in the detail stack. SwiftUI's log says such a link *cannot be activated*, so for a day a tap on
any cover of the Library shelf did nothing — on the iPhone too, where the collapsed split is the
only shelf there is — while every gate stayed green. `PublicationPaneTests` pinned the
registration's position, not a tap, and these walks, the only ones that would have caught it,
were left owed.

The shelf column now hands its cells `OpenPublicationRoute`, which writes the detail stack's
path, and the frames are what that looks like. The phone's proof is `CurlWalkTests`, which opens
a page from the shelf on its way to the reader.

## Two things to know before comparing them

**The black band.** Each frame carries an unrendered band along one edge: the walk rotates the
iPad to landscape and the simulator's framebuffer had not redrawn that strip when the shutter
fired. It is the capture, not the app — the page's own edge is what is cut, and its title,
author and *Read* action are all inside the rendered part.

**Stored upright.** The simulator writes a rotated device's screenshot sideways; these were
turned so the status bar reads across the top.

## Still owed

Portrait and Split View frames (`testCaptureIpadEmptyPanePortrait` for the first), and whether
the hero art reads as carrying under the floating sidebar, which §4.1 also asks.

## How to retake them

```bash
IPAD=6FA19CF5-3287-48A3-96ED-22A713F773B0
node scripts/capture-ios.mjs --out docs/designs/screenshots/ios-pane-2026-09-06 \
  --only SweepIpadPaneTests/testCaptureIpadEmptyPane --device $IPAD --appearance light   # installs
node scripts/corpus.mjs --simulator $IPAD
for walk in testCaptureIpadPageBesideTheShelf testCaptureIpadSecondChoiceKeepsTheShelfStill testCaptureIpadEmptyPane; do
  node scripts/capture-ios.mjs --out docs/designs/screenshots/ios-pane-2026-09-06 \
    --only SweepIpadPaneTests/$walk --device $IPAD --appearance light
done
```

Each run must report `1 test case(s): 1 passed, 0 failed, 0 skipped`; a first run on a device
without the corpus skips, which is why the corpus goes on after the install.
