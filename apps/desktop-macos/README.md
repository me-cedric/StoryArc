# StoryArc for macOS

**Status: wave 2, open and read a comic.** The library window opens on Home (Keep
reading, Up next), lists the chosen folders' publications as a grid or a list over
`StoryArcKit`'s `LibraryModel`, with search, filters, sorting and a publication page. Each
publication reads in its own window with keys, the edge click zones, zoom and pan, spreads
by window shape and a sliding drag; positions are written on every turn and before a
window closes or the app quits. Files open from Finder, a drop and the Dock menu; folders
keep their bookmarks and are watched with FSEvents. The preferences have a search, the
accent choice and the app's own text size. A PDF opens through the same reader model and
is not walked yet; EPUB, audio, network sources and secrets are later waves. [ADR-0018](../../docs/decisions/0018-desktop-clients.md) supersedes the
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
| EPUB | `WKWebView` with the pinned Readium ts-toolkit renderer. Readium swift-toolkit is iOS only and cannot serve macOS. |
| PDF | PDFKit, through `StoryArcKit`. |
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
│   │                           reader targets and restoration, the window registry
│   ├── Settings/               MacSettings (the preferences model), the tabs, the search index
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
│   ├── CaptureTests.swift, Wave2CaptureTests.swift   the frames, on request
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
[`wave1/`](../../docs/designs/screenshots/desktop/macos/wave1/README.md) and
[`wave2/`](../../docs/designs/screenshots/desktop/macos/wave2/README.md)
for how and for what they do and do not show.

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
