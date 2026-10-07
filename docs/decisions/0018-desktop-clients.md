---
status: accepted
date: 2026-10-07
deciders: Cédric Meyer, choices delegated to the agent on 2026-10-07
---

# ADR-0018 — Desktop clients: macOS in Swift, Windows and Linux on one Rust core

**Accepted. Wave 0 builds the base only. No desktop feature is implemented.**

## Context and problem statement

[ADR-0004](0004-desktop-strategy.md) documented desktop and said: build nothing
until both mobile apps ship 1.0. It left three questions open. Which UI toolkit
does Linux use? Does Windows start with WinUI 3 or Avalonia? Does a desktop
core exist, and in which language?

On 2026-10-07 the owner decided that desktop starts now. The mobile apps are
still in progress in a parallel session. So this ADR does two things.

1. It supersedes ADR-0004's **timing**: desktop work starts in a preparation
   wave, in new directories, with no change to `apps/ios` or `apps/android`.
2. It settles ADR-0004's **open questions**, using the research in
   [`docs/delivery/`](../delivery) dated 2026-10-07.

ADR-0004 stays valid where this ADR is silent. Its rejection of Mac Catalyst,
.NET MAUI and Electron-style shells still holds.

Wave 0 is the preparation wave: documents, audit, specs, designs, vendored
design skills, and a minimal base that builds. The change
[`desktop-clients`](../openspec/changes/desktop-clients) holds the plan and the
later waves.

## Decision drivers

- The artwork is the interface. Each platform must look and feel stock
  ([`AGENTS.md`](../../AGENTS.md) section 2, non-negotiable 1: no cross-platform UI).
- No backend and no analytics. Offline is normal. Secrets live only in the
  platform secure store.
- The mobile apps must not break. Desktop work uses new directories and new,
  path-filtered CI workflows.
- One person maintains the project. Every new implementation of the format layer
  is a recurring cost.
- The page curl needs a custom fragment shader at display rate
  ([ADR-0009](0009-page-curl-as-a-fragment-shader.md)).
- A web view may host EPUB reflow only. This is the one sanctioned web-view
  exception, bound by [ADR-0015](0015-epub-webview-network-egress.md).

## Decisions

| ID | Decision |
| --- | --- |
| D2 | macOS is a native SwiftUI app. It has its own XcodeGen project in `apps/desktop-macos/` and consumes `apps/ios/Packages/StoryArcKit` by path. Floor macOS 26. Bundle id `com.mecedric.storyarc`. App Sandbox on. |
| D3 | Windows is WinUI 3 (Windows App SDK 2.x) in C#, on .NET 10 LTS. Floor Windows 11 24H2 (build 26100). |
| D4 | Linux is GTK4 and libadwaita in Rust. Floor GTK 4.14 and libadwaita 1.5. Wayland first. Flatpak first. App id `com.mecedric.StoryArc`. |
| D5 | Windows and Linux share one Rust core, `storyarc-core`, with no UI. A C ABI crate, `storyarc-ffi`, exposes it to C#. macOS keeps StoryArcKit. |
| D6 | Desktop EPUB uses one pinned JavaScript renderer, Readium ts-toolkit, inside each system web view. |

### D2 — macOS: its own project, StoryArcKit by path

**Considered options**

