# Screen catalogue

The screens that both platforms name the same way, and the test that draws each one.
`lighter-visual-check` decision 4 defines the list. A change that alters one of these screens
records its reference again, looks at the new images in light, in dark and (on iOS) at the
largest text size, and commits them.

A person who adds a screen adds its row here, a snapshot test on each platform, and a step in the
accessibility audit.

## How the tests work

- **iOS snapshots.** `StoryArcSnapshotTests` is a unit-test bundle that the app hosts
  (`apps/ios/project.yml`). Each test draws the real SwiftUI view with fixture data, in light and
  in dark, on an iPhone 17 at scale 2 (402 by 874 points, iOS 26.2). It also draws the light
  appearance at the largest text size, AX5 (`accessibilityExtraExtraExtraLarge`). The reference
  images sit in `apps/ios/SnapshotTests/__Snapshots__/<Class>/<number>-<name>.<light|dark|largest>.png`.
  An image shows the first screen only. Text below the fold is not in it.
  - `pnpm snap:ios` compares each image with its reference. A changed image fails the test.
  - `pnpm snap:ios:record` records every reference again. Run it, open each changed image, and
    fix what is wrong before the commit.
  - The tolerance is 99 per cent of the pixels and 98 per cent perceptual precision. Liquid
    Glass moves its edge by a few hundred pixels from run to run, and that must not fail a test.
  - Entry 08 allows 16 per cent of its pixels to differ, because the tab bar and the accessory
    are two glass lenses that move a few levels of colour from run to run. Those two bars are a
    device screenshot case.
  - Entry 01 allows 2 per cent, because the glass edge of the two Resume capsules draws in one of
    two ways from run to run, and the two differ in 1.3 per cent of the pixels.
  - A reference belongs to one iOS version. Another version fails by a few thousand pixels or by
    a whole bar. Record again on that version.
- **iOS accessibility audit.** `CatalogueAuditTests` in the UI-test target walks the real app to
  each screen that a UI test can reach and runs Apple's `performAccessibilityAudit` over all
  kinds. A control under 44 points, a hit region that the platform names, an element with no
  description and a contrast finding on an element that the audit names fail the test. Clipped
  text, Dynamic Type and the other kinds are printed.
  - A contrast finding is printed and does not fail when it names no element, or when its element
    is cut by the window or covered by a tab bar, a toolbar or a navigation bar.
  - A contrast fault that stands for now is in `knownContrastFaults`
    (`apps/ios/UITests/CatalogueVerdict.swift`), with its reason. A steady entry that no longer
    occurs fails the test, so the list drains. `testFaintTextFails` proves that the gate fails a
    faint label, which the debug argument `-storyarc.audit.targets` draws.
  - `pnpm test:ios:audit` runs the class on a local simulator: build, install and seed, the
    corpus, then the tests. The iOS workflow runs the same class in its step *Catalogue audit*,
    after the other UI tests. Entry 02 is skipped in both, because the seed gives the device a
    library.
  - Apple's hit-region check has a floor near 24 points: it named an 18 point button and passed
    24, 30, 36, 40 and 44 on iOS 26.2. So the suite measures every button, switch, slider, stepper
    and link on the screen against 44 points itself.
  - `testAThirtyPointTargetFails` proves that the measure fails a 30 point target. A debug build
    draws six buttons from 18 to 44 points when it starts with `-storyarc.audit.targets`.
  - Clipped text is printed and does not fail, because the audit cannot tell text that a scroll
    view cuts at its edge from text that a layout clips, and it names no element for most of what
    it finds.
- **Android snapshots.** Each screen module has a Robolectric test `Catalogue<number><Name>Test`
  that draws the real Compose screen with fixture data through `catalogue()` in `:core:snapshots`,
  in light and in dark, at `w411dp-h891dp-xhdpi` (822 by 1782 pixels). Roborazzi writes the
  reference images to `src/test/snapshots/<number>-<name>-<light|dark>.png` in that module.
  - `pnpm snap:android` compares each image with its reference. A changed image fails the test.
    `pnpm test:android` also compares them. A plain `./gradlew test`, as the Linux CI runs it,
    does not compare them, because the references are recorded on macOS.
  - `pnpm snap:android:record` records every reference again. Open each changed image before the
    commit.
  - The same call runs the accessibility checks of `:core:snapshots` on each screen: touch
    targets, contrast and labels. A fault that stands for now is a `KnownFault` with its reason.

