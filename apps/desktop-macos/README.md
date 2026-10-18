# StoryArc for macOS

**Status: wave 4, EPUB, PDF text, audio and speech.** The library window opens on Home (Keep
reading, Up next), lists the chosen folders' publications as a grid or a list over
`StoryArcKit`'s `LibraryModel`, with search, filters, sorting and a publication page. Each
publication reads in its own window with keys, the edge click zones, zoom and pan, spreads
by window shape and a sliding drag; positions are written on every turn and before a
window closes or the app quits. Files open from Finder, a drop and the Dock menu; folders
keep their bookmarks and are watched with FSEvents. The preferences have a search, the
accent choice and the app's own text size. Wave 3 added the server sources, downloads, sync,
storage and shelves. Wave 4 adds a reflowable EPUB in a `WKWebView` over the pinned Readium
bundle, with the manifest and positions built in Swift and every way out of the page denied;
a PDF's text layer over PDFKit (selection, marks, search, the outline); an audiobook player on
the one `PlayerCentre` with the media keys and the Now Playing panel; and read-aloud over
`AVSpeechSynthesizer`, absent where the Mac has no voice. [ADR-0018](../../docs/decisions/0018-desktop-clients.md) supersedes the
timing in [ADR-0004](../../docs/decisions/0004-desktop-strategy.md).

- Plan: [`docs/openspec/changes/desktop-clients`](../../docs/openspec/changes/desktop-clients)
- Design: [`docs/designs/desktop/macos.md`](../../docs/designs/desktop/macos.md)
- Research: [`desktop-research-linux-macos-2026-10-07.md`](../../docs/delivery/desktop-research-linux-macos-2026-10-07.md)
  and [`desktop-parity-2026-10-07.md`](../../docs/delivery/desktop-parity-2026-10-07.md)

## Stack

| Part | Choice |
| --- | --- |
| Language and UI | Swift 6, SwiftUI. AppKit only where SwiftUI has no desktop control. |
| Floor | macOS 26. It matches `StoryArcKit`'s `.macOS(.v26)`. |
| Project | Its own XcodeGen project: `project.yml` makes `StoryArcMac.xcodeproj`. Scheme `StoryArc`. |
| Shared code | `apps/ios/Packages/StoryArcKit`, consumed by path. Wave 2 links `DesignSystem`, `StoryArcCore`, `LibraryFeature`, `Persistence`, `Formats` and `ReaderFeature`. Each wave adds the products it needs. |
| Bundle id | `com.mecedric.storyarc` |
| Sandbox | App Sandbox on. Entitlements: `app-sandbox`, `files.user-selected.read-write`, `files.bookmarks.app-scope`, `network.client`, and no other — `Tests/EntitlementsTests.swift` pins the set. No keychain access group: an ad-hoc build cannot use the data-protection keychain (`Tests/KeychainSpike.md`), so secrets go to the login keychain until the signed build of task 6.8. |
| EPUB | `WKWebView` with the pinned Readium ts-toolkit renderer (`apps/desktop-web/epub/dist`, copied into the app). Readium swift-toolkit is iOS only and cannot serve macOS. The host serves the archive on the `storyarc-epub` scheme, denies every other load with a content rule list and a Content-Security-Policy header, and builds the manifest and the positions in Swift from `Formats` (design.md Open Question 6). |
| PDF | PDFKit, through `StoryArcKit`'s `PdfDocumentReader`; the text model, the overlay and the pasteboard are the Mac's own. |
| Audio and speech | `Playback`'s `PlayerCentre` and `NarratedSource`; Now Playing and the media keys through `MediaPlayer` in the Mac target; read-aloud over `AVSpeechSynthesizer` with the Mac's own sentence source. |
| Not used | Mac Catalyst. It gives an iPad app in a window. |

`apps/ios/project.yml` and `apps/ios/App` stay untouched. The Mac shell has its
own source folder.

## Folder layout