| Option | Verdict |
| --- | --- |
| A multiplatform target inside `apps/ios` (ADR-0004's plan) | Rejected. It edits `apps/ios/project.yml` and `apps/ios/App` while another session builds them. A merge collision costs more than a second project. |
| A separate Xcode project in `apps/desktop-macos/` that depends on StoryArcKit by path | **Chosen.** |
| Mac Catalyst | Rejected. It gives an iPad app in a window. It fails the native-feel rule. |

The audit found that all 12 StoryArcKit targets compile for macOS today. The
package declares `.macOS(.v26)`. The iOS CI job already tests it on macOS. So
the Mac app reuses the domain, formats, sources, persistence and design system.

The Mac shell must rebuild what `apps/ios/App` does (about 3,400 lines). The
audit lists it. A shared `AppSupport` package would remove the duplication, but
it needs a change under `apps/ios`. That change is a later task, not wave 0.

Sandbox consequence. The old macOS README said a Mac needs no security-scoped
bookmarks. That is false with App Sandbox on. The Mac app uses `.withSecurityScope`
bookmarks and the `files.bookmarks.app-scope` entitlement. SMB uses the
existing pure-Swift `Smb` package, which needs only `network.client`.

### D3 — Windows: WinUI 3, C#, .NET 10

**Considered options**

| Option | Verdict |
| --- | --- |
| WinUI 3 on Windows App SDK 2.x | **Chosen.** The vendor's own toolkit. Windows App SDK 2.5.1 is stable (2026-09-16). Version 1.8 left servicing on 2026-09-24, so starting on 1.x is closed. |
| Avalonia | Rejected. It draws every control itself (Reported). Its Wayland backend is experimental in 12.1, July 2026 (Reported). On Linux it would run through XWayland (Inferred from the experimental backend). No research file covers Avalonia: each claim here is unchecked. |
| .NET MAUI | Rejected, unchanged from ADR-0004. It renders through WinUI 3 anyway. |
| WPF | Rejected. New Fluent work goes to WinUI. |
| Electron or Tauri | Rejected. Web-view UI outside EPUB reflow is forbidden by the `native-experience` spec. |

Three details differ from the old Windows README.

- **No Win2D for the curl.** Win2D 1.4.0 targets Windows App SDK 1.8. No release
  targets 2.x. The curl uses a Direct3D 11 swap chain in a `SwapChainPanel`, and
  the ADR-0009 shader becomes HLSL. This costs more code than Win2D. It removes
  the version skew.
- **Floor Windows 11 24H2.** It matches the template default and the CI image.
  CI cannot test a lower floor.
- **PDF uses PDFium, not `Windows.Data.Pdf`.** The Windows API has no text,
  search or outline. The `ebook-reader` spec needs all three.

### D4 — Linux: GTK4 and libadwaita in Rust

**Considered options**

| Option | Verdict |
| --- | --- |
| GTK4 + libadwaita, Rust (`gtk4-rs`) | **Chosen.** It looks native on GNOME. It runs well on Wayland. The curl runs in a `GtkGLArea`, which works under every GSK renderer. |
| Avalonia, shared with Windows | Rejected, with D3. Native Wayland is experimental (Reported). The embedded web view needs the WPE runtime (Reported). No archive-serving API is documented for EPUB (Inferred: no source was searched for one). No research file covers Avalonia, so the decision rests on the GTK and WinUI choices and not on these claims. |
| GTK4 in Vala or C | Rejected. It would add a third language to the repository and share nothing with the Windows core. |
| Qt 6 and KDE Frameworks | Rejected. It looks native on Plasma only. The test targets include GNOME and COSMIC, where GTK looks native. The research did not evaluate Qt. |
| A self-hosted web reader instead of an app | Rejected. The owner chose native apps. ADR-0004's third open question closes here. |

The floor is GTK 4.14 and libadwaita 1.5. Ubuntu 24.04 and Pop!_OS 24.04 ship
exactly these. Every other target distro is newer. A higher floor drops both.
Crates: `gtk4` 0.11 (feature `v4_14`), `libadwaita` 0.9 (`v1_5`), `webkit6` 0.6
(`v2_44`). Never enable a feature above the floor.

The floor loses some libadwaita widgets (BottomSheet, ToggleGroup, Sidebar and
others). The research lists a substitute for each.

Display servers. Wayland is first. X11 still works through GDK's fallback. The
curl runs on Wayland. It is absent on X11 until a spike shows it holds the
frame budget there, and it is never degraded. Hyprland, GNOME, KDE
Plasma and COSMIC are the test targets. Arch, Manjaro, Ubuntu, Pop!_OS and
Fedora are the distro targets.

**Flatpak first, with a policy risk.** Flathub replaced its blanket ban on
AI-assisted apps with a disclosure policy on 2026-09-04. StoryArc is developed
with AI assistance. Flathub forbids AI-generated content in the manifest it
accepts, and a human must submit it. A reviewer may still reject the app. The
owner must ask Flathub in writing before packaging work is scheduled. If Flathub
says no, the fallback is source builds, an AUR package and container-proven
distro builds. AppImage is not a fallback: WebKitGTK helper processes do not fit it.

### D5 — A shared Rust core for Windows and Linux

**Considered options**

| Option | Verdict |
| --- | --- |
| Rust core `storyarc-core`, one C ABI crate `storyarc-ffi` for C#, direct use from the GTK app | **Chosen.** |
| Two separate implementations (C# for Windows, Rust for Linux) | Rejected. The same layer is written twice. |
| Avalonia, one C# codebase | Rejected, see D3 and D4. |
| Kotlin Multiplatform | Rejected. It is the ADR-0001 option. It has no native Linux GTK story and no Windows toolchain gain. |
| macOS on the Rust core as well | Rejected. StoryArcKit already holds the logic in Swift and compiles on macOS. A rewrite buys nothing. |

**Why this does not contradict ADR-0001.** ADR-0001 rejected a shared core
between iOS and Android for three reasons. Each platform already had mature
native libraries, so a core would have wrapped them. A shared core would have put
Gradle inside the Xcode build. And the expensive parts could not be shared. Those
reasons do not hold on Windows and Linux.

- **No core exists there.** There is no Windows or Linux implementation to reuse.
  Without a shared core, both would solve the same layer twice: connectors,
  archives, the download queue, the progress merge and the sync state machine.
- **The expensive parts are the same on both.** The EPUB web renderer, PDFium
  and libarchive are identical on Windows and Linux. They are bundled, not
  provided by the platform.
- **The build is cargo on both.** Linux uses cargo directly. The Windows app calls
  one `cargo build` target. Nothing crosses an unrelated build system, as Gradle
  would have crossed Xcode.

ADR-0001 also rejected "a C++ or Rust core via FFI" because the parsing layer
already had good native libraries. On Windows and Linux that premise is false.
ADR-0001's own "revisit when" clause allowed a desktop target to change the answer.

**The seam to C#.** A hand-designed C ABI: opaque handles, byte buffers, UTF-8
JSON for records, integer error codes. The `csbindgen` tool generates the
`DllImport` declarations from the Rust source. C# wrappers are hand-written.
uniffi-bindgen-cs is rejected for now: it targets uniffi 0.31 while 0.32 is
current, and it has open async-callback and native-AOT bugs. Revisit it if the
ABI passes about 40 functions. The wave 0 contract is one function,
`storyarc_core_version()`, which returns a static NUL-terminated pointer that the
caller never frees.

**Costs accepted**

- The project now has three implementations of the format and connector layer:
  Swift (iOS and macOS), Kotlin (Android), Rust (Windows and Linux). Drift is
  possible. The shared fixture corpus in `packages/test-fixtures` and the
  OpenSpec contract remain the controls, as in ADR-0001.
- Rust is a new language in the repository.
- The Rust core owns some choices the mobile apps do not: a bundled PDF engine
  (PDFium) and a vendored libarchive build through the `cc` crate.

### D6 — Desktop EPUB: one pinned JavaScript renderer

**Considered options**

| Option | Verdict |
| --- | --- |
| Readium ts-toolkit (`@readium/navigator` 2.11.1, `@readium/shared` 2.7.0), BSD-3 | **Chosen.** Its locator model matches the Readium swift and kotlin toolkits. It is actively released. |
| foliate-js | Rejected. It uses CFI locators, not the Readium model. Its README says the API may break at any time. |
| Readium swift-toolkit on macOS | Not possible. It declares iOS only. |
| A native text engine per platform | Rejected. It would triple the hardest renderer. |

The renderer runs in the system web view: WKWebView on macOS, WebView2 on
Windows, WebKitGTK on Linux. It stays inside the sanctioned EPUB web-view
exception. ADR-0015 still binds. The web view fetches nothing outside the app's
own scheme. Each host serves archive resources through a custom scheme and adds
a deny rule and a Content-Security-Policy header. The eight-vector egress proof
from ADR-0015 runs once per web view.

The toolkit has no EPUB container parser. The core must build the Web
Publication Manifest and the positions list. Position numbers must match iOS and
Android for the same book. A shared-corpus test checks this.

## Other settled points

- **PDF.** Windows and Linux use `pdfium-render` with a pinned bundled PDFium.
  macOS keeps PDFKit.
- **RAR.** The Rust core compiles the vendored libarchive with the `cc` crate.
  This keeps one copy of the sources for SwiftPM, CMake and cargo.
- **SMB.** An in-app Rust client (`smb` first, `smb2` as the swap-in) serves
  Windows and Linux. Both crates implement SMB 3 encryption, which the mobile
  clients lack ([ADR-0010](0010-smb-clients.md)). The OS redirector is not used.
- **Secrets.** `keyring` (Windows) and `oo7` (Linux) sit behind one `SecretStore`
  trait. Where no Secret Service runs, the app never writes plaintext. It holds
  the secret in memory and shows one grey line.
- **Mobile-only features drop.** CarPlay, volume-key page turns, haptics and
  orientation lock do not exist on desktop. Cellular becomes a metered
  connection. The parity audit classifies every requirement.
- **Behaviour goes in one new spec.** `desktop-experience` takes ADDED
  requirements only, so nothing collides with the mobile changes in flight.

## Consequences

**Positive**

- Desktop work starts without touching the mobile build.
- macOS reuses a compiling, tested package.
- Windows and Linux write the connector and format layer once.
- Each platform keeps its own stock UI.

**Negative**

- Three implementations of the format layer, in three languages.
- The curl on Windows (a hand-built D3D11 path) and on Linux (a `GtkGLArea`,
  Wayland only) has no precedent in this repository. The first spikes measure it.
- PDFium is the first bundled PDF engine in the project. It parses untrusted
  input. `SECURITY.md` must list PDF parsing as an attack surface.
- Flathub may refuse the app.
- The libarchive build on MSVC needs its own desktop-only config header, kept
  outside `third_party/` so the mobile builds do not change. The research names
  it as the largest risk of its item.
- Windows 11 only. Windows 10 users are not served.

**Follow-up**

- Wave 0 writes the OpenSpec change, the design documents, the three READMEs and
  a minimal base. Later waves are in the change's `tasks.md`.
- ADR-0004's "Revisit when both mobile apps ship 1.0" is void. ADR-0004 stays
  as the record of the earlier plan.
- The owner asks Flathub about the disclosure policy, and later buys the Apple
  Developer Program for notarised macOS builds.

## Links

- Change: [`docs/openspec/changes/desktop-clients`](../openspec/changes/desktop-clients)
- Audit: [`docs/delivery/desktop-parity-2026-10-07.md`](../delivery/desktop-parity-2026-10-07.md)
- Research: [`desktop-research-windows-2026-10-07.md`](../delivery/desktop-research-windows-2026-10-07.md),
  [`desktop-research-linux-macos-2026-10-07.md`](../delivery/desktop-research-linux-macos-2026-10-07.md)
- Designs: `docs/designs/desktop/macos.md`, `windows.md`, `linux.md`
- App plans: [`apps/desktop-macos`](../../apps/desktop-macos/README.md),
  [`apps/desktop-windows`](../../apps/desktop-windows/README.md),
  [`apps/desktop-linux`](../../apps/desktop-linux/README.md)
- Related decisions: supersedes the timing of [ADR-0004](0004-desktop-strategy.md).
  Relates to [ADR-0001](0001-independent-native-cores.md),
  [ADR-0005](0005-format-and-rendering-libraries.md),
  [ADR-0008](0008-ranged-reads-and-own-zip-reader.md),
  [ADR-0009](0009-page-curl-as-a-fragment-shader.md),
  [ADR-0010](0010-smb-clients.md) and
  [ADR-0015](0015-epub-webview-network-egress.md).
