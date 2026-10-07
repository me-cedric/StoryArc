# Desktop parity audit, 2026-10-07

Wave 0 of the `desktop-clients` change. This audit classifies every requirement in the 17 capability specs for macOS, Windows and Linux. It adds the mobile build state, a reuse map for macOS, and a ranked list of desktop-only features.

Sources read: the 17 files in `docs/openspec/specs/*/spec.md`, the 13 changes in flight, `docs/openspec/STATUS.md` (state to 2026-10-07), `docs/delivery/remaining-work-2026-09-28.md`, and the three `apps/desktop-*/README.md` files. The macOS reuse map comes from reading `apps/ios/Packages/StoryArcKit/Sources` and `apps/ios/App`, and from one `swift build` of the package on this Mac.

Decisions that bind this audit: D1 to D11 of the lead, and `AGENTS.md` section 2. Desktop behaviour goes into a new spec, `desktop-experience`, with ADDED requirements only (D7). This audit is the input for that spec. It does not change any file under `docs/openspec/specs`.

## 1. Result in numbers

Main specs: 95 requirements.

| Class | macOS | Windows | Linux |
| --- | --- | --- | --- |
| INH | 63 | 60 | 60 |
| READ | 25 | 27 | 27 |
| PART | 5 | 6 | 6 |
| DROP | 2 | 2 | 2 |
| Total | 95 | 95 | 95 |

Requirements of the changes in flight that add capabilities: 35 requirements.

| Class | macOS | Windows | Linux |
| --- | --- | --- | --- |
| INH | 26 | 26 | 26 |
| READ | 8 | 8 | 8 |
| PART | 0 | 0 | 0 |
| DROP | 1 | 1 | 1 |
| Total | 35 | 35 | 35 |

What the numbers say:

- Most of the contract holds as written. The specs were platform-neutral by design.
- Every DROP is the same two groups: the app icon chooser, and the mobile-only hardware (CarPlay, Android Auto).
- Nothing in the contract blocks a desktop app. The cost sits in the READING items, because each one needs a desktop implementation and a desktop test.
- Windows and Linux differ from macOS in implementation cost, not in contract. They share one Rust core (D5) that must re-create what `StoryArcKit` already holds in Swift.

## 2. How to read the tables

Classes, one per requirement per platform:

| Class | Meaning |
| --- | --- |
| INH | The platform-neutral text holds as written. |
| READ | The text holds. Its desktop meaning differs. The note gives the reading. |
| PART | Some scenarios drop. The note names them. |
| DROP | Mobile only. The note gives the reason. |

Mobile column, iOS / Android: `B` built, `P` partial (a named gap is open), `M` missing. The values come from `STATUS.md` (waves to 2026-10-07) and the 2026-09-28 gap list. They are an inference per requirement, because `STATUS.md` scores scenarios and capabilities, not requirements. No requirement is `M`. Home-screen widgets are the one missing clause (a system-integration scenario inside Platform-native interface, which reads `P`).

Universal readings. These apply everywhere and the tables do not repeat them:

- Tap becomes click. Long press becomes right-click. Swipe becomes drag, trackpad swipe or key.
- Pinch becomes trackpad pinch or Ctrl/Cmd plus wheel.
- Backgrounded becomes window closed or app hidden. Terminated becomes quit.
- Cellular becomes metered connection (D9).
- Sheet becomes popover or window where a pointer is the input.
- Haptics are a no-op (D9).
- Screen reader means VoiceOver (macOS), Narrator through UI Automation (Windows), Orca through AT-SPI (Linux).

## 3. Main specs

### `collections-and-reading-lists`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| Collections | B/B | INH | INH | INH | Right-click replaces long press. |
| Reading lists | B/B | INH | INH | INH | Drag to reorder works with a pointer. |
| Server-backed and local objects | B/B | INH | INH | INH | Offline edit queue unchanged. |
| Bulk actions | B/B | INH | INH | INH | Shift and Ctrl/Cmd click select many. |
| Shelves on the home surface | B/B | INH | INH | INH | Home is a sidebar destination. |

