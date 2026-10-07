## Context

ADR-0004 documented a desktop strategy and told the project to build nothing until both mobile apps
shipped 1.0. On 2026-10-07 the owner decided that desktop starts now. ADR-0018 supersedes ADR-0004's
timing and settles its open stack questions. This file turns ADR-0018 into a design: what each desktop
is made of, where each piece lives, and what is still unknown.

Evidence behind it, all dated 2026-10-07:

- `docs/delivery/desktop-parity-2026-10-07.md`: every requirement of the 17 main specs and of the changes in
  flight, classified per desktop. 95 main requirements: 60 to 64 inherited, 25 to 27 read differently, 4 to 6
  partial, 2 dropped.
- `docs/delivery/desktop-research-windows-2026-10-07.md`: Windows, the Rust-to-C# seam, the EPUB renderer, PDF,
  SMB, RAR.
- `docs/delivery/desktop-research-linux-macos-2026-10-07.md`: Linux floors and compositors, macOS sandbox.
- Per-platform designs: `docs/designs/desktop/macos.md`, `windows.md`, `linux.md`.

Confidence labels follow ADR-0005. **Known**: read in vendor text, source or a package index. **Reported**:
a credible secondary source. **Inferred**: reasoned from Known facts and not run. **Assumed**: nobody checked.
Nothing here is Proven. No spike has run on a desktop.

One decision is already in the code and needs no work: `apps/ios/Packages/StoryArcKit/Package.swift` declares
`.macOS(.v26)`, and the iOS CI job tests the package with `-destination 'platform=macOS'`. All 12 StoryArcKit
targets compile for macOS today (the audit ran `swift build`).

## Goals / Non-Goals

**Goals**

- A native reader on macOS, Windows and Linux that meets the `desktop-experience` spec and every other spec
  through the readings the audit records.
- No change to `apps/ios`, `apps/android` or their CI.
- One shared, interface-free Rust core for Windows and Linux. macOS reuses StoryArcKit.
- Waves that build in parallel lanes on disjoint files, test first.

**Non-Goals**

- No feature in wave 0. The base builds and reads nothing.
- No shared interface layer, no web view outside EPUB reflow, no Electron-style shell.
- No Rust rewrite of StoryArcKit. macOS keeps its Swift logic.
- No signed or published build in this change. See Open Questions.

## Decisions

### D1 to D11 in one table

| ID | Decision | Where it is argued |
| --- | --- | --- |
| D1 | Desktop starts now (owner, 2026-10-07). ADR-0018 supersedes ADR-0004's timing. | ADR-0018 |
| D2 | macOS: native SwiftUI app, own XcodeGen project in `apps/desktop-macos/`, StoryArcKit by path, macOS 26 floor, App Sandbox on, not Mac Catalyst. | Decision 2 below |
| D3 | Windows: WinUI 3 on Windows App SDK 2.5.1, C#, .NET 10 LTS, Windows 11 24H2 floor. | Decision 3 |
| D4 | Linux: GTK4 and libadwaita in Rust, GTK 4.14 and libadwaita 1.5 floor, Wayland first, Flatpak first. | Decision 4 |
| D5 | One Rust core for Windows and Linux (`storyarc-core`), a C ABI crate for C# (`storyarc-ffi`). | Decision 5 |
| D6 | Desktop EPUB: one pinned Readium ts-toolkit bundle in each system web view. | Decision 6 |
| D7 | Behaviour goes in the new capability `desktop-experience`, ADDED requirements only. | Spec; this change |
| D8 | One umbrella change, `desktop-clients`. Wave 0 is preparation. | `tasks.md` |
| D9 | Mobile-only features drop on desktop. Cellular becomes metered. | Decision 9 |
| D10 | Desktop-new features: the audit's ACCEPT list ships, its LATER list is specified and scheduled late. | Decision 10 |
| D11 | Desktop work stays in new directories and path-filtered CI. | Decision 11 |

### Decision 1. Repository layout

```
Cargo.toml                           workspace root, members below
apps/desktop-core/storyarc-core/     no UI, ever; builds on Windows, Linux and macOS hosts
apps/desktop-core/storyarc-ffi/      cdylib storyarc_ffi, C ABI over the core
apps/desktop-linux/                  package storyarc-linux, binary storyarc
apps/desktop-windows/                src/StoryArc.Windows, src/StoryArc.Interop, tests/StoryArc.Interop.Tests, build.ps1,
                                     global.json, Directory.Build.props, StoryArc.Windows.slnx
apps/desktop-macos/                  project.yml, project StoryArcMac.xcodeproj, scheme StoryArc
apps/desktop-web/epub/               the one EPUB renderer bundle (see Decision 6)
.github/workflows/desktop-{macos,linux,windows}.yml
```

The Rust workspace is at the repository root so `cargo` finds it from any directory. `apps/desktop-web/epub`
is a plain JavaScript project with a lockfile, an exact-version pin and a built file, not a framework app.
Its directory name is part of the plan and not of the audit; an agent that finds a better home moves it in
task 1.9 and records the move.

Commands, fixed for this change:

| Purpose | Command |
| --- | --- |
| Build macOS | `pnpm build:macos` (`xcodegen generate` then `xcodebuild build -scheme StoryArc -destination 'platform=macOS'`) |
| Test the core | `pnpm test:desktop:core` (`cargo test -p storyarc-core -p storyarc-ffi`) |
| Build Linux | `pnpm build:linux` (`cargo build -p storyarc-linux`) |
| Run Linux | `cargo run -p storyarc-linux` |
| Test the seam | `pnpm test:desktop:interop` (`cargo build -p storyarc-ffi` then `dotnet test apps/desktop-windows/tests/StoryArc.Interop.Tests`) |
| Build Windows | `pwsh apps/desktop-windows/build.ps1` |
| Linux on other distros | `apps/desktop-linux/scripts/container-build.sh <ubuntu-24.04\|arch\|manjaro\|fedora>` |
| Flatpak | `flatpak-builder --user --install --force-clean build-flatpak apps/desktop-linux/build-aux/com.mecedric.StoryArc.json` |

