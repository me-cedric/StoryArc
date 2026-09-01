# The cover grid — the matrix iOS had never had

Taken on the booted `StoryArc-iPhone17Pro` simulator by `ScreenshotTests`, from the debug app
built at the commit these are committed with.

| Picture | Appearance | Text size | Position |
| --- | --- | --- | --- |
| `ios-library.png` | light | default | top |
| `ios-library-dark.png` | dark | default | top |
| `ios-library-ax5.png` | light | `AccessibilityXXXL` | top |
| `ios-library-ax5-dark.png` | dark | `AccessibilityXXXL` | top |
| `ios-library-end.png` | light | default | scrolled to the end |
| `ios-library-end-dark.png` | dark | default | scrolled to the end |

## Why these exist at all

**Android has held a four-cell matrix for the cover grid since it was written; iOS held one
picture.** Not because anybody decided iOS needed less, but because
`capture-android.mjs` has taken `--dark` and `--font-scale` since day one and always put the
device back, and `capture-ios.mjs` had neither — it ran a walk and photographed whatever
appearance the simulator happened to be in. Every iOS dark capture in this repository was taken
by a person flipping the simulator by hand, and two runs of the same walk overwrote each other
because the filename carried no appearance.

`--appearance light|dark` landed on 2026-09-01, and these are the first four cells it made
takeable. `docs/designs/ui-revamp-2026-08.md` §7.5 records the asymmetry.

## The two end-of-scroll shots, and the defect that turned out not to be one

`ui-revamp-2026-08.md` §7.5 recorded, on 2026-08-30: *"Cover titles render behind that pill …
The grid has no bottom safe-area inset for the floating bar. That is a live layout defect, not a
taste question."* It stood for three days.

The four top-of-shelf captures above appear to confirm it — the third row's captions sit under
the tab bar, and at `AccessibilityXXXL` a caption is clipped at the screen edge. **They do not
confirm it, and reading them as confirmation was wrong.** Content passing *under* Liquid Glass
while it scrolls is what the material is for. The only thing that would be a defect is a last
row that can never be scrolled clear, and **a screenshot taken at the top of a shelf cannot tell
those two apart** — which is exactly why the bullet survived: every capture of the library in
this repository was taken at rest.

`ios-library-end{,-dark}.png` are the pictures that answer it. The last row — *Tidal Reach #2*
and *Tidal Reach #3* — clears the bar with room to spare, and the bar has minimised to a single
pill, which is `tabBarMinimizeBehavior(.onScrollDown)` doing its job. There is nothing to fix.

**A fix was written first, and reverted.** `CoverGrid`'s `ScrollView` was given a
`contentMargins(.bottom,)` fed from `safeAreaInsets.bottom`. The re-capture came back
*byte-identical*, which said the inset it read was **zero** — and only then was the right
question asked. The observation that started all this was made when a floating **search pill**
hovered over a shelf with no tab bar for the content to inset against; the shell has changed
underneath it since.

`ScreenshotTests.testCaptureLibraryAtTheEnd` is kept rather than deleted with the investigation.
It is the only walk that can fail if a future change does break the inset, and it swipes rather
than asking XCUITest to scroll an element into view — asking the framework to reveal the cell
whose visibility is in question would be asking it the thing being measured.

## What these do not prove

- **The iPad.** These are an iPhone 17 Pro. `after-2026-08-30/` holds the iPad set, and every
  one of its sixteen shots is portrait; a landscape pass per destination is still owed there.
- **A shelf longer than the fixture library.** Ten publications is two and a bit screens. A
  reader with four hundred is a different scroll and a different memory profile, and neither is
  measured anywhere in this repository.