### `comic-reader`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| Page transitions in the comic reader | B/B | READ | READ | READ | Swipe becomes drag, trackpad swipe, wheel or key. Scroll mode uses the wheel. |
| Reading direction | B/B | INH | INH | INH | Arrow keys mirror in right-to-left. |
| Page fitting and zoom | B/B | READ | READ | READ | Pinch becomes trackpad pinch or Ctrl+wheel. Double-tap becomes double-click. Landscape becomes a wide window. |
| Auto-hiding chrome | B/B | READ | READ | READ | Centre tap becomes pointer move or click. Full screen hides the menu bar. A native title bar stays outside the page. |
| Navigation within a publication | B/B | INH | INH | INH | Slider and thumbnails live in the reader menu or a popover. |
| Image adjustments | B/B | INH | INH | INH | Win and Linux need the filters in the Rust core. macOS uses Core Image. |
| Reader performance | B/B | READ | READ | READ | Screen stays awake becomes display sleep inhibit (IOPMAssertion, SetThreadExecutionState, portal Inhibit). Memory pressure scenario keeps its meaning. |
| System integration | B/B | PART | PART | PART | Drops: volume buttons, orientation lock. Keeps: keyboard, controller, screenshot. |

### `ebook-reader`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| Reflowable rendering | B/B | READ | READ | READ | One pinned JS renderer in WKWebView, WebView2 or WebKitGTK (D6). Typography axes become CSS. StoryArcEpub (Readium Swift) is not used on macOS. |
| Reader themes | B/B | READ | INH | INH | macOS has no Dynamic Type. The largest-text scenario is met by the reader's own size control. |
| Pagination and progress | B/B | INH | INH | INH | Position stays in words. No reflowable page number. |
| Navigation and annotation | B/B | READ | READ | READ | Egress denial must be proved again on three web views (ADR-0015). Footnote popover and link hand-off use the desktop browser. |
| PDF rendering | B/P | INH | READ | READ | macOS: PDFKit as on iOS. Win and Linux: PDFium or poppler in the core, because Windows.Data.Pdf has no text layer. Outline is available on all desktops. |
| Reading aloud | P/P | READ | READ | READ | Backgrounded becomes window hidden. Lock screen becomes media keys and system media controls. macOS AVSpeech, Windows SpeechSynthesis, Linux speech-dispatcher. Control is absent where no engine exists. |

### `kavita-server`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| Kavita connection | B/B | INH | INH | INH | Win and Linux: new Rust client. macOS: Kavita target. |
| Library structure | B/B | INH | INH | INH | Same wire shapes. |
| Metadata | B/B | INH | INH | INH | - |
| Server-side collections and reading lists | B/B | INH | INH | INH | - |
| Progress synchronisation | B/B | INH | INH | INH | Locator format must match mobile. Readium ts-toolkit does. |
| Server-side search | B/B | INH | INH | INH | - |

### `library-browsing`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| Unified library | B/B | INH | INH | INH | - |
| Search | B/B | INH | INH | INH | Focus on Cmd/Ctrl+F or a toolbar field. |
| Filtering | B/B | INH | INH | INH | - |
| Sorting | B/B | INH | INH | INH | Win and Linux need locale collation in the core (ICU). |
| What could not be opened | B/B | INH | INH | INH | Announced via VoiceOver, Narrator, Orca. |
| Presentation | B/B | READ | READ | READ | Columns follow window width. Index rail may give way to a scrollbar. A sortable list view is allowed. |
| Continue reading | B/B | INH | INH | INH | - |

### `local-library`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| Folder libraries | B/B | READ | READ | READ | A third scenario replaces the iOS and Android ones: folder chooser. macOS sandbox needs security-scoped bookmarks. Flatpak needs the document portal. |
| Opening a single file | B/B | READ | READ | READ | Open-in becomes file association, Open With, drop on icon, argv. Remembered file becomes recent documents. |
| Imported copies | B/B | INH | INH | INH | Rarely needed: desktop reads in place. |
| Watched changes | B/B | READ | READ | READ | Backgrounded becomes app not running: rescan at launch. FSEvents, ReadDirectoryChangesW, inotify (watch limit). A Flatpak folder grant passes no native events: polled reconciliation at 10 seconds or less. |

