## Context

The owner decided on 2026-10-23 that StoryArc supports foldables, and that the work starts
later. This document records the facts found on that day, the decisions that follow from
them, and what the code already does. A later wave implements `tasks.md` from here.

What exists today:

- Android keeps a comic page off a separating vertical hinge:
  `apps/android/core/designsystem/.../navigation/HingeSlots.kt` reads
  `currentWindowAdaptiveInfoV2().windowPosture.separatingVerticalHingeBounds` from
  `material3-adaptive` 1.3.0 and moves one page to the wider side (`HingeInsetPage`).
  `ReaderPageSurface.kt` applies it. `WindowClass.kt` holds Material's five width classes,
  so a fold is a resize for every screen but the reader.
- iOS reads `horizontalSizeClass` in `CoverGrid.swift`, `LibrarySidebar.swift`,
  `DetailHero.swift` and `HomeHeroMetrics.swift`. The app sets no `UIRequiresFullScreen`,
  so a resized window already reflows (`native-experience`, *Split View, Slide Over and
  multi-window*). `ReaderBrightness.swift` reads `UIScreen.main.brightness`, and
  `OrientationDelegate.swift` locks the reader's orientation.
- The store capture harness (`scripts/store-capture.mjs`) has five buckets: `phone`,
  `tablet7`, `tablet10`, `iphone-6.9`, `ipad-13`. The frames are the six of
  `docs/designs/store/README.md`.

## Facts, checked 2026-10-23

**iPhone Duo (Apple newsroom, 2026-10; Tech Talk 111461 "Prepare your app for iPhone Duo";
App Store Connect screenshot specifications).**

- Ships with the iOS 27.1 SDK and Xcode 27.1. Device Hub in Xcode 27.1 opens, closes,
  folds and rotates a simulated iPhone Duo.
- An app built with an older SDK runs letterboxed on the inner display. Built with the iOS
  27 SDK it extends left of the status bar. Built with the iOS 27.1 SDK it runs edge to edge,
  and standard navigation and toolbar buttons lay out vertically under the status bar.
- Outer display: the size classes of any iPhone. Inner display: regular horizontal and
  regular vertical. The inner display does not honour the app's supported interface
  orientations; Apple's rule is to decide layout from size classes, never from orientation.
- `UIScreen.main` is ambiguous on two displays and will be deprecated. Use
  `traitCollection.displayScale` and `window?.windowScene?.screen`.
- Safe areas are asymmetric: vertical bars can sit on the left in landscape and in Split
  View. Read each inset on its own.
- New in iOS 27.1: `ReservedRegion` (SwiftUI) and `UIViewReservedRegion` (UIKit) for the
  fold (`.division`) and the camera (`.occlusion`); an arrangement container that splits a
  layout across the fold (Assumed name `ArrangementView`, from a secondary source); a hinge
  API that reports the angle (Assumed name `onHingeChange`, secondary source). Standard
  `NavigationSplitView`, `TabView`, `List`, `ScrollView`, sheets, popovers and alerts adapt
  on their own. `TabView` takes `.defaultTabBarPlacement(.sidebar)` on the inner display.
- App Store screenshot slots for iPhone Duo: outer 1398 x 2034 (portrait) and 2034 x 1398
  (landscape); inner 2007 x 2853 (portrait) and 2853 x 2007 (landscape). Optional today;
  **required from April 2027 for any app built with the iOS 27.1 SDK or later.**
  Optimised apps carry a "Made for iPhone Duo" badge on the product page.

**Android (developer.android.com, large screen and foldable guides, read 2026-10-23).**

- Posture comes from Jetpack WindowManager `FoldingFeature` through `WindowInfoTracker`:
  state `FLAT` or `HALF_OPENED`, orientation, `isSeparating`, `occlusionType`, `bounds`.
  `material3-adaptive` wraps it as `windowPosture` (already used in `HingeSlots.kt`).
- The quality guidelines grade posture support as Tier 1 (`Foldables_Postures`) and a
  camera preview on both displays (`Foldables_Camera`, not relevant here). The recommended
  test profile for a foldable is 841 x 701 dp; the emulator profile is Phone > Pixel Fold.
