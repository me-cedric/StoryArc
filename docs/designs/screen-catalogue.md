# Screen catalogue

The screens that both platforms name the same way, and the test that draws each one.
`lighter-visual-check` decision 4 defines the list. A change that alters one of these screens
records its reference again, looks at the new image in light and dark, and commits both.

A person who adds a screen adds its row here, a snapshot test on each platform, and a step in the
accessibility audit.

## How the tests work

- **iOS snapshots.** `StoryArcSnapshotTests` is a unit-test bundle that the app hosts
  (`apps/ios/project.yml`). Each test draws the real SwiftUI view with fixture data, in light and
  in dark, on an iPhone 17 at scale 2 (402 by 874 points, iOS 26.2). The reference images sit in
  `apps/ios/SnapshotTests/__Snapshots__/<Class>/<number>-<name>.<light|dark>.png`.
  - `pnpm snap:ios` compares each image with its reference. A changed image fails the test.
  - `pnpm snap:ios:record` records every reference again. Run it, open each changed image, and
    fix what is wrong before the commit.
  - The tolerance is 99 per cent of the pixels and 98 per cent perceptual precision. Liquid
    Glass moves its edge by a few hundred pixels from run to run, and that must not fail a test.
  - A reference belongs to one iOS version. Another version fails by a few thousand pixels or by
    a whole bar. Record again on that version.
- **iOS accessibility audit.** `CatalogueAuditTests` in the UI-test target walks the real app to
  each screen that a UI test can reach and runs Apple's `performAccessibilityAudit` over all
  kinds. A control under 44 points, a hit region that the platform names and an element with no
  description fail the test. Contrast, clipped text, Dynamic Type and the other kinds are printed.
  - Apple's hit-region check has a floor near 24 points: it named an 18 point button and passed
    24, 30, 36, 40 and 44 on iOS 26.2. So the suite measures every button, switch, slider, stepper
    and link on the screen against 44 points itself.
  - `testAThirtyPointTargetFails` proves that the measure fails a 30 point target. A debug build
    draws six buttons from 18 to 44 points when it starts with `-storyarc.audit.targets`.
  - Clipped text is printed and does not fail, because the audit cannot tell text that a scroll
    view cuts at its edge from text that a layout clips, and it names no element for most of what
    it finds.
- **Android.** The Android column says "see lighter-visual-check 2.2" until that task fills it.

## The catalogue

| No. | Screen | iOS snapshot test | iOS images (light and dark) | iOS audit | Android |
| --- | --- | --- | --- | --- | --- |
| 01 | Home with content | `LibraryCatalogueTests/testCatalogue01HomeWithContent` | `LibraryCatalogueTests/01-home-with-content` | `testCatalogue01HomeWithContent` | see lighter-visual-check 2.2 |
| 02 | Home on a first run | `LibraryCatalogueTests/testCatalogue02HomeFirstRun` | `LibraryCatalogueTests/02-home-first-run` | `testCatalogue02HomeFirstRun`, on a device with no library | see lighter-visual-check 2.2 |
| 03 | Library grid | `LibraryCatalogueTests/testCatalogue03LibraryGrid` | `LibraryCatalogueTests/03-library-grid` | `testCatalogue03LibraryGridAndRail` | see lighter-visual-check 2.2 |
| 04 | Library list | `LibraryCatalogueTests/testCatalogue04LibraryList` | `LibraryCatalogueTests/04-library-list` | `testCatalogue04LibraryList` | see lighter-visual-check 2.2 |
| 05 | Publication page with a cover | `DetailAndPlayerCatalogueTests/testCatalogue05PublicationWithCover` | `DetailAndPlayerCatalogueTests/05-publication-with-cover` | `testCatalogue05PublicationWithCover` | see lighter-visual-check 2.2 |
| 05b | Publication page, file not on this device | `DetailAndPlayerCatalogueTests/testCatalogue05bPublicationUnavailable` | `DetailAndPlayerCatalogueTests/05b-publication-unavailable` | not reachable: needs an unreachable source | see lighter-visual-check 2.2 |
| 06 | Publication page without a cover | `DetailAndPlayerCatalogueTests/testCatalogue06PublicationWithoutCover` | `DetailAndPlayerCatalogueTests/06-publication-without-cover` | `testCatalogue06PublicationWithoutCover` | see lighter-visual-check 2.2 |
| 07 | Full player | `DetailAndPlayerCatalogueTests/testCatalogue07FullPlayer` | `DetailAndPlayerCatalogueTests/07-full-player` | `testCatalogue07And08Player` | see lighter-visual-check 2.2 |
| 08 | Compact player bar | `DetailAndPlayerCatalogueTests/testCatalogue08CompactPlayerBar` | `DetailAndPlayerCatalogueTests/08-compact-player-bar` | `testCatalogue07And08Player` | see lighter-visual-check 2.2 |
| 09 | Settings root | `SettingsCatalogueTests/testCatalogue09SettingsRoot` | `SettingsCatalogueTests/09-settings-root` | `testCatalogue09To11SettingsAndSources` | see lighter-visual-check 2.2 |
| 10 | Sources list | `SettingsCatalogueTests/testCatalogue10SourcesList` | `SettingsCatalogueTests/10-sources-list` | `testCatalogue09To11SettingsAndSources` | see lighter-visual-check 2.2 |
| 11 | Source detail | `SettingsCatalogueTests/testCatalogue11SourceDetail` | `SettingsCatalogueTests/11-source-detail` | `testCatalogue09To11SettingsAndSources` | see lighter-visual-check 2.2 |
| 12 | The sync section of settings | `SettingsCatalogueTests/testCatalogue12SettingsSync` | `SettingsCatalogueTests/12-settings-sync` | `testCatalogue12SettingsSync` | see lighter-visual-check 2.2 |
| 13 | Downloads and storage | `SettingsCatalogueTests/testCatalogue13DownloadsAndStorage` | `SettingsCatalogueTests/13-downloads-and-storage` | `testCatalogue13Downloads`, which audits the tab and the settings group | see lighter-visual-check 2.2 |
| 14 | Search at rest | `LibraryCatalogueTests/testCatalogue14SearchAtRest` | `LibraryCatalogueTests/14-search-at-rest` | `testCatalogue14SearchAtRest` | see lighter-visual-check 2.2 |
| 15 | Comic or PDF reader chrome | `ReaderCatalogueTests/testCatalogue15ComicReaderChrome` | `ReaderCatalogueTests/15-comic-reader-chrome` | `testCatalogue15ReaderChrome` | see lighter-visual-check 2.2 |
| 16 | Reading themes sheet | `ReaderCatalogueTests/testCatalogue16ThemeSheet` | `ReaderCatalogueTests/16-theme-sheet` | `testCatalogue16ThemeSheet` | see lighter-visual-check 2.2 |
| 17 | Library A to Z rail | `LibraryCatalogueTests/testCatalogue17LibraryAToZRail` | `LibraryCatalogueTests/17-library-a-to-z-rail` | `testCatalogue03LibraryGridAndRail` | see lighter-visual-check 2.2 |

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
- **The largest text size.** The snapshot tests do not draw it. The accessibility audit and the
  review gate in `docs/design.md` section 10 cover it.