```
apps/desktop-macos/
├── project.yml                 XcodeGen spec; StoryArcMac.xcodeproj and App/Info.plist are generated
├── App/
│   ├── StoryArcMacApp.swift    the @main entry: the library Window, the reader WindowGroup(for:), Settings
│   ├── LibraryWindow.swift     sidebar, content column, toolbar search, drops, navigation requests
│   ├── MacChrome.swift         theme, accent, appearance, language, and the scaled text size
│   ├── SettingsRoot.swift      the six preferences tabs and the preferences search
│   ├── DestinationEmptyState.swift, MacFolderBookmarks.swift, MacCredentialStore.swift   wave 1
│   ├── Library/                MacLibrary (the composition root), Home, grid and list, detail,
│   │                           search state, selection, folder source states, toolbar menus
│   ├── Reader/                 the reader window and its Mac page view, chrome, key mapper,
│   │                           click zones, zoom model, spreads, drag turn, progress writer,
│   │                           reader targets and restoration, the window registry, and
│   │                           ReaderRoot, which picks the reader by format
│   ├── Epub/                   the EPUB host: the scheme handler and the egress rules, the
│   │                           manifest and positions builder, the archive source and host
│   │                           page, the model over the web view, the window and its chrome
│   ├── Pdf/                    the PDF text layer: the Mac text model over PdfDocumentReader,
│   │                           the page geometry, the overlay, the selection menu and search
│   ├── Player/                 the player window, the Now Playing and media keys copy, and
│   │                           the wiring of the one PlayerCentre
│   ├── Speech/                 read-aloud: the voice catalogue, the sentence splitter, the
│   │                           spoken chapters and the spoken source over AVSpeech
│   ├── Settings/               MacSettings (the preferences model), the tabs, the search index,
│   │                           the Sources and sync sections, storage, the diagnostic export
│   ├── Sources/                MacSources: share, catalogue and Kavita sheets, Bonjour, the rows
│   ├── Downloads/              MacDownloads, the Downloads page, the metered rule, catalogue rows
│   ├── Sync/                   MacSync (sync at start and quit) and its runner wiring
│   ├── Shelves/                collections and reading lists: the model's Mac reading, the menus,
│   │                           the shelf page, Home's shelves, bulk marks with undo and downloads
│   ├── System/                 the app delegate (files, Dock menu, quit), the command table and
│   │                           menus, FSEvents watching, files handed over, the power assertion
│   ├── StoryArcMac.entitlements
│   └── Localizable.xcstrings   en, fr, de, es
├── Tests/                      StoryArcMacTests, hosted in the app
│   ├── *Tests.swift            one suite per rule: window model, commands, keys, pointer, zoom,
│   │                           spreads, drag, progress writer, display awake, folders, watcher,
│   │                           files, search, settings search, Home, detail, accent, localisation
│   ├── WindowWalk.swift        the serialized parent of every suite that drives windows
│   ├── ReaderWalkTests.swift, PointerAndFilesWalkTests.swift, ShellTests.swift   the walks
│   ├── EpubEgressTests.swift, EpubWalkTests.swift, PdfWalkTests.swift, PlayerWalkTests.swift   wave 4
│   ├── CaptureTests.swift, Wave2CaptureTests.swift, Wave3CaptureTests.swift, Wave4CaptureTests.swift
│   ├── MockServers.swift       where the walks find the OPDS, Kavita, SMB and egress mocks
│   ├── ConformanceLog.swift    what the wave 3 walks measured, for the conformance record
│   ├── MacCatalogue.swift      the screen catalogue: each screen brought up over the fixtures
│   ├── AccessibilityAudit.swift, AccessibilityAuditTests.swift   every catalogue control
│   │                           named and at least 20 × 20 points, as VoiceOver reads it
│   ├── MacSnapshot.swift, SnapshotTests.swift   every catalogue screen held against a reference
│   ├── __Snapshots__/          the references, light, dark and largest, and the macOS version
│   ├── TestFixtures.swift      fixtures and the entitlements file, read from the test bundle
│   └── KeychainSpike.md        the spike's result, 2026-10-16
└── README.md
```

The library window's minimum is 640 × 440 points. Below about 600 the system
collapses the sidebar into its toggle.

## Build and run