- Play has no foldable screenshot slot. Foldable frames go in the large screen slots
  (16:9 or 9:16, 1080 to 7680 px, at least four frames to be featured).

## Decisions

### D1. Size classes decide, on both platforms

iOS layouts read `horizontalSizeClass` and `verticalSizeClass`; no layout reads the
orientation or the idiom. Android layouts read `WindowClass` (the five Material widths) and
the posture. The reader's orientation lock (`OrientationDelegate.swift`) stays for the outer
display and is a no-op on the inner one, which is what the platform does.

### D2. The fold is a reserved region, never a split of the layout

A single page is one surface moved to the wider side of the fold, the rule `HingeSlots.kt`
holds. iOS gets the same arithmetic over `ReservedRegion` of kind `.division`. The
arrangement container is used only for the two states that put two things on two halves:
the spread (one page per half) and tabletop (page above, controls below). No other screen
uses it.

### D3. Tabletop puts the page on the upright half

At `HALF_OPENED` with a horizontal fold, the page surface is the upper half and the chrome
(slider, page carousel, menu) the lower half. The reader's auto-hide stays off while the
posture lasts, because the lower half is a control surface and not a page. Accessibility:
VoiceOver and TalkBack keep one reading order, page first and controls second.

### D4. Book posture is the spread the comic reader has

At `HALF_OPENED` with a vertical fold, `comic-reader`'s double-page spread is forced on and
its gutter is placed on the fold. Right-to-left keeps its order. A paged EPUB takes the same
two columns. The curl transition is withheld in book posture: a curl across a hinge draws a
crease the shader cannot model (`page-transitions`, *A device that cannot curl*).

### D5. The hand-over keeps the state in the model, not the view

A fold event is a size change. The reader's position, the open sheet and the playing voice
already live outside the view tree (`ReaderSession` on iOS, the reader view model on
Android), so no new persistence is added. A test on each platform resizes a reader from the
outer to the inner size and back and asserts the page, the sheet and the voice are kept.

### D6. `UIScreen.main` leaves the iOS code

`ReaderBrightness.swift` moves to the scene's screen through the window. The UI tests keep
`XCUIScreen.main`, which is a test API.

### D7. Store captures get two buckets

`duo` on iOS: the `iPhone Duo` simulator, outer and inner display, portrait, six frames,
four languages, written to the App Store layout at 1398 x 2034 and 2007 x 2853. `fold` on
Android: the Pixel Fold profile at 841 x 701 dp open and the outer size closed, six frames,
written to the Play large screen slot. The walk of `store-walk.mjs` is reused; a frame on the
open display shows the wide layout the `tablet10` and `ipad-13` buckets already show.

### D8. Build with the iOS 27.1 SDK before April 2027

The release train pins Xcode on CI. The pin moves to Xcode 27.1 in the first wave of this
change, and `pnpm release:check` fails after 2027-03-01 if the pin is older. That is the one
date in this change with a cost outside the app.

## Accessibility

- A reader who cannot see the fold must not be surprised by a control that moved: the
  tabletop state announces "Controls below" once when it starts (VoiceOver, TalkBack).
- The 44 pt and 48 dp floors hold on the outer display, which is narrower than a phone.
- At the largest text size the tabletop control half scrolls; nothing is cut off.

## Risks

- The iPhone Duo arrangement and hinge API names are from secondary sources until the
  Apple documentation is read (Assumed, marked above).
- No foldable device is in the owner's device list. The Pixel Fold emulator profile and the
  iPhone Duo simulator are the proof; the device checklist gains two owner steps.
- A spread forced in book posture changes the page count the slider shows; the comic reader
  already handles a spread's numbering.

## Open Questions

1. Does the owner want the Flip form factor (a tall outer display, a square half-open
   posture) treated as a phone with tabletop, or excluded? The plan assumes tabletop only.
2. Should the "Made for iPhone Duo" badge be sought in the first wave, or after a Duo is
   in hand? The plan assumes the badge waits for a device.