### Decision 2. macOS: SwiftUI over StoryArcKit

**Architecture.** A new XcodeGen project builds the app target. It depends on StoryArcKit through a local
package reference to `apps/ios/Packages/StoryArcKit`. No file under `apps/ios` changes. The Mac shell rebuilds
what `apps/ios/App` does (about 3.4k lines in 22 files: the audit lists each piece and what it becomes).

**Shape on macOS 26 (Known, Apple documentation).**

- Library: one `Window` scene with a `NavigationSplitView` sidebar and an optional `inspector`.
- Readers: `WindowGroup(for:)` with a `Codable` and `Hashable` reader target, opened through `openWindow(value:)`.
  Window restoration comes from SwiftUI (restore behaviour: Inferred).
- Menus: `commands` with `CommandGroup`. Page keys with `keyboardShortcut` and `onKeyPress`.
- Preferences: the `Settings` scene.
- Files: `fileImporter` for folders. `onDrop` and `onOpenURL` for dropped files. Document types and exported UTIs
  in the app's `Info.plist`, carried over from the iOS plist (keys that start `UI` are dropped).
- Full screen: `windowFullScreenBehavior`. Dock menu: an `NSApplicationDelegate` Dock menu.
- Glass: Liquid Glass through `glassEffect` on chrome only, never on the artwork.