```bash
pnpm build:macos      # xcodegen generate, then xcodebuild build, scheme StoryArc
cd apps/desktop-macos && xcodebuild test -project StoryArcMac.xcodeproj -scheme StoryArc -destination 'platform=macOS'
```

The tests are hosted in the app, so they run inside the ad-hoc signed, sandboxed
process: the entitlement, bookmark and keychain tests measure a local run, not an
`xctest` runner. The test bundle carries `packages/test-fixtures/comics` and the
entitlements file as resources; a test in the sandboxed app that opens a path under
`~/Documents` waits on a privacy prompt and the run hangs. The walks copy the comics into
the container and read them as the app's library, so a run needs no setup. Suites that
open windows run one after another under `WindowWalks`. `TEST_RUNNER_STORYARC_CAPTURE=1` in front of the test command also
writes the window frames into the container's `tmp/captures/`; see
[`wave1/`](../../docs/designs/screenshots/desktop/macos/wave1/README.md),
[`wave2/`](../../docs/designs/screenshots/desktop/macos/wave2/README.md) and
[`wave3/`](../../docs/designs/screenshots/desktop/macos/wave3/README.md)
for how and for what they do and do not show.

The source, download and sync walks need the repository's mock servers (`pnpm opds`,
`pnpm kavita`, `pnpm smb`, and `scripts/smb-server.sh --encrypted`); a walk whose server is
not listening is skipped and says so. Ports and the share's user move with
`TEST_RUNNER_STORYARC_OPDS_PORT`, `_KAVITA_PORT`, `_SMB_PORT`, `_SMB_ENCRYPTED_PORT` and
`_SMB_USER` in front of the test command (`Tests/MockServers.swift`). The EPUB egress test
needs the egress collector of `apps/desktop-web/epub` (`pnpm egress` there, port 4815,
`TEST_RUNNER_STORYARC_EGRESS_PORT` to move it): the sandboxed app may not listen on a socket,
so the eight-vector page's arrivals are counted out of process, and the test reads the count.
Without it the two egress tests skip and say so; the rule list's compile test runs regardless.

The EPUB, PDF and player walks open corpus fixtures (`packages/test-fixtures/ebooks`,
`audiobooks` and the two PDFs under `comics`), copied into the test bundle. An EPUB or an
audiobook opens from a fixed copy in the container under its own id, outside the library, so
the library screens of the snapshots do not change. A run that stops before a walk closes its
window leaves that window's session saved, and the next launch restores it: the walks close
such windows and forget such sessions before they open their own.

The snapshot suite holds each screen of `Tests/MacCatalogue.swift` against
`Tests/__Snapshots__/`, drawn in-process at one pixel per point, so materials are absent.
To record again, run the test command with `TEST_RUNNER_STORYARC_SNAPSHOT_RECORD=1` in
front, then copy the images and `macos-version.txt` from the container's
`tmp/snapshots/record/` into `Tests/__Snapshots__/`. A failing run leaves the drawn image in
`tmp/snapshots/failures/`. On a major macOS version other than the one the references name
the screen test is skipped, with that reason. The references are drawn with the app in
front; when another application is in use macOS can refuse to bring the test host forward,
every window then draws inactive, and the screen test is skipped with that reason too
(`Tests/AppActivation.swift`). On CI (`CI` set) the test runs regardless and reports it.

The references draw the same on every Mac because the run pins what the Mac would
otherwise choose. The first walk of a run copies the fixture comics into the container
afresh, each on its own fixed date a day apart in name order (`TestFixtures.layDownComics`),
so *Recently Added* does not follow the checkout's or the copy's clock, and empties the cover
cache. The scheme's test action runs in English for the US region, with scroll bars shown
only while scrolling (`project.yml`). What it does not pin: the system accent colour (the
references assume the default, Multicolor), Reduce Transparency and Increase Contrast.

Requires macOS 26, Xcode 27.1 with the Metal toolchain component (`AGENTS.md`
section 3b) and `brew install xcodegen`. For the Xcode IDE, run
`cd apps/desktop-macos && xcodegen generate && open StoryArcMac.xcodeproj`.

CI: `.github/workflows/desktop-macos.yml`. It is path-filtered, so mobile CI is
unaffected.

