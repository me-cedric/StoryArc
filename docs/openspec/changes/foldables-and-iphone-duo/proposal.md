## Why

Two foldable form factors reach readers in 2026 that StoryArc has not planned for. Apple
ships iPhone Duo with the iOS 27.1 SDK: an outer display shaped like a phone and an inner
display that is regular in both size classes, with a fold, an under-display camera and
Split View on a phone. Android foldables (Pixel Fold line, Galaxy Z Fold and Flip lines,
OnePlus Open) have been on sale for years, and Google's large screen quality guidelines
grade an app on its posture support.

A comic reader is the app a foldable is bought for: a page across the open inner display,
a spread across two halves, a book held like a book at half-open. The contract already
holds one Android foldable scenario (`native-experience`, *Foldables*) and the Android app
already keeps a page off a separating hinge. Nothing names iPhone Duo, the outer-to-inner
hand-over, the half-open postures, or the store assets each store now asks for.

**Built on 2026-10-24.** The owner decided on 2026-10-23 that foldables are supported later,
and on 2026-10-24 told us to build them. What stays open needs a person: Xcode's Device Hub
to open the simulated iPhone Duo, and a foldable device in hand (`tasks.md`). A Duo
screenshot set is required for every app built with the iOS 27.1 SDK from April 2027.

## What Changes

- **Both platforms: a continuous hand-over between the folded and the open display.** The
  reader keeps the page, the position and the open sheet when the device opens or closes.
- **Both platforms: the reader respects the fold.** A single page stays whole on one side
  of a separating hinge; a spread puts its gutter on the fold; the comic reader never puts a
  page's focal area under the fold or the camera.
- **Both platforms: half-open postures.** At half-open on a table, the page stays on the
  upright half and the controls move to the flat half. Held like a book, the two halves are
  the two pages of a spread.
- **iOS: iPhone Duo.** Size classes decide every layout. The inner display takes the
  sidebar layout the iPad already has. Split View on the inner display is a resize the app
  already supports. The app is built with the iOS 27.1 SDK before April 2027.
- **Android: the posture scenario gains the outer display and the hand-over.** The existing
  *Foldables* scenario stays; new scenarios cover what it leaves out.
- **Store listings.** The App Store gains the iPhone Duo screenshot slots (outer and inner
  display) in the four languages. Play gains a foldable set in the large screen slots. The
  capture harness gains a `duo` bucket on iOS and a `fold` bucket on Android.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `native-experience`: the *Adaptive layout* requirement gains the foldable scenarios on
  both platforms. The *Visual proof of interface changes* requirement gains the foldable
  postures as states that a screen catalogue entry must show.

## Platforms

Both. iOS: iPhone Duo. Android: Pixel Fold, Galaxy Z Fold and Z Flip, and the resizable
emulator's foldable profiles. The desktop clients are not affected.

## Non-goals

- No rear-display or dual-screen mode (content on both displays at once). Scene
  accessories on iPhone Duo and Android's rear display mode are camera features.
- No new reading mode. A spread on a book-posture foldable is the existing double-page
  spread of `comic-reader`, placed on the fold.
- No Samsung Flex mode panel integration beyond the platform's own posture report.
- No tent posture. A tented device shows the same layout as a flat one.

## Impact

- `apps/ios`: `project.yml` (SDK and the `iPhone Duo` simulator in the capture scripts),
  the reader chrome and the page surface in `ReaderFeature`, the capture suite in `UITests`.
- `apps/android`: `core/designsystem` (the hinge arithmetic exists in `HingeSlots.kt`), the
  reader and the player screens, the catalogue snapshot tests.
- `scripts/store-capture.mjs`, `scripts/store-walk.mjs` and `docs/designs/store/README.md`:
  two new buckets and the Duo slot sizes.
- `docs/designs/screen-catalogue.md`: the posture column.