**What StoryArcKit gives and what a Mac must add** (the audit's reuse map, section 5, is the source):

| Piece | State on a Mac | Work |
| --- | --- | --- |
| `StoryArcCore`, `DesignSystem`, `Catalogue`, `Kavita`, `Smb` | Compiles and runs | None |
| `Formats` | Compiles | None. Two `#if os(iOS)` file-protection guards are harmless. |
| `Persistence` | Compiles | `FolderBookmarks` must create and resolve with `.withSecurityScope`. `CredentialStore` must set `kSecUseDataProtectionKeychain`. Both live in `apps/ios`, so the Mac project wraps them and a later task moves the change into the package. |
| `Playback` | Compiles | `NowPlaying` and the audio session sit inside `#if os(iOS)`. Split the guard so a Mac gets Now Playing and remote commands (media keys) and skips `AVAudioSession`. |
| `ReaderFeature` | Compiles, partly inert | `ZoomablePage`, `PageScrollView`, the PDF overlay and text model, `ReaderSystemChrome` and `FrameProbe` do nothing on a Mac. Write Mac versions in the Mac target first. |
| `LibraryFeature` | Compiles | Mac layout and chrome. `CoverSearchHandoff` opens the default browser. `EntryPoster` needs an `NSImage` path. |
| `SettingsFeature` | Compiles | The app icon chooser is dropped. |
| `StoryArcEpub` | Does not build for macOS (iOS only, Readium Swift) | Not used. A new Mac target hosts the JavaScript renderer. |

Changes that need a file under `apps/ios` or `apps/ios/Packages` are listed as *parent* tasks in `tasks.md`
and wait for the iOS owner. The Mac lane works around each of them inside `apps/desktop-macos` first.

**Sandbox.** Entitlements to start from (Inferred): `com.apple.security.app-sandbox`,
`com.apple.security.files.user-selected.read-write`, `com.apple.security.files.bookmarks.app-scope`,
`com.apple.security.network.client`. Read-write is needed because the diagnostic export writes a file the reader names
outside the container (`desktop-experience`, diagnostics). The keychain access group is not in this list yet: it needs a
team ID, and task 1.13 spikes whether an ad-hoc build can use the data-protection keychain at all. Result: pending task
1.13. If the call fails with `errSecMissingEntitlement` (-34018), ad-hoc builds use the login keychain and the
data-protection path waits for task 6.8. Add the audio-input entitlement only if a spec ever needs it. SMB uses the
existing `Smb` package (SMBClient 0.3.1, pure Swift), which needs only the network entitlement. The app does not
mount shares through `NetFS`.

**EPUB.** A new Swift target, `StoryArcEpubMac`, hosts `WKWebView`, serves archive resources through a
`WKURLSchemeHandler` on a per-publication scheme, and loads the shared bundle of Decision 6. A `WKContentRuleList`
denies everything outside the app scheme (the same technique ADR-0015 measured on iOS), and every response
carries a Content-Security-Policy header.

**PDF.** PDFKit through StoryArcKit, as on iOS. **Archives and covers.** StoryArcKit's `Formats`. **Curl.**
The Metal shader of `PageCurl.metal` is reused. `swift build` does not compile `.metal` files and a host run
shows a warning that is correct (`AGENTS.md` section 3b), so only an `xcodebuild` build proves the shader.

**Accessibility.** SwiftUI controls carry VoiceOver names and roles. Custom readers (page surface, spread, zoom)
need explicit labels. macOS has no system text scaling, so the reader's own size control meets the largest-text
scenarios.

**Distribution.** Local run is ad hoc signed (`CODE_SIGN_IDENTITY=-`). A downloaded build is quarantined and
Gatekeeper blocks it unless notarised (Reported). Notarisation and the Mac App Store need the 99 USD Apple Developer
Program and are the owner's step (Open Questions).

### Decision 3. Windows: WinUI 3 in C# over the Rust core

**Stack (all Known unless marked).**

| Part | Choice | Version |
| --- | --- | --- |
| Toolkit | WinUI 3 on Windows App SDK | `Microsoft.WindowsAppSDK` 2.5.1 (stable, 2026-09-16). 1.8 left servicing on 2026-09-24. |
| Runtime | .NET 10 LTS | SDK 10.0.401 on the CI image. End of life 2028-11-14. |
| Project shape | Single-project packaged app | TFM `net10.0-windows10.0.26100.0`, platforms x64 and ARM64 |
| Floor | Windows 11 24H2 (build 26100) | `TargetPlatformMinVersion` and manifest `MinVersion` `10.0.26100.0` (Medium confidence: CI cannot test a lower floor) |
| Shell controls | `TitleBar`, `SystemBackdrop` (Mica or Acrylic), `NavigationView`, `TabView` | In the stable line. Chrome only. |
| Curl | Direct3D 11 swap chain in a `SwapChainPanel`, the ADR-0009 shader as HLSL | D3D11 wrapper: Vortice.Direct3D11 3.8.3 (Known), or TerraFX (Assumed) |
| Interop | `StoryArc.Interop`, plain `net10.0`, runs on any host with the .NET 10 SDK | Inferred, not run: no .NET SDK on the research machine |

**Why no Win2D.** Win2D 1.4.0 depends on Windows App SDK 1.8 or newer with no upper bound, yet no source says
its native part activates on 2.x. Treat it as unproven. The curl must hold the monitor rate on a 120 Hz display,
so the swap chain owns its own render thread and takes input through `CreateCoreIndependentInputSource`.

**Project structure.**

```
apps/desktop-windows/
  build.ps1
  global.json                        pins the SDK
  Directory.Build.props              shared build properties
  StoryArc.Windows.slnx              the solution
  src/StoryArc.Windows/              WinUI 3 app: windows, pages, view models, resources (.resw)
  src/StoryArc.Interop/              net10.0: NativeMethods.g.cs (generated), SafeHandle wrappers, models (System.Text.Json source generation)
  tests/StoryArc.Interop.Tests/      runs on windows, ubuntu and macOS runners
```

The `StoryArc.Windows` project builds the Rust library with one MSBuild `Exec` target before compiling:
`cargo build -p storyarc-ffi --target x86_64-pc-windows-msvc` or `aarch64-pc-windows-msvc`, then copies
`storyarc_ffi.dll` beside the executable. No maintained NuGet package does this (Known). `SkipCargo` skips it.

**Windows without Visual Studio.** The 2026 templates and the `winapp` CLI build with the .NET SDK. Microsoft's
WinUI CI page still uses Visual Studio's `msbuild`. Use `dotnet build` for compile checks and `msbuild` for the
MSIX step until a spike shows `dotnet` is enough (Medium confidence). Whether single-project MSIX produces a
bundle is a documented conflict between two Microsoft pages: a spike resolves it.

**Accessibility.** WinUI controls expose UI Automation. Custom surfaces (page, spread, zoom) need automation peers
with names, roles and values. Narrator must announce a page change. The system text scale changes the XAML text
size; `NavigationView` and the dialogs must be checked at the largest scale.

**Distribution.** Free Microsoft Store registration for individuals and companies. The Store signs the MSIX.
It is the canonical channel (High confidence). Dev builds use `winapp run` (Developer Mode) or an unpackaged
`dotnet publish`. A sideloaded MSIX needs a trusted certificate. Azure Artifact Signing is closed to individuals
outside the US and Canada. A full-trust packaged app declares `runFullTrust` and Store review may ask for a
justification (Reported): a Store dry run in wave 6 records it.

### Decision 4. Linux: GTK4 and libadwaita in Rust

**Stack (Known, read 2026-10-07).**

| Part | Choice | Cargo feature |
| --- | --- | --- |
| GTK 4 | `gtk4` 0.11.5 | `v4_14` |
| libadwaita | `libadwaita` 0.9.2 | `v1_5` |
| Web view for EPUB | `webkit6` 0.6.1 (WebKitGTK 6.0), pinned exactly: young major | `v2_44` |
| Toolchain | Rust 1.92 or newer, from `rustup`, set by `rust-version` in the root `Cargo.toml` | n/a |

Rule: never enable a feature above the floor. One source tree serves the Flatpak and every distro build.

**Floor.** GTK 4.14 and libadwaita 1.5 (Ubuntu 24.04 and Pop!_OS 24.04 ship 4.14.5 and 1.5.0; Pop!_OS is Inferred
from its Ubuntu base). WebKitGTK floor 2.44. Fedora 43 (GTK 4.20, libadwaita 1.8) is the Fedora floor. Every other target is newer. A higher floor drops both.

**Widgets lost at the floor and their substitutes.**

| Lost | Use |
| --- | --- |
| `AdwBottomSheet` (mini player) | `GtkRevealer` or an `AdwOverlaySplitView` bar. A spike judges the feel. |
| `AdwButtonRow` | `AdwActionRow`, activatable |
| `AdwSpinner` | `GtkSpinner` |
| `AdwWrapBox` | `GtkFlowBox` |
| `AdwToggleGroup` | Linked `GtkToggleButton` group |
| `AdwShortcutsDialog` | A custom `AdwDialog` (`GtkShortcutsWindow` is deprecated since 4.17.4) |
| `AdwSidebar` | `AdwNavigationSplitView` with a `GtkListBox` styled `.navigation-sidebar` |
| `AdwMultiLayoutView` | `AdwBreakpoint` setters |

Kept: `AdwNavigationSplitView`, `AdwOverlaySplitView`, `AdwToolbarView`, `AdwBreakpoint`, `AdwDialog`,
`AdwAlertDialog`, `AdwPreferencesDialog`, `AdwAboutDialog`.

**Windows and sessions.**

- One `AdwApplicationWindow` for the library, one per reader. Application id `com.mecedric.StoryArc`, which is also
  the Wayland application id and the class a Hyprland rule matches (class equals id: Inferred).
- Minimum size set through `set_size_request` (360 by 200 or more). libadwaita sets one only from 1.6. A breakpoint
  below about 600 px collapses the split view (600 px: Inferred, a spike confirms).
- GTK saves no session before 4.26, so the app saves window state itself (Known: 4.23.3 deferred it).
- Renderer: leave the choice to GTK. `ngl` is the 4.14 default. `GSK_RENDERER=ngl` is the documented fallback for
  NVIDIA problems (GTK issues 8364 and 6689 are open). The curl runs in a `GtkGLArea`, which works under every
  renderer. It is present on Wayland. It is absent on X11 until spike 1.17 shows it holds the frame budget there (`desktop-experience`, Linux display servers).
- Idle inhibit: `Application::inhibit` with the idle flag. GTK uses `zwp_idle_inhibit_v1` on Wayland, which Hyprland
  and COSMIC implement. The portal path calls `org.gnome.SessionManager` and fails on a bare Hyprland, so the app
  treats a refusal as normal.
- Decorations: Hyprland answers the decoration protocol with server-side mode and draws no title bar. `AdwHeaderBar`
  stays as an ordinary widget. Control and W closes a window. Control and Q quits.

**Portals and services by desktop (Known, from each compositor's portal files).**

| | Hyprland | COSMIC | KDE Plasma | GNOME |
| --- | --- | --- | --- | --- |
| File chooser | none: needs `xdg-desktop-portal-gtk` | `xdg-desktop-portal-cosmic` | `xdg-desktop-portal-kde` | `xdg-desktop-portal-gnome` (Inferred) |
| Dark mode (settings portal) | none: portal-gtk reads GSettings | yes | yes | yes (Inferred) |
| Inhibit portal | none: use the protocol | none: use the protocol | yes | yes (Inferred) |
| Secret Service | user installs a daemon | `oo7-portal` or `gnome-keyring` | KWallet (Reported) | `gnome-keyring` (Reported) |

File access uses `GtkFileDialog`, which goes through the portal. Where no portal exists the app says so once, in grey.

**Accessibility.** GTK 4 exposes AT-SPI to Orca. Custom widgets (page surface, spread, zoom) need accessible roles,
labels and live announcements. High contrast follows the system. The 1.5 floor has no system accent API (libadwaita
accent colour arrived later: Inferred), so the open question on the chrome accent is also constrained by the floor.

**Packaging.**

- Flatpak first. Runtime `org.gnome.Platform` 51 (GTK 4.24.0, libadwaita 1.10.0, WebKitGTK 2.54.1), SDK
  `org.gnome.Sdk`, extension `org.freedesktop.Sdk.Extension.rust-stable`. Crate sources through
  `flatpak-cargo-generator.py Cargo.lock`. A `libarchive` module. PDFium as one archive source with a `sha256`.
  Finish arguments: `--socket=wayland`, `--socket=fallback-x11`, `--share=ipc`, `--device=dri`, `--share=network`,
  `--socket=pulseaudio`, no broad `--filesystem` (Inferred from a Flathub Rust GTK4 app).
- Flathub policy risk: since 2026-09-04 Flathub requires disclosure of AI-generated code, forbids AI-generated content
  in the manifest it accepts, and a human must submit it. A reviewer may still say no. The repository's own manifest
  may be AI-assisted. The Flathub copy may not. The owner asks Flathub in writing before packaging work starts.
- Source builds are documented per distro (apt, pacman, dnf) in the README, with the dependency table in the research
  file. Distro proof runs in containers through `container-build.sh`. Docker 29.5.3 runs on the lead's Mac.
- AUR package: shape in the research file. AppImage is not shipped (WebKitGTK helper processes do not fit).

### Decision 5. The shared Rust core and its seam

**Crates.**

| Crate | Kind | Holds |
| --- | --- | --- |
| `storyarc-core` | library, no UI, builds on every host | Everything non-visual for Windows and Linux |
| `storyarc-ffi` | `cdylib` named `storyarc_ffi` | The C ABI over the core. The wave 0 contract is one function. |
| `storyarc-linux` | binary `storyarc` | GTK interface. Uses `storyarc-core` directly, with no C ABI |

`storyarc-ffi` exports `storyarc_core_version()`, which returns a static NUL-terminated `const char *` the caller
never frees. Everything else is added by later waves under the ABI rules below.

**What the core holds, in build order.** (1) The format layer, mirrored from StoryArcKit `Formats` and checked
against `packages/test-fixtures`: own ZIP reader, own TAR reader, RAR through libarchive, page ordering, metadata,
covers. (2) Page decoding and the image adjustments. (3) The ranged-read abstraction (`RandomAccessSource`,
ADR-0008). (4) Sources: local folders, SMB, OPDS, Kavita. (5) The progress store, merge and sync. (6) Downloads and
the queue. (7) Secrets behind a `SecretStore` trait. (8) The EPUB manifest and positions builder. (9) PDF. (10)
Collation and formatting (ICU4X, Assumed).

**Crates the core depends on.**

| Need | Choice | Version | Label |
| --- | --- | --- | --- |
| RAR | libarchive 3.8.9, vendored from `third_party/libarchive`, compiled by the `cc` crate from `build.rs`, about ten hand-written `extern "C"` declarations | `cc` 1.6.0 | Known (versions), Inferred (the MSVC build) |
| PDF | `pdfium-render` with a bundled PDFium from `pdfium-binaries` | 0.9.4, binary `chromium/7881` | Known |
| SMB | `smb` first, `smb2` as the swap-in, behind `RandomAccessSource` | `smb` 0.12.x, `smb2` 0.27.x | Known |
| Secrets, Windows | `keyring` with `windows-native-keyring-store` | 4.2.0 and 1.1.0 | Known |
| Secrets, Linux | `oo7` | 0.6.0 | Known |
| Local store | SQLite through `rusqlite` | Assumed, pin in task 2.1 | Assumed |
| HTTP, TLS, pinning | `reqwest` with `rustls` | Assumed, pin in task 3.4 | Assumed |
| XML | `quick-xml` | Assumed | Assumed |
| Image decode | `image`, `libheif` and `dav1d` bindings | Assumed | Assumed |
| Locale | ICU4X (`icu` crate) | Assumed | Assumed |

**The seam to C#.** A hand-designed C ABI (Medium confidence):

1. Opaque handles (`StoryArcHandle *`), wrapped on the C# side in `SafeHandle` subclasses.
2. Byte buffers: caller-owned, or Rust-owned and freed by one `storyarc_buffer_free`.
3. Records as UTF-8 JSON, parsed in C# with `System.Text.Json` source generation. No reflection, so trimming works.
4. Integer error codes plus `storyarc_last_error` for the message.
5. `storyarc_cancel(token)` for cancellation. C# maps a `CancellationToken` onto it and runs blocking calls on `Task.Run`.
6. `csbindgen` 1.9.8 writes `NativeMethods.g.cs` from the Rust source in `build.rs`. Callbacks are `[UnmanagedCallersOnly]`
   static methods.

uniffi is rejected for now: `uniffi-bindgen-cs` 0.11.0 targets uniffi 0.31 while 0.32.2 is current, and it has open
async-callback and native-AOT issues. Revisit above about 40 functions.

**Mirror, not rewrite.** The core is a second implementation of logic that Swift and Kotlin already hold. The shared
corpus in `packages/test-fixtures` and the specs are the control, as ADR-0001 states. Every core module's first test
reads that corpus and asserts byte-identical or value-identical output.

**Async runtime.** `oo7` needs one. Decide one runtime for the core and the Linux app before the first secret is stored
(Open Questions).

### Decision 5b. Audio and speech engines on Windows and Linux

The research did not cover them. Mobile uses the platform players and speech engines, and the `audio-playback`,
`ebook-reader` (Reading aloud) and `read-aloud-beyond-the-reader` requirements need an engine on each desktop. macOS uses
AVFoundation and AVSpeechSynthesizer through StoryArcKit `Playback`. For Windows the plan is the WinRT `MediaPlayer` and
`SpeechSynthesizer` called from C# (Assumed). For Linux the plan is GStreamer through `gstreamer-rs` for audio and
speech-dispatcher for speech (Assumed). Chapter parsing and the progress model stay in the core. A spike in wave 4 task
4.12 confirms each engine before any UI depends on it. Where no speech engine exists, the control is absent (spec: Media
keys and system media controls).

### Decision 6. One EPUB renderer in three web views

**Choice (Medium confidence).** `@readium/navigator` 2.11.1 and `@readium/shared` 2.7.0 from `readium/ts-toolkit`
(BSD-3-Clause), pinned to exact versions, built with Vite into one JavaScript file whose digest is recorded in a
`pin.json`, the way libarchive's is. foliate-js is rejected: it uses CFI locators and its README says its API may
break at any time.

**What the host owes the renderer.** The toolkit has no EPUB container parser. The host supplies a Readium Web
Publication Manifest (reading order, table of contents, metadata, layout, reading progression) and a positions list.
The core builds both from the OPF (`storyarc-core`; macOS builds them in `StoryArcEpubMac` from Swift, or calls a
shared builder: see Open Questions). Position numbers must match iOS and Android for the same book. swift-toolkit's
`EPUBPositionsService` uses `ceil(archiveEntryLength / 1024)`, minimum 1, where the length is the ZIP entry's compressed
size (Known, source read). The core's ZIP reader already exposes the compressed size. A shared-corpus test asserts equal
positions on all platforms.

**Serving resources and denying egress.** ADR-0015 binds on every desktop.

| Web view | Serve archive bytes | Deny everything else |
| --- | --- | --- |
| `WKWebView` (macOS) | `WKURLSchemeHandler` on a per-publication scheme | `WKContentRuleList` deny-all except the scheme (Known, measured on iOS) plus a CSP header |
| WebView2 (Windows) | Custom scheme registered through `CoreWebView2CustomSchemeRegistration` on a custom environment, answered in `WebResourceRequested` (virtual-host mapping serves folders only, so it cannot serve archive bytes) | CSP header on every response (`default-src 'none'`, `connect-src 'none'`), `NavigationStarting` cancels non-app URLs, a `*` filter answers 403 to the rest. WebSockets may bypass the event, so the CSP carries that case (Inferred) |
| WebKitGTK (Linux) | `WebContext::register_uri_scheme`, answering through `URISchemeRequest` with a stream and a CSP header | `WebKitUserContentFilterStore` with the same JSON rule list as iOS (Inferred) plus the CSP header |

WebKitGTK range-request behaviour and whether subresources of a page loaded through the scheme use the handler are not
documented: a spike decides. The eight-vector egress page from ADR-0015 runs once per web view and must show zero
arrivals.

**Accessibility consequence.** A web view's content is exposed to each system's screen reader through the web engine.
The renderer must keep the book's own markup and language. Focus handoff between the chrome and the web content is part
of the Full keyboard navigation requirement and needs a test per desktop.

**Kavita.** Kavita stores its own page number and a scroll identifier, not a Readium locator (Reported, Inferred).
The app maps `position` and `totalProgression` to Kavita's fields the same way on every platform. ADR-0006 keeps the
locator local.

### Decision 7. PDF, archives, SMB, secrets

- **PDF, Windows and Linux.** `pdfium-render` 0.9.4 with a bundled PDFium from `bblanchon/pdfium-binaries`,
  pinned to `chromium/7881`, sha256 in a `pin.json`. `load_pdf_from_reader` takes a `Read + Seek`, so a
  `RandomAccessSource` adapter gives ranged reads from SMB and HTTP and the first page of a large file shows without a
  full transfer. PDFium is not thread safe: one dedicated PDF thread. It is the first bundled PDF engine in the project
  and parses untrusted input, so `SECURITY.md` adds PDF to its attack-surface list. `Windows.Data.Pdf` has no text,
  search or outline, so it cannot meet `ebook-reader` and is rejected. macOS keeps PDFKit.
- **RAR.** The same vendored libarchive sources compile on three build systems (SwiftPM, CMake, `cc`). `pnpm libarchive:pin`
  keeps one copy. The vendored `config.h` stays untouched, because iOS and Android compile it (D11). Linux and MSVC each get
  a desktop-only config header under `apps/desktop-core/storyarc-core/libarchive/`, which `build.rs` puts ahead of the
  vendored include path (Inferred). **MSVC also needs the Windows BCrypt code paths**: the biggest risk of this item (Inferred). The first spike builds x64 and ARM64 and runs the RAR corpus.
- **SMB.** An in-app client, not the OS redirector. Reasons (Known): both crates report the negotiated dialect and
  encryption, so the "Encrypted transport" scenario becomes meetable on desktop (neither mobile client can);
  Windows 11 24H2 requires signing by default, which blocks guest shares; UNC I/O can block in the kernel and cannot meet
  the two-second indicator rule without a watchdog; one code path serves Windows and Linux; no `cifs` mounts or GVfs
  are needed in a Flatpak. An SMB 1 negotiate probe on failure classifies "SMB 1 only" and names the server setting
  (Inferred, since neither crate speaks SMB 1). Both crates are pre-1.0 with one maintainer: the trait keeps the swap cheap.
  ADR-0010's rejection of libsmb2 over LGPL stands.
- **Secrets.** `SecretStore` trait in the core. Windows: `keyring` with `windows-native-keyring-store`, bytes API,
  `CRED_PERSIST_LOCAL_MACHINE` set explicitly (Inferred: the default is checked in the spike), each blob under 2560
  bytes, one thread per entry behind a mutex. Linux: `oo7`, which uses Secret Service on the host and an encrypted file
  keyring keyed through the Secret portal in a sandbox. No daemon: nothing is written, the secret stays in memory for the
  session, and one grey line names the fix. macOS: the data-protection keychain through StoryArcKit.

### Decision 8. Storage locations and sandbox consequences

| | Data | Cache and downloads | Bookmarks and access |
| --- | --- | --- | --- |
| macOS | App container `Application Support` | Container `Caches` for covers. Downloads in `Application Support` with the Time Machine exclusion flag | Security-scoped bookmarks, app scope, created and resolved with `.withSecurityScope` |
| Windows | `%LOCALAPPDATA%` of the package (MSIX redirects it) | Same, never `%APPDATA%` (roaming) | Folder access by path. Access can be withdrawn by a volume or a permission |
| Linux | `$XDG_DATA_HOME/com.mecedric.StoryArc` (Flatpak: `~/.var/app/com.mecedric.StoryArc`) | `$XDG_CACHE_HOME` for covers | The document portal in Flatpak. Direct paths in a source build |

(Paths: Assumed, confirmed by task 2.4.) Windows and Linux drop the backup-exclusion flag and rely on non-roaming
locations (`offline-downloads`, Storage management reads partly). The phrase "access revoked" means a withdrawn
bookmark on macOS, a revoked portal grant on Linux Flatpak, and a missing or denied path on Windows. The spec scenario
is the same for all three.

### Decision 9. Mobile-only features drop, and the readings

The audit's classification stands. Dropped: the app icon chooser (`native-experience`, `settings-and-about`), CarPlay and
Android Auto, volume-key page turns, orientation lock, brightness, haptics (a no-op), Split View, Slide Over and
foldables, Continuity on Windows and Linux. Cellular reads as a metered connection:

| System | Source of "metered" |
| --- | --- |
| macOS | Low Data Mode and the constrained or expensive path flags (Known API names, the `Network` framework: Assumed for the exact check) |
| Windows | `NetworkCostType` from the connection profile (Assumed) |
| Linux | NetworkManager's metered property, over D-Bus (Assumed) |

Where the system does not say, the connection is treated as not metered (spec).

### Decision 10. Desktop-new features

ACCEPT (shipped in waves 1 to 4): menu bar and shortcuts, two-page spreads, full screen, multiple reader windows,
file associations and drag and drop, pointer reading, live folder watching, media keys and system media controls,
recent items in the launcher, tiling-friendly windows with a stable Wayland identity. LATER (specified now, built in
wave 5 or later): thumbnails in the file manager, Handoff, Spotlight, the `storyarc://` link. REJECTED (Non-goals):
widgets, tray, background sync, notifications, command palette, tabs, printing, global hotkeys.

Per-system hooks for the ACCEPT list:

| Feature | macOS | Windows | Linux |
| --- | --- | --- | --- |
| Media controls | `MPNowPlayingInfoCenter` and remote commands (Known API) | System Media Transport Controls (Assumed) | MPRIS over D-Bus (Assumed) |
| Recent items | Dock menu | Jump List (`ICustomDestinationList`, Assumed) | `GtkRecentManager`, plus the static `.desktop` actions Continue Reading, Library and Downloads. A `.desktop` file cannot name a publication and a Flatpak cannot rewrite its exported one. |
| File associations | Info.plist document types and UTIs | ProgID registration in the MSIX manifest (Assumed) | MIME types in the `.desktop` file |
| Live watching | FSEvents | `ReadDirectoryChangesW` | `inotify` on a path the app owns, with its watch limit. A folder granted through the document portal gets no native events, so it uses polled reconciliation at an interval of 10 seconds or less. |
| Sleep inhibit | IOKit power assertion | `SetThreadExecutionState` | `zwp_idle_inhibit_v1`, portal second |
| Thumbnails (LATER) | Quick Look generator | Shell extension: cannot run as managed .NET, needs a native shim | Thumbnailer CLI with a `.thumbnailer` file, for source and AUR builds only. A Flatpak does not export a thumbnailer to the host file manager, and Flatpak is the first package, so the Flatpak build shows no cover thumbnails (Inferred). Research this before task 5.5. |

### Decision 11. CI

Three workflows, each triggered only by its own paths and by the shared core, so mobile CI is unaffected.

| Workflow | Runner | Jobs |
| --- | --- | --- |
| `desktop-macos.yml` | `macos-26` (arm64, Xcode 26.6 default, Known) | Print `xcodebuild -version`, `pnpm build:macos`, and the StoryArcKit macOS destination already run by `ios.yml`. The workflow has read-only `contents` permission. `.swiftlint.yml` includes `apps/desktop-macos` (a parent edit). A change under `apps/ios/Packages/StoryArcKit/**` runs this build on purpose. |
| `desktop-linux.yml` | `ubuntu-24.04` (matches the floor) | A lint job (`cargo fmt --all --check`, clippy with `-D warnings` on the two core crates); a container matrix runs `container-build.sh` for Ubuntu 24.04, Arch, Manjaro and Fedora (distro dev packages, `cargo test`, `cargo build`, the data file checks). The Ubuntu 24.04 row passes `--clippy`, so `storyarc-linux` is linted with `-D warnings` there only. |
| `desktop-windows.yml` | `windows-2025-vs2026` (pinned: `windows-latest` maps to it, but an older readme survives in the runner-images repo) | `pwsh build.ps1` for x64, plus an interop job (`cargo build -p storyarc-ffi`, `dotnet test`) on each of `ubuntu-24.04` and `macos-26`. The ARM64 build joins CI with tasks 1.18 and 1.22, because the base proves only the x64 build in CI. |

`windows-2025-vs2026` carries Visual Studio 2026 18.10, .NET SDK 10.0.401, Windows SDK 26100, Rust 1.98.1 and ARM64
tools (Known). Nothing device-driven runs in CI: captures, accessibility walks and the Hyprland, KDE, GNOME and COSMIC
matrix are manual, as `AGENTS.md` section 6 already states for mobile.

### Decision 12. Localisation

The four-language string source must feed three formats: `.xcstrings` (macOS, already the iOS source), `.resw`
(Windows) and gettext `.po` (Linux). A generator reads the single source and writes the three, and a drift check joins
`pnpm lint`. macOS follows a per-app language. Windows and Linux follow the system list. Every language is tested with
the pseudo-locale walk on each desktop. The generator and its source are a wave 2 task: the exact source file is Assumed
until it is read in task 2.8.

## Where each desktop reading lands

| Reading (audit row) | Design answer |
| --- | --- |
| Folder libraries (local-library) | Chooser, then a stored grant: security-scoped bookmark, document portal, path. Decision 8 |
| Watched changes | Native watcher per system, rescan at launch and focus, a stated fallback. Decision 10 |
| Credential storage (sources) | `SecretStore`. Decision 7 |
| Screen stays awake (comic-reader) | Sleep inhibit per system. Decision 10 |
| Network policy, streaming reads | Metered flag. Decision 9 |
| Queue management, downloads | Downloads while the app runs, pause at quit, resume at launch. Spec: No presence when closed |
| Library sync timing | At start and quit. Spec: Sync when the app runs |
| Ebook rendering, navigation | The pinned bundle in a web view. Decision 6 |
| PDF rendering | PDFKit on macOS, PDFium on Windows and Linux. Decision 7 |
| Reading aloud and media | System speech on each OS and system media controls. Decision 10 |
| Accessibility | Per system, in each platform section |
| Page transitions, curl | Metal on macOS, D3D11 on Windows, `GtkGLArea` on Linux Wayland. Decisions 2 to 4 |
| Discovery (network-share) | Bonjour on macOS, avahi on Linux (Assumed), manual entry on Windows. Spec: Finding a network share |
| About and licences | Generated notices must include Rust crates, .NET packages, PDFium and libarchive. Wave 6 task |

## Risks / Trade-offs

- **Three implementations of the format layer.** Swift, Kotlin and Rust can drift. The shared corpus is the control and
  the first test of each core module. Cost accepted in ADR-0018.
- **The curl on Windows and Linux has no precedent in this repository.** Two spikes measure it first: monitor-rate
  presents on a 120 Hz screen on Windows, a `GtkGLArea` on Wayland. If either fails, that desktop ships without the curl
  and the settings say so, as they would on X11 until the curl holds the frame budget there.
- **Web-view egress.** Three web views filter requests three ways, and the Linux engine version changes by distro. The
  eight-vector proof runs once per web view and again on the oldest WebKitGTK the floor allows.
- **Linux secret store.** Hyprland and minimal installs ship none. The app degrades to a session-only secret and a grey
  line, which weakens the experience but never the rule.
- **PDF on Windows and Linux.** One bundled engine for untrusted input, with a thread rule and a pin. Parity with
  PDFKit on fit, geometry in PDF points, selection and search is a test task.
- **Folder access under sandboxes.** macOS, Flatpak and Windows each lose access in a different way. One scenario covers
  all three and each needs its own test.
- **Flathub may refuse the app.** The fallback is source builds, an AUR package and container-proven distro builds.
- **Windows 11 only.** Windows 10 users are not served. The floor reopens if users report 23H2 devices (cost: an older VM
  and the Mica fallback).
- **Pre-1.0 dependencies.** `smb`, `smb2`, `webkit6` 0.6 and `oo7` are young. Each sits behind a trait or an exact pin.
- **Duplicated shell code on macOS.** About 3.4k lines exist twice until a shared `AppSupport` package moves under
  `apps/ios`. That move is a later parent task.
- **Mobile builds are still moving.** The parity audit scored mobile state from `STATUS.md`. Verify a row against the
  source before building from it (see the memory note on stale rows).

## Migration Plan

Waves, each ending when its tasks are ticked and its gates pass:

0. Preparation (this wave): research, skills, ADR-0018, this change, designs, base scaffolds, CI, README.
1. Foundations: macOS shell boots with a library window and the two sandbox fixes; the Rust core's format layer passes
   the fixture corpus; the EPUB bundle builds and is pinned; Linux and Windows shells open a window.
2. Open and read a comic: folder sources, file association and drop, the comic reader with keys, pointer, zoom and
   spreads, on all three desktops.
3. Sources and sync: SMB, OPDS, Kavita, secrets, the progress store, downloads.
4. EPUB and PDF, reading aloud and media keys.
5. Polish and the LATER list: full screen, recent items, thumbnails, Handoff, Spotlight, the link scheme.
6. Release readiness: accessibility walks, egress proofs, packaging, signing, licences, captures.

Nothing migrates for a reader: no desktop app exists today. Rollback is deletion of the new directories and workflows.

## Open Questions

1. **Chrome accent.** Does the desktop chrome keep the single StoryArc brand colour or follow the system accent? The spec
   marks it. The Linux floor may not offer the accent API at all. Owner decision.
2. **Edge click zones.** The spec carries a marker. Off by default is the audit's recommendation (the zones conflict with
   text selection and window drag). The mobile Turn triggers requirement has them on. When the owner answers, the spec
   states that the answer overrides Turn triggers on a desktop. Owner confirms.
3. **Cold-launch budget on a desktop.** The spec marks it. Mobile uses 1.5 seconds on a mid-range device. A desktop number
   needs a measurement from the first running shell.
4. **Shared shell code.** Move the iOS composition code into a package that both iOS and macOS use? It needs a change under
   `apps/ios`. Wave 5 parent task.
5. **Async runtime** for the core and `oo7` (tokio is the `oo7` default, `async-io` is the alternative).
6. **Who builds the EPUB manifest and positions on macOS?** Swift in `StoryArcEpubMac`, or the Rust core through a static
   library. A Swift builder duplicates logic. A Rust static library puts cargo inside the Xcode build, which ADR-0001
   avoided. Decide in wave 1 with a spike.
7. **Flathub.** Does the reviewer accept a project that discloses AI assistance? Owner asks in writing.
8. **Apple Developer Program** and **Windows signing identity.** Both are owner purchases and decisions. Until then, builds
   are ad hoc or unsigned and testers meet Gatekeeper and SmartScreen.
9. **Windows build without Visual Studio**, and **MSIX bundles** from a single-project app: a spike.
10. **WebKitGTK** inside the final Flatpak, and the 2.44 base pocket on Ubuntu 24.04 against the 2.52.6 updates pocket.
11. **A bare Hyprland header bar.** Does the close control stay usable? Does the 600 px breakpoint suit a tiled column?
12. **A user who mounted SMB in Finder.** A second path through an open panel. Low priority, since the `Smb` package covers it.
13. **Pop!_OS 26.04.** Release date and versions: recheck when it ships.
14. **Audio and speech engines on Windows and Linux** are Assumed, not researched (Decision 5b). Spike in wave 4.
15. **Thumbnails on Windows.** A native shim is unavoidable. Decide whether the feature is worth a C++ component.

## Versions

| Item | Version | Label |
| --- | --- | --- |
| Windows App SDK | 2.5.1 (stable, 2026-09-16) | Known |
| .NET | 10 LTS, SDK 10.0.401, runtime 10.0.12 | Known |
| Windows floor | 10.0.26100.0 | Known (template default), Medium choice |
| csbindgen | 1.9.8 | Known |
| Vortice.Direct3D11 | 3.8.3 | Known |
| GTK / libadwaita floor | 4.14 / 1.5 | Known |
| `gtk4` / `libadwaita` / `webkit6` crates | 0.11.5 / 0.9.2 / 0.6.1 | Known |
| WebKitGTK floor | 2.44 | Known |
| Rust for the Linux crates | 1.92 or newer | Known |
| GNOME Flatpak runtime | 51 (GTK 4.24.0, libadwaita 1.10.0) | Known |
| `@readium/navigator` / `@readium/shared` | 2.11.1 / 2.7.0 | Known |
| `pdfium-render` / PDFium binary | 0.9.4 / `chromium/7881` | Known |
| libarchive (vendored) | 3.8.9 | Known (`pin.json`) |
| `smb` / `smb2` | 0.12.x / 0.27.x | Known |
| `keyring` / `windows-native-keyring-store` / `oo7` | 4.2.0 / 1.1.0 / 0.6.0 | Known |
| `cc` crate | 1.6.0 | Known |
| macOS floor | 26 | Known (`Package.swift`) |
| macOS runner | `macos-26`, Xcode 26.6 | Known |
| Windows runner | `windows-2025-vs2026` | Known |
| Linux runner | `ubuntu-24.04` | Known |