### `localization`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| Supported languages | B/B | INH | INH | INH | Per-app language on macOS. Win and Linux follow the user locale list. |
| Locale-correct formatting | B/B | INH | INH | INH | Rust core needs ICU4X or equivalent. |
| Layout resilience | B/B | INH | INH | INH | Pseudo-locale walk needed on each desktop. |
| Content language | B/B | INH | INH | INH | Four-language string source must feed .xcstrings, .resw and gettext. |

### `native-experience`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| Platform-native interface | P/P | READ | PART | PART | SwiftUI (Liquid Glass), WinUI 3 (Fluent), GTK4/libadwaita. Quick actions become Dock menu, Jump List, GtkRecentManager and static .desktop actions. Win and Linux drop Continuity (Handoff). |
| Dynamic colour | P/P | PART | PART | PART | Drops the Android scenario. Cover-derived accent stays in readers. Chrome accent: decide brand colour or OS accent (open question). |
| Adaptive layout | B/P | PART | PART | PART | Drops Split View, Slide Over, foldables, orientation. Sidebar is permanent. Multi-window and resize stay. |
| Reader chrome material | B/B | INH | READ | READ | Windows: Acrylic or Mica, opaque when transparency is off. Linux: libadwaita has no blur, so opaque overlay. |
| Theme sheet reachability | B/B | INH | INH | INH | Popover anchored to its control. |
| Accessibility | P/P | READ | READ | READ | VoiceOver, UI Automation, AT-SPI/Orca. Dynamic Type becomes OS text scaling (macOS: the reader's own size control). Touch target becomes pointer target. |
| Performance and responsiveness | B/B | INH | INH | INH | Cold launch budget needs a desktop number. |
| Visual proof of interface changes | P/P | READ | READ | READ | Captures per desktop, both appearances. Linux adds compositor and DE matrix. |
| The icon a reader chose | B/B | DROP | DROP | DROP | No supported runtime icon switch that persists on desktops. |
| Chrome for a mode a reader is in | B/B | READ | READ | READ | Selection mode uses a toolbar swap and modifier-click. |

### `network-share`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| SMB connection | P/P | PART | READ | READ | SMB 3 encryption is missing in the `Smb` package (SMBClient 0.3.1), so the Mac cannot meet the Encryption scenario of `desktop-experience`: it states the source is not encrypted and a server that requires encryption fails with the reason named. A parent edit under `apps/ios/Packages` would add it. Windows and Linux use the in-app Rust client (ADR-0018), which has SMB 3 encryption. |
| Disconnect and reconnect | B/B | INH | INH | INH | Sleep and wake becomes lid close. Wi-Fi switch stays. |
| Streaming reads | B/B | READ | READ | READ | Cellular becomes metered (D9): Low Data Mode, NetworkCostType, NetworkManager metered. |
| Discovery | B/B | READ | READ | READ | mDNS on macOS and Linux (avahi). Windows has no default mDNS: WS-Discovery or manual entry. Permission prompt exists on macOS only. |

### `offline-downloads`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| Downloading | P/B | INH | INH | INH | iOS publication-page download of an OPDS book still open. |
| Queue management | B/B | READ | READ | READ | Background downloads become downloads while the app runs. No desktop keeps a background session after quit (spec: No presence when the app is closed): a download pauses at quit and resumes at launch. |
| Network policy | B/B | READ | READ | READ | Wi-Fi only becomes not on a metered link. |
| Storage management | B/B | INH | PART | PART | Backup exclusion: macOS uses the Time Machine flag. Win and Linux drop it and store in a non-roaming data directory. |
| Offline integrity | B/B | INH | INH | INH | - |

### `opds-catalog`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| OPDS protocol support | B/B | INH | INH | INH | Certificate pin flow same. Win and Linux need a Rust OPDS parser. |
| Feed navigation | B/B | INH | INH | INH | - |
| Acquisition | B/B | INH | INH | INH | - |

### `page-transitions`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| Transition modes | B/B | INH | INH | INH | - |
| The curl | P/P | READ | READ | READ | Finger becomes pointer drag, trackpad or key. macOS reuses the Metal shader. Win: custom shader in WinUI. Linux: GtkGLArea. On X11 the curl is absent until the Linux spike shows it holds the frame budget there (honest-absence scenario). EPUB curl still on a timer (task 8.12). |
| Reduced motion | B/B | INH | INH | INH | macOS flag, SPI_GETCLIENTAREAANIMATION, gtk-enable-animations. |
| Turn triggers | B/B | PART | PART | PART | Drops volume buttons. Edge click zones sit beside text selection and window drag: keep them off by default on desktop. |
| Transition performance | B/B | READ | READ | READ | 120 Hz becomes the display's own rate, per monitor. X11 is measured by the Linux curl spike. |

### `publication-formats`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| Supported formats | B/B | INH | INH | INH | CB7 stays refused. RAR needs libarchive in the Rust core. |
| Streaming capability per format | B/B | INH | INH | INH | Same ranged-read rules. |
| Page ordering | B/B | INH | INH | INH | - |
| Metadata extraction | B/B | INH | INH | INH | - |
| Cover extraction | B/B | INH | INH | INH | OS thumbnail providers are a new feature, not a change here. |
| Page decoding | B/B | INH | READ | READ | HEIC and AVIF depend on OS codecs on Windows and on libheif and dav1d on Linux. The core must ship its own set. |

### `reading-progress`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| Local progress store | B/B | INH | INH | INH | Win and Linux: SQLite in the core. macOS: SwiftData. |
| Resuming | B/B | INH | INH | INH | - |
| Synchronisation | B/B | INH | INH | INH | - |
| Conflict resolution | B/B | INH | INH | INH | - |
| Progress across formats and sources | B/B | INH | INH | INH | Locator JSON must round-trip with mobile. |
| Privacy of reading history | B/B | INH | INH | INH | - |

### `reading-themes`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| Theme presets | B/B | INH | INH | INH | - |
| Theme axes | B/B | INH | INH | INH | - |
| Custom colour | B/B | INH | INH | INH | - |
| Theme scope and persistence | B/B | INH | INH | INH | - |

### `settings-and-about`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| Appearance | B/B | INH | INH | INH | System appearance read from the OS or portal. |
| Choosing the app icon | B/B | DROP | DROP | DROP | Same reason as native-experience. |
| Settings organisation | B/B | READ | READ | READ | A preferences window (Cmd+, / Ctrl+,), searchable. |
| Privacy | B/B | INH | INH | INH | - |
| About | B/B | READ | READ | READ | System About panel or AdwAboutDialog. Licence inventory must list the Rust and .NET dependencies. |
| What changed in this version | B/B | INH | INH | INH | Shown after an update from any channel. |

### `sources`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| Source registry | B/B | INH | INH | INH | - |
| Credential storage | B/B | READ | READ | READ | Keychain (needs the data-protection keychain under sandbox), Credential Manager, Secret Service. Without a keyring on Linux the app does not save the secret: it holds it in memory for the session, shows one grey line and asks again at the next launch. |
| Connection state | B/B | INH | INH | INH | - |
| Metadata cache | B/B | INH | INH | INH | - |
| Source health visibility | B/B | INH | INH | INH | - |
| Refresh visibility | B/B | INH | INH | INH | - |


## 4. Requirements in flight

These belong to changes that add capabilities. They are not in the 17 main specs yet. The other changes (`reader-theming-and-page-transitions`, `close-the-audited-gaps`, `page-browser-carousel`, `android-brand-palette-by-default`, `a-server-shelf-shows-what-it-holds`, `one-vocabulary-in-four-languages`) add scenarios to main requirements. They fall under the main-spec rows above.

### `audio-playback (audiobooks-and-playback)`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| One player for everything that speaks | B/P | INH | INH | INH | Mini player sits in the window toolbar or footer. |
| Playback controls | B/B | READ | READ | READ | Add media keys and system media controls (D10). |
| Reaching the player without sight | B/B | READ | READ | READ | Per-OS screen reader. |
| Chapters before the first minute | B/B | INH | INH | INH | - |
| Listening in a car | P/P | DROP | DROP | DROP | CarPlay and Android Auto are mobile only (D9). |

### `cover-art (cover-for-every-publication)`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| The cover ladder | P/P | INH | INH | INH | - |
| A reader may choose a cover | P/P | INH | INH | INH | File chooser. |
| Looking a cover up is the reader's choice | P/P | INH | INH | INH | - |
| Finding a cover on the web is a hand-off | P/P | READ | READ | READ | Opens the default browser. |
| Writing a cover back to a source | P/P | INH | INH | INH | - |

### `library-portability`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| One versioned document | P/P | INH | INH | INH | - |
| What an export carries | P/P | INH | INH | INH | - |
| Secrets travel only sealed, and only when asked | P/P | INH | INH | INH | - |
| Import merges | P/P | INH | INH | INH | Import preview screen is still missing on mobile. |

### `library-sync`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| The sync document lives where the reader chose | P/P | INH | INH | INH | A synced folder fits desktops well. |
| When a sync happens | P/P | READ | READ | READ | Foreground and background become app running and quit. |
| Two devices that both moved | P/P | INH | INH | INH | - |
| Kavita keeps what Kavita owns | P/P | INH | INH | INH | - |

### `home-screen (one-library-three-destinations)`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| Keep reading | B/B | INH | INH | INH | - |
| Up next | B/B | INH | INH | INH | - |
| The rest of the home surface | B/B | INH | INH | INH | - |
| The home surface never waits on a source | B/B | INH | INH | INH | - |
| The home surface when there is little to show | B/B | INH | INH | INH | - |

### `navigation-shell (one-library-three-destinations)`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| The destination set | B/B | READ | READ | READ | Tab bar becomes sidebar. |
| Reaching search | B/B | READ | READ | READ | Toolbar search field and shortcut. The field stays in place and its results take over the content column. Recorded as the `desktop-experience` requirement Search on a desktop. |
| Where a source can be reached | B/B | INH | INH | INH | - |
| The destination set on a large screen | B/B | INH | INH | INH | This is the desktop default. |
| Chrome that gets out of the way | B/B | READ | READ | READ | Desktop keeps a title bar and menu bar. Only reader chrome hides. |

### `publication-detail`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| Reaching a publication's page | B/B | INH | INH | INH | - |
| What the page shows | B/B | INH | INH | INH | - |
| One primary action | B/P | INH | INH | INH | - |
| Where it came from | B/B | INH | INH | INH | - |
| Colour taken from the cover | B/B | INH | INH | INH | - |
| The page on a large screen | B/B | INH | INH | INH | - |

### `read-aloud-beyond-the-reader`

| Requirement | Mobile i/a | macOS | Windows | Linux | Note |
| --- | --- | --- | --- | --- | --- |
| The transport outside the reader | P/P | READ | READ | READ | Mini bar plus media keys and system media controls. |


## 5. macOS reuse map

### 5.1 Evidence

- `swift build` of `apps/ios/Packages/StoryArcKit` on this Mac (macOS host) exits 0. All 12 targets compile for macOS today. It prints warnings only, mostly unused `public import`.
- `pnpm test:ios` already runs the whole package with `-destination 'platform=macOS'`. The macOS floor of the package is 26, as D2 needs.
- `PageCurl.metal` is not built by `swift build`. Only `xcodebuild` builds it. This audit did not check it on macOS.
- Compiling is not reuse. Four spots compile on macOS and do nothing (section 5.3).
- `StoryArcEpub` declares `platforms: [.iOS(.v26)]` and depends on Readium Swift. It does not build for macOS. A Mac needs its own EPUB renderer (D6).

### 5.2 Target by target

| Target | Files / lines | macOS today | Blockers and gaps for a Mac app |
| --- | --- | --- | --- |
| `StoryArcCore` | 86 / 11.6k | Compiles. | None. Pure Swift. Quick-action and icon-choice models are reusable as values. |
| `DesignSystem` | 12 / 1.4k | Compiles. | None. `sensoryFeedback` is a no-op on a Mac. Check Liquid Glass look on macOS. |
| `Formats` | 47 / 7.1k | Compiles. | Two `#if os(iOS)` guards (`CoverCache`, `CoverOverrideStore`) skip file protection classes. Harmless. PDFKit and AVFoundation exist on macOS. |
| `Catalogue` | 15 / 2.7k | Compiles. | None. `OpdsTrust` already has an `#if os(macOS)` branch. |
| `Kavita` | 9 / 1.9k | Compiles. | None. |
| `Smb` | 5 / 0.9k | Compiles. | None. SMB 3 encryption missing, as on iOS. Local-network permission text goes in the Mac Info.plist. |
| `Persistence` | 32 / 3.6k | Compiles. | `FolderBookmarks` makes bookmarks with `.minimalBookmark`. Under App Sandbox a Mac needs `.withSecurityScope` on create and on resolve. `CredentialStore` has no `kSecUseDataProtectionKeychain`. A sandboxed Mac needs it for the keychain access group. `DownloadStore` skips backup exclusion on macOS (`#if os(iOS)`). `StorageUsage` imports WebKit (fine). |
| `Playback` | 23 / 2.8k | Compiles. | `NowPlaying.swift` and `PlaybackAudioSession.swift` are inside `#if os(iOS)`. On a Mac there is no Now Playing entry and no remote commands, so no media keys. `MPNowPlayingInfoCenter` exists on macOS. The guard must split into iOS and macOS paths. `AVAudioSession` does not exist on macOS and must be skipped. |
| `PlayerFeature` | 9 / 1.5k | Compiles. | `PlayerArtworkImage.png` returns `nil` on macOS (no `UIKit`). |
| `ReaderFeature` | 71 / 8.9k | Compiles. | The largest gap. See 5.3. 16 files use `#if os(iOS)`, 9 import UIKit, 3 touch `UIApplication`. |
| `SettingsFeature` | 24 / 3.6k | Compiles. | `AppIconSettings` and `AppIconStore` use `UIApplication.alternateIconName`. They are DROP on desktop. `BuildInfo` and `Diagnostic` use `UIDevice` and have a non-UIKit branch. |
| `LibraryFeature` | 202 / 31.6k | Compiles. | 21 files with `#if os(iOS)` (navigation bar styles, keyboard and presentation modifiers). `CoverSearchHandoff.SystemBrowser` is a `UIViewControllerRepresentable` (use the default browser on a Mac). Four files already have AppKit branches. `EntryPoster.image(from:)` returns `nil` on macOS. The iOS layouts assume a tab bar and full-screen covers. They need Mac chrome. |

### 5.3 Compiles but does nothing on a Mac

| Piece | What a Mac gets today | What a Mac shell must add |
| --- | --- | --- |
| `ZoomablePage` | A plain fitted `Image`. The zoomable view is a `UIViewRepresentable` over `UIScrollView`. | Zoom, pan, click zones, drag-to-turn and curl drag with `NSScrollView` magnification or SwiftUI gestures. |
| `PageScrollView` | Nothing (whole file is `#if os(iOS)`). | A Mac scroll mode. |
| `PdfPageOverlay`, `PdfTextModel` | No mark overlay and no copy. Both use `UIColor` and `UIPasteboard` inside `#if os(iOS)`. | `NSColor` and `NSPasteboard` ports. |
| `ReaderSystemChrome`, `ReaderBrightness`, `ReaderOrientation` | Nothing. | Sleep assertion (`IOPMAssertion`). Brightness and orientation are DROP. |
| `FrameProbe` | No frame counting (`CADisplayLink`). | `NSView.displayLink` if the 120 Hz gate is kept. |
| `NowPlaying` | No media keys, no Now Playing. | See `Playback` above. |
| `EntryPoster`, `PlayerArtworkImage` | A `nil` image. | `NSImage` branch. |

### 5.4 What the iOS app shell does that a Mac shell must redo

`apps/ios/App` is 22 Swift files, about 3.4k lines with its plist and assets, in the app target. The Mac project cannot import them, and `apps/ios` stays untouched (D2). The Mac shell rebuilds or copies the following.

| iOS shell piece | Mac shell work |
| --- | --- |
| `StoryArcApp.swift` (351 lines): composition root, stores, `scenePhase`, `onOpenURL`, one `fullScreenCover` reader | One `Window` for the library plus a reader window per publication. State restoration. Open-file and open-URL handling. Quit flushes progress. |
| `AppShell.swift` (384): `TabView`, `tabViewBottomAccessory` mini player | `NavigationSplitView` sidebar, toolbar, mini player in the window. Commands and menu bar. |
| `OrientationDelegate`, `CarScene` | DROP. |
| `HomeScreenQuickActions` (`UIApplicationShortcutItem`) | Dock menu from `NSApplicationDelegate`. |
| `ReadingContinuity` (`NSUserActivity`, Spotlight) | Reusable. Handoff and Spotlight exist on macOS. |
| `OpenedFile`, `RefusedFile`, `KeepForOffline`, `NextEntryOpening`, `ReadingSelection` | Mostly Foundation and SwiftUI. Copy, or move into a shared package later. |
| `DownloadsDestination`, `DownloadQueueSection`, `StorageBreakdownSection`, `FinishedDownloadSweep`, `BackgroundDownloads` | SwiftUI. The background-session hand-off is dropped on macOS: downloads pause at quit (spec: No presence when the app is closed). |
| `StoryArcAppSettingsSheet`, `StoryArcAppActions`, `StoryArcAppSources`, `SourceReconnectSheet`, `OnDeviceShelf` | A `Settings` scene replaces the sheet. Rest is reusable logic. |
| `Info.plist`: document types, exported UTIs, `UIBackgroundModes`, orientations, file sharing | Keep document types and UTIs. Drop the `UI*` keys. Add the local-network usage text and Bonjour services. |
| `StoryArc.entitlements` (keychain access group only) | Add App Sandbox, user-selected read access, app-scope bookmarks, network client. Keep the keychain group. |
| EPUB reader (`StoryArcEpub`) | New, built on the pinned JS renderer in `WKWebView` (D6). |

Duplication risk: about 3.4k lines of composition exist twice once the Mac shell lands. Extracting a shared `AppSupport` target needs a change under `apps/ios`. That belongs after wave 0. List it as a later task.

## 6. Desktop-new features

Ranked by value to a reader. Verdict: ACCEPT (goes in `desktop-experience`), LATER (accepted, after the base), REJECT.

| # | Feature | Verdict | Why | Cost notes |
| --- | --- | --- | --- | --- |
| 1 | Menu bar, shortcuts and full keyboard reading | ACCEPT | A desktop reader without keys is broken. | All three. Menu bar is native on macOS. Windows and Linux use in-window menus or a hamburger menu. |
| 2 | Two-page spreads by window shape | ACCEPT | The first thing a comic reader wants on a wide window. Spec already has spreads and a pairing offset. | Check `PageDecoder.isSpread`: it had no production caller on 2026-09-28. A curl over a spread already works on mobile. |
| 3 | Full screen reading | ACCEPT | Matches "nothing on screen while reading". | Native on all three. Linux needs a compositor-safe path (Hyprland, tiling). |
| 4 | Multiple reader windows | ACCEPT | Compare issues. Read while the library stays open. Restore on relaunch. | SwiftUI window scenes. WinUI needs one `Window` per reader. GTK needs one `AdwApplicationWindow` per reader. |
| 5 | Open from the file manager: file association, drag and drop, argv | ACCEPT | The main way to open one file on a desktop. | UTI, ProgID, `.desktop` MIME. Flatpak passes file paths through the portal. |
| 6 | Pointer reading: wheel and trackpad zoom and pan, hover reveals chrome, right-click menus, cursor hides | ACCEPT | Replaces every touch gesture. | Conflict: edge click zones against window drag and text selection. Keep zones off by default. |
| 7 | Live folder watching | ACCEPT | Desktop apps stay open. Spec has Watched changes. Mobile caps it at 96 directories. | `inotify` limit on Linux. Network shares do not report changes. |
| 8 | Media keys and system media controls | ACCEPT | Read-aloud and audiobooks need play, pause and skip from the keyboard. | `MPNowPlayingInfoCenter`, SMTC, MPRIS. Needs the `Playback` split on macOS. |
| 9 | Recent items in Dock menu, Jump List, `GtkRecentManager` and static `.desktop` actions | ACCEPT | Mirrors the mobile quick actions that already exist. | `NSDockTile` menu, `ICustomDestinationList`, `GtkRecentManager`. A `.desktop` file cannot name a publication, so its actions are static. |
| 10 | Tiling-friendly windows and a stable Wayland app id | ACCEPT | Hyprland, Sway and COSMIC users need predictable rules. | Linux only. App id `com.mecedric.StoryArc`. |
| 11 | OS thumbnail providers for covers (Quick Look, Explorer, GNOME thumbnailer) | LATER | The file manager shows real covers. High polish, low reading value. | Windows shell extensions cannot run on managed .NET. Needs a native shim. Linux thumbnailer is a small CLI. |
| 12 | Handoff from iPhone to Mac | LATER | Free on macOS because iOS already publishes the activity. | macOS only. Needs both apps signed by one Apple team (task 6.8). The Mac opens the book at the position it holds. Win and Linux have no equivalent. |
| 13 | Spotlight index of titles (macOS) | LATER | Search by title from the OS. | Reuse `ReadingContinuity`. |
| 14 | `storyarc://` URL scheme and command-line open | LATER | Scripts and launchers (Hyprland binds). | Small. |
| 15 | Widgets on the desktop | REJECT for now | Mobile widgets wait on ADR-0011. | Same prerequisite. |
| 16 | Reader tabs inside one window | REJECT | Windows already cover it. Tabs add chrome. | None. |
| 17 | Tray icon, background sync, notifications | REJECT | AGENTS.md section 2 allows no backend. The sources spec forbids a notification for a refresh. | None. |
| 18 | Command palette | REJECT | A third way into every action. The menu bar already is one. | None. |
| 19 | Printing, presentation mode, global hotkeys | REJECT | Not reading. | None. |

## 7. The five riskiest READING items

1. **Web-view egress for EPUB** (`ebook-reader`, Navigation and annotation, plus Reflowable rendering). The spec says a book never reaches the network, and scripts stay on. WKWebView, WebView2 and WebKitGTK each filter requests in a different way. The Linux engine version also changes by distro. The proof from ADR-0015 must run three times.
2. **The curl on Windows and Linux** (`page-transitions`, The curl). The finger-tracked shader at display rate has no WinUI or GTK4 precedent in this repo. GTK4 lost its shader API. The path is an app-owned GL context, measured on Wayland and on X11. macOS can reuse the Metal shader.
3. **Credential storage on Linux** (`sources`, Credential storage). Secret Service may not run on Hyprland or minimal installs. The rule "secrets only in the platform secure store" then forbids saving a password. The app holds it in memory for the session, the source works, and the next launch asks again. Flatpak adds the secret portal.
4. **PDF parity on Windows and Linux** (`ebook-reader`, PDF rendering). There is no PDFKit. `Windows.Data.Pdf` has no text layer. PDFium or poppler in the core must match the same aspect ratio, fit, geometry in PDF points, selection and search on three desktops.
5. **Folder access under sandboxes** (`local-library`, Folder libraries). macOS App Sandbox needs security-scoped bookmarks (the current code lacks the option). Flatpak needs the document portal. Both change what "access is revoked" means and how watching works.

Also watch: HEIC and AVIF page decoding on Windows and Linux, and Orca and UI Automation quality for the Accessibility requirement.

## 8. Open questions for the lead

1. Chrome accent: keep the single StoryArc brand colour, or follow the OS accent colour? The spec Dynamic colour is silent for desktops.
2. Edge click zones: off by default on desktop? The spec Turn triggers says they are on until a reader says otherwise.
3. Should the shared app-shell code move into a package for macOS and iOS? It needs a change under `apps/ios`.
4. Does the Linux floor (GTK 4.14, libadwaita 1.5) offer the accent colour? `AdwAboutDialog` arrived in libadwaita 1.5. The system accent API is, I believe, 1.6. Not checked in this audit. Research item.
5. Which Rust crate opens SMB 3 with encryption for Windows and Linux? Answered by ADR-0018: the in-app `smb` crate on both, not the OS client.
