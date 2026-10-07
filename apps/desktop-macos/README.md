# StoryArc for macOS

**Status: wave 0, base only.** The app opens an empty window. It proves that
the project generates, builds, and links `StoryArcKit`. No reading feature exists
yet. [ADR-0018](../../docs/decisions/0018-desktop-clients.md) supersedes the
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
| Shared code | `apps/ios/Packages/StoryArcKit`, consumed by path. Wave 0 links `DesignSystem` and `StoryArcCore`. Each wave adds the products it needs. |
| Bundle id | `com.mecedric.storyarc` |
| Sandbox | App Sandbox on. Entitlements: `app-sandbox`, `files.user-selected.read-write`, `network.client`. Later waves add `files.bookmarks.app-scope`. |
| EPUB | `WKWebView` with the pinned Readium ts-toolkit renderer. Readium swift-toolkit is iOS only and cannot serve macOS. |
| PDF | PDFKit, through `StoryArcKit`. |
| Not used | Mac Catalyst. It gives an iPad app in a window. |

`apps/ios/project.yml` and `apps/ios/App` stay untouched. The Mac shell has its
own source folder.

## Folder layout

```
apps/desktop-macos/
├── project.yml                 XcodeGen spec; StoryArcMac.xcodeproj is generated
├── App/
│   ├── StoryArcMacApp.swift    the @main entry
│   ├── RootView.swift          the placeholder window
│   ├── StoryArcMac.entitlements
│   └── Localizable.xcstrings
└── README.md
```

## Build and run

```bash
pnpm build:macos      # xcodegen generate, then xcodebuild build, scheme StoryArc
```

Requires macOS 26, Xcode 26 and `brew install xcodegen`. For the Xcode IDE, run
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

1. The page curl on a desktop: default transition, or a different default for a Mac reader?
2. Does the reader belong in its own window, or as a mode of the library window? The plan assumes its own window.
3. Chrome accent: the StoryArc brand colour, or the system accent colour?
4. Edge click zones: off by default on desktop?
5. Which path serves a user who mounted SMB in Finder? The `Smb` package covers it. Low priority.
6. Is `PageCurl.metal` valid on macOS? The audit did not build it.