Builds are ad-hoc signed. A downloaded ad-hoc build carries the quarantine
attribute and Gatekeeper blocks it. Notarised direct download and the Mac App
Store need the Apple Developer Program (99 USD per year). The owner takes that
step later. Both routes need App Sandbox, which is on already.

## What it inherits

All 12 `StoryArcKit` targets compile for macOS today, and the iOS CI job tests
them on macOS. The Mac app reuses `StoryArcCore`, `DesignSystem`, `Formats`,
`Catalogue`, `Kavita`, `Smb`, `Persistence`, `Playback`, and the feature modules.
The parity audit finds 64 of 95 main requirements hold as written on macOS.

## What it must redo

| Area | Work |
| --- | --- |
| App shell | About 3,400 lines in `apps/ios/App` exist twice. The Mac shell rebuilds the composition root, the library shell and the downloads views. A shared `AppSupport` package would remove the copy. It needs a change under `apps/ios`, so it waits. |
| Folder access | `FolderBookmarks` makes `.minimalBookmark` bookmarks. App Sandbox needs `.withSecurityScope` on create and on resolve. `CredentialStore` needs `kSecUseDataProtectionKeychain`. |
| Comic reader | `ZoomablePage` and `PageScrollView` compile and do nothing. They are UIKit. The Mac needs zoom, pan, click zones and curl drag on AppKit or SwiftUI gestures. |
| PDF selection | `PdfPageOverlay` and `PdfTextModel` need `NSColor` and `NSPasteboard` ports. |
| EPUB | A new Swift target, for example `StoryArcEpubMac`, on `WKWebView`, `WKURLSchemeHandler` and the pinned renderer. It serves archive resources through a custom scheme and denies all other network access (ADR-0015). |
| Playback | `NowPlaying` and `PlaybackAudioSession` sit inside `#if os(iOS)`. Split them. `MPNowPlayingInfoCenter` gives media keys on macOS. `AVAudioSession` does not exist there. |
| Images | `EntryPoster` and `PlayerArtworkImage` return `nil` on macOS. Add `NSImage` branches. |
| SMB | The `Smb` package needs only `network.client`. Do not mount through `NetFS`. Add the local-network usage text to the Mac `Info.plist`. |

## What drops

| Mobile feature | On macOS |
| --- | --- |
| CarPlay | Dropped. |
| Orientation lock, brightness control | Dropped. |
| Haptics | No-op. |
| App icon chooser | Dropped. |
| Volume-key page turns | Dropped. Arrow keys and the space bar replace them. |
| Cellular data setting | Becomes the metered-connection setting. |
| Share sheet | Becomes save-to-file and reveal in Finder. |

## Desktop-new features

Accepted in the parity audit and specified in `desktop-experience`:

- Menu bar with `File`, `Edit`, `View`, `Go` and `Window` menus, and full keyboard reading.
- `NavigationSplitView` sidebar, a native toolbar, a `Settings` scene.
- Multiple reader windows with `WindowGroup(for:)`, restored on relaunch.
- Two-page spreads by window shape. Full screen reading.
- Open from Finder: file associations, drag and drop, Dock icon drop.
- Pointer reading: trackpad pinch and scroll zoom, hover to reveal chrome, right-click menus.
- Live folder watching. Media keys. Recent items in the Dock menu.

Later: Quick Look thumbnails for covers, Handoff from iPhone, Spotlight titles, `storyarc://` URLs.
Rejected: tabs, tray icon, command palette, desktop widgets.

Liquid Glass is for chrome only. The artwork stays the interface.

## Open questions

Questions 2 to 4 are answered: the reader has its own windows, the chrome accent is the
brand colour with a System choice in Appearance, and the edge click zones are on by
default with a Reading setting to turn them off (task 1.26).

1. The page curl on a desktop: default transition, or a different default for a Mac reader? Wave 5.
5. Which path serves a user who mounted SMB in Finder? The `Smb` package covers it. Low priority.
6. Is `PageCurl.metal` valid on macOS? The app builds it (`ReaderFeature` is linked); the curl is wave 5.
