# The iPad's hero exists — 2026-09-04

Two of the September sweep's findings, checked and **not confirmed**. Both were read off
`ios-ipad-home.png` in [`../ios-sweep-2026-09-02/`](../ios-sweep-2026-09-02/README.md), and
both are artefacts of what that frame is rather than properties of the app.

Device: `iPad Pro 11-inch (M5)`, iOS 26.5, udid `0489EB53` — the simulator the sweep used,
with the same corpus.

## "Home has no hero on an iPad"

**The device had nothing part-read.** `HomeScreen` draws the hero when
`model.continueReading` is non-empty, and on nothing else — there is no size class, no window
width and no idiom anywhere in that decision. Reading positions live in a per-device SwiftData
store that no launch argument reaches, so the phone, which had been read on across four months
of walks, had a hero and this iPad, whose corpus was copied in on 2026-09-02, did not.

| File | What it shows |
| --- | --- |
| `ios-ipad-home.png` | The sweep's state reproduced: nothing in progress, so *Recently added* is first. |
| `ios-ipad-home-in-progress.png` | The same walk after reading one page. **Continue reading**, with the hero. |
| `ios-ipad-home-in-progress-portrait.png` | The same state, photographed with `xcrun simctl io screenshot` rather than `XCUIScreenshot` — so it is upright, uncropped, and the clearest of the three. |

`SweepIpadTests.testCaptureIpadHomeInProgress` is the walk, and it is kept rather than run
once and deleted: it is the only iPad walk that photographs the hero at all.

**This is the second time this reading has been made here.** `one-library-three-destinations`
task 0b.5 already records it against Android: "The review reported it missing because the
device had nothing in progress. Do not build a second one." No 0b task is answered or
contradicted by this; nothing was built.

Getting the frame took three attempts and both failures are worth keeping:

- Two swipes finished the comic, and `home-screen` removes a finished publication from Keep
  reading **by design** — so Home came back with a *Finished* shelf and still no hero, which
  would have read as the finding confirmed.
- The corpus's comics are 3 to 12 pages. `Foreign Codec` is 3 and one swipe finished it too.
  The walk now reads a `Tidal Reach` issue, which is 8.

## "A horizontal shelf on an iPad stretches its covers"

**The frame is rotated, not the covers.** `XCUIScreenshot` returns the device's own canvas,
which stays portrait while the interface is landscape. The sweep's README notices half of this
— it says the frames are letterboxed and to crop them — but the transposition is the other
half, and it swaps exactly the axis the finding is about: a portrait 2:3 cell in a landscape
window appears in the raw PNG as a landscape cell.

`ios-ipad-home-in-progress-portrait.png` settles it with no rotation to argue about. The
*Recently added* cells there are plainly taller than wide, and they are the same cells: the
Home shelf card is `.frame(width: width, height: width * 3 / 2)` in `LibraryFeature/HomeRow.swift`
— a literal 2:3 with no device branch — at the 158 pt tier a wide window takes.

The letterbox-not-crop rule `design.md` asks for is also being kept, in
`LibraryFeature/HomeArtwork.swift`: the art is drawn `.scaledToFit()` over `surfaceSunken`,
which is the letterbox. It is invisible on this corpus because the generated covers are
already 2:3, so a fitted cover fills its frame exactly and leaves no well to see.

## One thing this did surface

On the iPad the hero fills the visible column, and whether the next section's heading clears
the fold could not be read off either landscape frame, because both are cropped by the canvas
artefact above. `one-library-three-destinations` task 0b.4 asks for that heading to be visible
without scrolling **on a phone at the default text size** and says nothing about a tablet, so
this is an observation and not a defect against anything written down. It wants a look on a
real iPad before anybody changes a number.