## The catalogue

| No. | Screen | iOS snapshot test | iOS images (light and dark) | iOS at the largest text size, `.largest.png` (2026-10-10) | iOS audit | Android |
| --- | --- | --- | --- | --- | --- | --- |
| 01 | Home with content | `LibraryCatalogueTests/testCatalogue01HomeWithContent` | `LibraryCatalogueTests/01-home-with-content` | No fault. The Home card stops growing at AX1 | `testCatalogue01HomeWithContent` | `:feature:library` `Catalogue01HomeWithContentTest`, `01-home-with-content` |
| 02 | Home on a first run | `LibraryCatalogueTests/testCatalogue02HomeFirstRun` | `LibraryCatalogueTests/02-home-first-run` | No fault | `testCatalogue02HomeFirstRun`, on a device with no library | `:feature:library` `Catalogue02HomeFirstRunTest`, `02-home-first-run` |
| 03 | Library grid | `LibraryCatalogueTests/testCatalogue03LibraryGrid` | `LibraryCatalogueTests/03-library-grid` | No fault since titles wrap. The grid is a list at this size | `testCatalogue03LibraryGridAndRail` | `:feature:library` `Catalogue03LibraryGridTest`, `03-library-grid` |
| 04 | Library list | `LibraryCatalogueTests/testCatalogue04LibraryList` | `LibraryCatalogueTests/04-library-list` | No fault since titles wrap | `testCatalogue04LibraryList` | `:feature:library` `Catalogue04LibraryListTest`, `04-library-list` |
| 05 | Publication page with a cover | `DetailAndPlayerCatalogueTests/testCatalogue05PublicationWithCover` | `DetailAndPlayerCatalogueTests/05-publication-with-cover` | No fault | `testCatalogue05PublicationWithCover` | `:feature:library` `Catalogue05PublicationWithCoverTest`, `05-publication-with-cover` |
| 05b | Publication page, file not on this device | `DetailAndPlayerCatalogueTests/testCatalogue05bPublicationUnavailable` | `DetailAndPlayerCatalogueTests/05b-publication-unavailable` | No fault on the first screen | not reachable: needs an unreachable source | none |
| 06 | Publication page without a cover | `DetailAndPlayerCatalogueTests/testCatalogue06PublicationWithoutCover` | `DetailAndPlayerCatalogueTests/06-publication-without-cover` | No fault | `testCatalogue06PublicationWithoutCover` | `:feature:library` `Catalogue06PublicationWithoutCoverTest`, `06-publication-without-cover` |
| 07 | Full player | `DetailAndPlayerCatalogueTests/testCatalogue07FullPlayer` | `DetailAndPlayerCatalogueTests/07-full-player` | No fault | `testCatalogue07And08Player` | `:app` `Catalogue07FullPlayerTest`, `07-full-player` |
| 08 | Compact player bar | `DetailAndPlayerCatalogueTests/testCatalogue08CompactPlayerBar` | `DetailAndPlayerCatalogueTests/08-compact-player-bar` | Fault: the bar cuts the title to one line | `testCatalogue07And08Player` | `:app` `Catalogue08CompactPlayerBarTest`, `08-compact-player-bar` |
| 09 | Settings root | `SettingsCatalogueTests/testCatalogue09SettingsRoot` | `SettingsCatalogueTests/09-settings-root` | No fault | `testCatalogue09To11SettingsAndSources` | `:feature:settings` `Catalogue09SettingsRootTest`, `09-settings-root` |
| 10 | Sources list | `SettingsCatalogueTests/testCatalogue10SourcesList` | `SettingsCatalogueTests/10-sources-list` | No fault since the status goes under the name | `testCatalogue09To11SettingsAndSources` | `:feature:settings` `Catalogue10SourcesListTest`, `10-sources-list` |
| 11 | Source detail | `SettingsCatalogueTests/testCatalogue11SourceDetail` | `SettingsCatalogueTests/11-source-detail` | No fault | `testCatalogue09To11SettingsAndSources` | `:feature:settings` `Catalogue11SourceDetailTest`, `11-source-detail` |
| 12 | The sync section of settings | `SettingsCatalogueTests/testCatalogue12SettingsSync` | `SettingsCatalogueTests/12-settings-sync` | No fault | `testCatalogue12SettingsSync` | `:feature:settings` `Catalogue12SyncSectionTest`, `12-sync-section` |
| 13 | Downloads and storage | `SettingsCatalogueTests/testCatalogue13DownloadsAndStorage` | `SettingsCatalogueTests/13-downloads-and-storage` | Fault: the large title ends in an ellipsis. The system draws the bar | `testCatalogue13Downloads`, which audits the tab and the settings group | `:app` `Catalogue13DownloadsTest`, `13-downloads` |
| 14 | Search at rest | `LibraryCatalogueTests/testCatalogue14SearchAtRest` | `LibraryCatalogueTests/14-search-at-rest` | Fault: the titles under the covers end in an ellipsis after two lines | `testCatalogue14SearchAtRest` | `:feature:library` `Catalogue14SearchAtRestTest`, `14-search-at-rest` |
| 15 | Comic or PDF reader chrome | `ReaderCatalogueTests/testCatalogue15ComicReaderChrome` | `ReaderCatalogueTests/15-comic-reader-chrome` | No fault | `testCatalogue15ReaderChrome` | `:feature:reader` `Catalogue15ReaderChromeTest`, `15-reader-chrome`. The comic reader only |
| 16 | Reading themes sheet | `ReaderCatalogueTests/testCatalogue16ThemeSheet` | `ReaderCatalogueTests/16-theme-sheet` | No fault | `testCatalogue16ThemeSheet` | `:feature:epubreader` `Catalogue16ThemeSheetTest`, `16-theme-sheet`. The preview box is empty, because Robolectric does not draw a web view |
| 17 | Library A to Z rail | `LibraryCatalogueTests/testCatalogue17LibraryAToZRail` | `LibraryCatalogueTests/17-library-a-to-z-rail` | No fault since titles wrap | `testCatalogue03LibraryGridAndRail` | `:feature:library` `Catalogue17LibraryRailTest`, `17-library-a-to-z-rail` |
| 18 | Library with the skipped notice | `LibraryCatalogueTests/testCatalogue18LibrarySkippedNotice` | `LibraryCatalogueTests/18-library-skipped-notice` | No fault since the notice wraps. It fills most of the first screen | `testCatalogue18LibrarySkippedNotice`, on a device whose scan skipped a file | none yet. Android keeps its Material notice, and its snapshot is owed to the Android lane |

Entry 05b is not in the first list of the change. It holds a fault that the snapshots found, and
its test keeps that fault from coming back.

## What a snapshot cannot show

A screen in this list can still need one device screenshot, taken from a booted simulator, for the
parts that a snapshot does not draw. Take one for each appearance, and shrink it with
`pnpm frames:shrink`.

- **The tab bar and navigation between screens.** Entry 08 draws the tab bar in a `TabView`, but
  the shell's real tab bar, the sidebar on an iPad and the transitions need the running app.
- **The Downloads tab.** `DownloadsDestination` lives in the app target and reads the live
  download store, so its content depends on the device. Entry 13 draws *Downloads and storage* in
  settings instead. `CatalogueAuditTests` audits the tab on a seeded device.
- **The content of a web view.** The reflowable reader draws a page in a web view. Entry 16 draws
  the theme sheet, which has no web view; the page behind it is a device screenshot case.
- **System interface.** The status bar and the Dynamic Island, the keyboard, share sheets, file
  and folder pickers, the lock screen, widgets and CarPlay.
- **The largest text size on Android.** The Android catalogue tests do not set `fontScale` yet
  (`lighter-visual-check` task 5.2). On iOS the snapshot tests draw it.
