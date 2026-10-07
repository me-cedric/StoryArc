# Desktop research: Linux and macOS, 2026-10-07

Wave 0 of the `desktop-clients` change. Task R4. This file refreshes the facts in `apps/desktop-linux/README.md` and `apps/desktop-macos/README.md`. It does not repeat them. It does not change any spec.

Decisions that bind this file: D1 to D11 of the lead and `AGENTS.md` section 2.

## Confidence labels

- **Known**: read in the vendor's own text, source code, package index or API response during this research.
- **Reported**: stated by a credible secondary source (news site, forum, third-party project).
- **Inferred**: derived from Known facts. No source states it. A spike must prove it.

Nothing here is **Proven**. No spike has run on real hardware.

## Recommendations

Linux

| # | Question | Answer | Confidence | Source URL |
| --- | --- | --- | --- | --- |
| L1 | Which GTK and libadwaita floor? | Keep D4: GTK 4.14 and libadwaita 1.5. Ubuntu 24.04 (and so Pop!_OS 24.04) ships GTK 4.14.5 and libadwaita 1.5.0. Every other target is newer. A higher floor drops Ubuntu 24.04 and Pop!_OS 24.04. Ubuntu 24.04 is supported until 2029. | Known (Pop!_OS base: Inferred) | https://packages.ubuntu.com/search?keywords=libgtk-4-dev&searchon=names&suite=all&section=all |
| L2 | Which WebKitGTK floor? | webkitgtk-6.0 2.44. Ubuntu 24.04 base has 2.44.0. Its updates pocket has 2.52.6. Every other target has 2.52 or newer. | Known | https://packages.ubuntu.com/search?keywords=libwebkitgtk-6.0-dev&searchon=names&suite=all&section=all |
| L3 | Which crates? | `gtk4` 0.11.5 with feature `v4_14`. `libadwaita` 0.9.2 with feature `v1_5`. `webkit6` 0.6.1 with feature `v2_44`. `glib` and `gio` 0.22.x come as dependencies. `gtk4` 0.11 needs Rust 1.92 or newer. | Known | https://crates.io/crates/gtk4 |
| L4 | Which libadwaita widgets does the 1.5 floor lose? | Lost: `AdwBottomSheet`, `AdwButtonRow`, `AdwMultiLayoutView`, `AdwSpinner` (1.6). `AdwToggleGroup`, `AdwInlineViewSwitcher`, `AdwWrapBox` (1.7). `AdwShortcutsDialog` (1.8). `AdwSidebar`, `AdwViewSwitcherSidebar` (1.9). Kept: `AdwNavigationSplitView`, `AdwOverlaySplitView`, `AdwToolbarView`, `AdwBreakpoint` (1.4). `AdwDialog`, `AdwAlertDialog`, `AdwPreferencesDialog`, `AdwAboutDialog` (1.5). | Known | https://gitlab.gnome.org/GNOME/libadwaita/-/raw/main/NEWS |
| L5 | Which GSK renderer runs where? | GTK 4.14: `ngl` is the default, `vulkan` is opt-in. GTK 4.16 and newer: `vulkan` is the default on Wayland, `ngl` elsewhere. The old `gl` renderer is gone since 4.17.4. `GtkGLArea` works under all renderers. | Known | https://gitlab.gnome.org/GNOME/gtk/-/raw/main/NEWS |
| L6 | Fractional scaling? | Works from GTK 4.14. Wayland `wp-fractional-scale` is used by cairo since 4.11.1 and by `ngl` since 4.13.6. Fractional scaling with the `vulkan` renderer had buffer-size bugs fixed in 4.17.6. Ubuntu 24.04 does not use `vulkan` by default, so it avoids them. | Known | https://gitlab.gnome.org/GNOME/gtk/-/raw/main/NEWS |
| L7 | NVIDIA on Wayland? | Leave the renderer choice to GTK. Document `GSK_RENDERER=ngl` as the fallback. Two GTK issues are open: a `vulkan` crash in `libnvidia-glcore` (#8364) and a dGPU wake-up on multi-GPU laptops (#6689). Use NVIDIA driver 555 or newer for explicit sync. | Known (issues). Reported (driver 555) | https://gitlab.gnome.org/GNOME/gtk/-/issues/8364 |
| L8 | X11 fallback? | GTK deprecated its X11 backend in 4.17.4. It still builds. GDK falls back to X11 when Wayland is missing. GNOME 50 removed the X11 session. KDE Plasma 6.8 (expected 2026-10-14) offers Wayland only. XWayland stays. Wayland first is correct. | Known (deprecation). Reported (GNOME, Plasma) | https://linuxiac.com/gnome-50-ends-the-x11-era-after-decades/ |
| L9 | Hyprland: window decorations? | Hyprland always answers `xdg-decoration` with server-side mode. It draws no title bar. GTK drops its frame and shadow. `AdwHeaderBar` stays as a normal widget. Test that the close action stays reachable. Add `Ctrl+W` and `Ctrl+Q`. | Known (compositor source). Inferred (GTK result) | https://raw.githubusercontent.com/hyprwm/Hyprland/main/src/protocols/XDGDecoration.cpp |
| L10 | Hyprland: portals? | `xdg-desktop-portal-hyprland` implements Screenshot, ScreenCast, GlobalShortcuts and InputCapture only. It has no FileChooser, Settings, Inhibit or Secret. Ask users to install `xdg-desktop-portal-gtk`. Use `GtkFileDialog`, which goes through the portal. | Known | https://raw.githubusercontent.com/hyprwm/xdg-desktop-portal-hyprland/master/hyprland.portal |
| L11 | Hyprland: dark mode? | GTK and libadwaita read `color-scheme` from the Settings portal. On Hyprland, `xdg-desktop-portal-gtk` supplies it from GSettings. The user runs `gsettings set org.gnome.desktop.interface color-scheme prefer-dark`. | Known (portal split). Inferred (steps) | https://raw.githubusercontent.com/flatpak/xdg-desktop-portal-gtk/main/data/gtk.portal.in |
| L12 | Idle inhibit (audiobook, read-aloud)? | Call `Application::inhibit(window, IDLE, reason)`. On Wayland GTK uses `zwp_idle_inhibit_v1` first and the D-Bus path second. Hyprland and COSMIC implement that protocol. The `xdg-desktop-portal-gtk` Inhibit backend calls `org.gnome.SessionManager`, so it fails on a bare Hyprland. | Known | https://gitlab.gnome.org/GNOME/gtk/-/raw/main/gtk/gtkapplication-wayland.c |
| L13 | App id for Hyprland window rules? | The class is `com.mecedric.StoryArc`. The current Hyprland wiki writes rules in Lua (`hl.window_rule({ match = { class = ... } })`). The hyprlang form since 0.53 is `windowrule = match:class ..., effect`. `idle_inhibit` takes `none`, `always`, `focus`, `fullscreen`. Latest release is 0.56.2. | Known (wiki text, release). Inferred (class equals app id) | https://raw.githubusercontent.com/hyprwm/hyprland-wiki/main/content/configuring/core/rules/window-rules.md |
| L14 | Hyprland: tiling sizes? | Tiled windows get any size. Give `AdwApplicationWindow` a minimum size of 360 by 200 or more through `set_size_request`. libadwaita sets that default only from 1.6. Collapse the split view with `AdwBreakpoint` below about 600 px. | Known (1.6 default). Inferred (600 px) | https://gitlab.gnome.org/GNOME/libadwaita/-/raw/main/NEWS |
| L15 | Hyprland: Secret Service? | No portal and no daemon come with Hyprland. The user installs `gnome-keyring`, KeePassXC or `oo7-daemon`. The app must handle a missing service (see L19). | Known (XDPH list) | https://raw.githubusercontent.com/hyprwm/xdg-desktop-portal-hyprland/master/hyprland.portal |
| L16 | COSMIC (Pop!_OS)? | `xdg-desktop-portal-cosmic` implements Access, FileChooser, RemoteDesktop, Screenshot, Settings and ScreenCast. It has no Inhibit. Its config prefers `oo7-portal` then `gnome-keyring` for Secret. `cosmic-comp` supports `xdg-decoration`, fractional scale and idle inhibit. Pop!_OS 24.04 shipped 2025-12-11. A Pop!_OS 26.04 release was not found. | Known (portal, compositor). Reported (dates) | https://raw.githubusercontent.com/pop-os/xdg-desktop-portal-cosmic/master/data/cosmic.portal |
| L17 | KDE Plasma (Manjaro KDE)? | `xdg-desktop-portal-kde` implements FileChooser, Inhibit, Settings, GlobalShortcuts and more. Secret Service comes from KWallet. | Known (portal). Reported (KWallet) | https://raw.githubusercontent.com/KDE/xdg-desktop-portal-kde/master/data/kde.portal |
| L18 | GNOME Flatpak runtime? | `org.gnome.Platform` 51 (released 2026-09-16) carries GTK 4.24.0, libadwaita 1.10.0, WebKitGTK 2.54.1 on freedesktop SDK 26.08. Version 50 is old stable. Pick 51 for a new manifest. The runtime does not give a build-time floor: the code still compiles against the floor features. | Known | https://gitlab.gnome.org/GNOME/gnome-build-meta |
| L19 | Secrets crate? | Use `oo7` 0.6.0 (MIT). It speaks Secret Service on the host. It uses a file keyring keyed through the Secret portal in a sandbox. `keyring` 4.2.0 is a thin facade over `keyring-core` stores. Where no keyring daemon runs, never write plaintext. Hold the secret in memory for the session, show a grey notice, and name the fix (install `gnome-keyring`). A passphrase-locked `oo7` file keyring is the second option. | Known (crates). Inferred (fallback) | https://github.com/linux-credentials/oo7 |
| L20 | Async runtime for `oo7`? | `oo7` defaults to `tokio`. It also has an `async-std` feature (async-io). Pick one runtime for `storyarc-core` and the Linux app before adding `oo7`. | Known | https://raw.githubusercontent.com/linux-credentials/oo7/main/client/Cargo.toml |
| L21 | EPUB host crate? | `webkit6` 0.6.1 (2026-03-11, WebKitGTK 6.0). It binds `WebContext::register_uri_scheme`, `SecurityManager::register_uri_scheme_as_*`, and `URISchemeRequest::finish`, `finish_error`, `finish_with_response`. | Known | https://docs.rs/webkit6/0.6.1/webkit6/struct.WebContext.html |
| L22 | Archive resources for the web view? | Register a custom scheme such as `storyarc-epub://`. Answer each request from the archive reader. Send a `Content-Security-Policy` header through `finish_with_response`. The header can block remote loads, which narrows the egress risk of ADR-0015. | Known (API). Inferred (CSP effect) | https://webkitgtk.org/reference/webkitgtk/stable/method.WebContext.register_uri_scheme.html |
| L23 | JS renderer? | `@readium/navigator` 2.11.1 (BSD-3-Clause, released 2026-09-30) from `readium/ts-toolkit`. Pin the exact npm version and a lockfile. | Known | https://github.com/readium/ts-toolkit |
| L24 | PDF on Linux? | `pdfium-render` 0.9.4 binds `libpdfium.so` at run time. No major distro packages pdfium. Bundle a pinned `pdfium-binaries` build (latest tag `chromium/8086`, 2026-10-05). Match the crate's `pdfium_*` feature to the binary. Flathub apps already do this. | Known | https://github.com/bblanchon/pdfium-binaries/releases |
| L25 | Flathub policy on AI-assisted apps? | The May 2026 ban was real (reported 2026-05-29 and 2026-06-08). Flathub replaced it on 2026-09-04 (commit "Replace blanket AI ban with disclosure-based policy (#641)"). Today: disclose AI-generated code, docs and packaging with parts and extent. The Flathub manifest must contain no AI-generated or AI-assisted content. AI tools must not open Flathub pull requests or write their messages. Reviewers may reject on extent, role or maintainability. StoryArc is AI-assisted, so this gates Flathub. Owner decision needed. | Known (current text and commit). Reported (May ban) | https://docs.flathub.org/docs/for-app-authors/requirements#generative-ai-policy |
| L26 | Flatpak manifest shape? | Runtime `org.gnome.Platform` 51. SDK `org.gnome.Sdk`. Extension `org.freedesktop.Sdk.Extension.rust-stable` (branch 26.08). Add `/usr/lib/sdk/rust-stable/bin` to `append-path`. Generate crate sources with `flatpak-cargo-generator.py Cargo.lock -o cargo-sources.json`. Add a `libarchive` module and a `pdfium` archive source with a `sha256`. | Known (shape). Inferred (libarchive module) | https://github.com/flatpak/flatpak-builder-tools/tree/master/cargo |
| L27 | Flatpak finish args? | `--socket=wayland`, `--socket=fallback-x11`, `--share=ipc`, `--device=dri`, `--share=network`, `--socket=pulseaudio`. No broad `--filesystem`. Folder access goes through the FileChooser portal. | Inferred from a Flathub Rust GTK4 app | https://github.com/flathub/de.haeckerfelix.Shortwave |
| L28 | AppImage? | Do not ship it. WebKitGTK spawns helper processes. Their path handling does not fit AppImage. | Reported | https://github.com/AppImage/AppImageKit/wiki/Bundling-GTK3-apps |
| L29 | AUR package? | `depends=(gtk4 libadwaita webkitgtk-6.0 libarchive)`, `makedepends=(cargo)`. Build with `cargo fetch --locked` then `cargo build --frozen --release`. Install pdfium under `/usr/lib/storyarc/`. Arch has `rust` 1.99.0. | Inferred (shape). Known (versions) | https://archlinux.org/packages/extra/x86_64/gtk4/ |
| L30 | Linux CI runner? | Pin `ubuntu-24.04`. It matches the floor. `ubuntu-26.04` also exists. Prove other distros in containers with `container-build.sh`. | Known | https://github.com/actions/runner-images |
| L31 | Fedora risk? | The Fedora `webkitgtk` source package has owner `orphan` and one collaborator. Updates still flow (2.54.1 on 2026-10-03). If Fedora retires it, a Fedora source build loses `webkitgtk6.0-devel`. The Flatpak is not affected. | Known | https://src.fedoraproject.org/api/0/rpms/webkitgtk |
| L32 | Rust toolchain on distros? | Use `rustup` and a `rust-toolchain.toml` pin. Ubuntu 24.04 ships at most `rustc-1.91`. Debian 13 ships 1.85.1. Both are below the 1.92 floor of `gtk4` 0.11. | Known | https://packages.ubuntu.com/search?keywords=rustc&searchon=names&suite=all&section=all |

macOS

| # | Question | Answer | Confidence | Source URL |
| --- | --- | --- | --- | --- |
| M1 | Which SwiftUI APIs does a macOS 26 floor give? | All of these are available on macOS: `NavigationSplitView` (13), `inspector` (14), `Settings` scene (11), `WindowGroup(for:)` (13), `openWindow` and `dismissWindow` (13, 14), `Window` (13), `CommandMenu` and `CommandGroup` (11), `keyboardShortcut` (11), `onKeyPress` (14), `onOpenURL`, `onDrop`, `draggable` (11, 13), `fileImporter` (11), `utilityWindow`, `windowFullScreenBehavior` (15). | Known | https://developer.apple.com/documentation/swiftui/navigationsplitview |
| M2 | Liquid Glass on macOS? | `glassEffect`, `GlassEffectContainer`, `glassEffectID`, `backgroundExtensionEffect`, `ToolbarSpacer` and `scrollEdgeEffectStyle` are all macOS 26.0 APIs. Toolbars and sidebars take the glass look from the SDK. The reader must still let the artwork lead: use glass for chrome only. | Known (availability). Reported (automatic adoption) | https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:) |
| M3 | Multiple reader windows? | Use `WindowGroup(for: ReaderTarget.self)` with a `Codable` and `Hashable` value. Open with `openWindow(value:)`. SwiftUI restores windows on relaunch. | Known (API). Inferred (restore) | https://developer.apple.com/documentation/swiftui/windowgroup |
| M4 | App Sandbox for user folders? | Create a security-scoped bookmark (`.withSecurityScope`) from the URL the user picks. Store it. Resolve it on launch. Call `startAccessingSecurityScopedResource()` and balance it with the stop call. Refresh a stale bookmark. Entitlements: `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-only` (or read-write), `com.apple.security.files.bookmarks.app-scope`, `com.apple.security.network.client`. | Known (API). Inferred (exact entitlement set) | https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox |
| M5 | Does the macOS README stand? | No. It says the Mac needs "no security-scoped bookmark dance". That holds only without App Sandbox. D2 turns the sandbox on. The bookmark dance is required. Fix the README in a later wave. | Known | `apps/desktop-macos/README.md` |
| M6 | SMB under the sandbox? | Use the existing `Smb` package (SMBClient 0.3.1, pure Swift). It needs only `network.client`. Do not mount through `NetFS`. A sandboxed app cannot rely on `/Volumes`. A user-mounted volume works only after the user grants it through an open panel. Offer that as a second path. | Known (repo). Reported (`NetFS` limits) | https://developer.apple.com/forums/thread/15729 |
| M7 | Does Readium swift-toolkit support macOS? | No. `Package.swift` declares only `.iOS("15.0")`. The newest release is 3.11.0. The 4.0.0-alpha.2 notes mention no macOS. The repo already isolates Readium in `Packages/StoryArcEpub` because it is iOS-only. | Known | https://raw.githubusercontent.com/readium/swift-toolkit/develop/Package.swift |
| M8 | EPUB path on macOS? | D6 stands: `WKWebView` plus `@readium/navigator`. Serve archive resources through `WKURLSchemeHandler` (macOS 10.13). Set the handler with `setURLSchemeHandler(_:forURLScheme:)`. Return a CSP header from the handler, as on Linux. | Known (API). Inferred (CSP) | https://developer.apple.com/documentation/webkit/wkurlschemehandler |
| M9 | Distribution without a developer team? | Ad-hoc signing (`CODE_SIGN_IDENTITY=-`) runs locally. A downloaded app carries the quarantine attribute. Gatekeeper then blocks it unless notarised. Since Sequoia, Control-click Open does not override. The user must approve it in System Settings, Privacy and Security. Local builds without quarantine run. | Reported (Gatekeeper behaviour, two sources) | https://eclecticlight.co/2026/08/11/how-can-you-run-code-that-hasnt-been-notarised/ |
| M10 | What does the owner add later? | Apple Developer Program, 99 USD per year. It enables a Developer ID Application certificate, hardened runtime, `notarytool` notarisation and stapling for direct download. It also enables Mac App Store upload, which requires App Sandbox (already on). TestFlight is included. | Known (price, inclusions). Inferred (Developer ID steps) | https://developer.apple.com/programs/whats-included/ |
| M11 | GitHub runner for macOS? | Use `macos-26` (arm64, also `macos-latest`). The image 20260907.0351.1 is macOS 26.6.2. Default Xcode is 26.6. Xcode 27 is a public preview, not the default. `ios.yml` already uses `macos-26` and prints `xcodebuild -version`. Copy that step. Intel label is `macos-26-intel`. | Known | https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md |
| M12 | Does StoryArcKit build for macOS? | Yes. `Package.swift` declares `.iOS(.v26)` and `.macOS(.v26)`. The iOS CI job already runs `xcodebuild test -scheme StoryArcKit-Package -destination 'platform=macOS'`. | Known | `apps/ios/Packages/StoryArcKit/Package.swift` |

## Linux

### Version matrix

All rows read on 2026-10-07 from the distro's own package index. "Dev package" is the package a source build needs.

| Target | GTK 4 | libadwaita | WebKitGTK 6.0 | Rust in repo | Confidence |
| --- | --- | --- | --- | --- | --- |
| Ubuntu 24.04 LTS (noble-updates) | 4.14.5 | 1.5.0 | 2.52.6 (base 2.44.0) | 1.75 (up to `rustc-1.91`) | Known |
| Ubuntu 25.10 (questing) | 4.20.1 | 1.8.0 | 2.52.3 | not read | Known |
| Ubuntu 26.04 LTS (resolute-updates), released | 4.22.4 | 1.9.1 | 2.52.6 | 1.93.1 | Known |
| Pop!_OS 24.04 LTS (COSMIC Epoch 1) | 4.14.5 | 1.5.0 | 2.52.6 | as Ubuntu 24.04 | Inferred (Ubuntu base) |
| Debian 13 trixie | 4.18.6 | 1.7.6 | 2.54.0 (security), 2.52.6 | 1.85.1 | Known |
| Fedora 43 | 4.20.4 | 1.8.8 | 2.54.1 (testing) | 1.98.1 | Known |
| Fedora 44 | 4.22.5 | 1.9.4 | 2.54.1 | 1.98.1 | Known |
| Arch Linux (extra) | 4.24.1 | 1.10.0 | 2.54.1 | 1.99.0 | Known |
| Manjaro Stable | 4.22.4 | 1.9.3 | 2.52.6 | 1.98.1 | Known (mirror listing) |
| GNOME Flatpak runtime 51 | 4.24.0 | 1.10.0 | 2.54.1 | via extension | Known |

Newest upstream: GTK 4.24.1 (2026-10-01) and libadwaita 1.10.0. GTK 4.24.0 shipped on 2026-09-11 with GNOME 51 on 2026-09-16.

The lowest column is Ubuntu 24.04 and Pop!_OS 24.04. They set the floor. Debian 13 passes the floor with margin.

### Floor, crates and features

Cargo features:

```toml
gtk = { package = "gtk4", version = "0.11", features = ["v4_14"] }
adw = { package = "libadwaita", version = "0.9", features = ["v1_5"] }
webkit = { package = "webkit6", version = "0.6", features = ["v2_44"] }
```

Rules:

- A `vX_Y` feature makes the build need system headers of that version. Never enable a higher feature than the floor. One source tree serves the Flatpak and every distro build.
- Check a newer widget at run time with `adw::major_version()` and `adw::minor_version()` only if a feature earns it. Default: do not.
- `gtk4` 0.11 and `libadwaita` 0.9 depend on the same `glib` 0.22 line. `webkit6` 0.6.1 depends on `gtk4` 0.11. They match.
- `webkit6` 0.6 is a young major (0.6.0 on 2026-03-08). Pin the exact version.

Substitutes for the lost widgets:

| Lost widget | Use at the 1.5 floor |
| --- | --- |
| `AdwBottomSheet` (mini player) | `GtkRevealer` or `AdwOverlaySplitView` bar. Spike the feel. |
| `AdwButtonRow` | `AdwActionRow` with `activatable` and a style class. |
| `AdwSpinner` | `GtkSpinner`. |
| `AdwWrapBox` | `GtkFlowBox`. |
| `AdwToggleGroup` | Linked `GtkToggleButton` group. |
| `AdwShortcutsDialog` | A custom `AdwDialog`. `GtkShortcutsWindow` is deprecated since 4.17.4. |
| `AdwSidebar` | `AdwNavigationSplitView` with a `GtkListBox` using `.navigation-sidebar`. |
| `AdwMultiLayoutView` | `AdwBreakpoint` setters. |

### Wayland and rendering

- GTK uses `wp-fractional-scale` on Wayland. Fractional scales work at the floor (Known).
- GTK 4.17.1 made portals the default. GTK always uses portals inside Flatpak (Known).
- GTK 4.23 added `xdg-session-management-v1`. 4.23.3 deferred session save and restore to 4.26 (Known). Do not plan on it. Persist window state in the app.
- 4.23.2 added `gdk_display_set_prefer_vulkan()` (Known). Use it only if a spike shows a driver problem.
- The page curl lives in `GtkGLArea`. It does not depend on the GSK renderer. The Linux README's claim that `GskGLShader` is gone in 4.18 was not re-read in this research.
- The curl runs on Wayland. It is absent on X11. This stays as the README states.

### Compositor behaviour

| Topic | Hyprland | COSMIC | KDE Plasma | GNOME |
| --- | --- | --- | --- | --- |
| Decorations | Always server-side answer, no title bar drawn (Known) | Follows a user preference (Known) | KWin follows client request (Inferred) | Client-side (Known by long practice) |
| FileChooser | None. Needs portal-gtk or portal-kde (Known) | `xdg-desktop-portal-cosmic` (Known) | `xdg-desktop-portal-kde` (Known) | `xdg-desktop-portal-gnome` (Inferred) |
| Settings (dark mode) | None. portal-gtk reads GSettings (Known) | Yes (Known) | Yes (Known) | Yes (Inferred) |
| Inhibit portal | None. Use the Wayland protocol (Known) | None. Use the Wayland protocol (Known) | Yes (Known) | Yes (Inferred) |
| Idle-inhibit protocol | Yes (Known, `IdleInhibit.cpp`) | Yes (Known, `idle_inhibit.rs`) | Yes (Inferred) | Yes (Inferred) |
| Secret Service | User installs a daemon (Known) | `oo7-portal` or `gnome-keyring` (Known) | KWallet (Reported) | `gnome-keyring` (Reported) |
| Window rule key | `class` equals app id (Inferred) | n/a | n/a | n/a |

Use the app id `com.mecedric.StoryArc` for the GTK application. It is also the window class.

Hyprland setup note for the user guide: install `xdg-desktop-portal-hyprland`, `xdg-desktop-portal-gtk` and a Secret Service daemon. Set `color-scheme` with `gsettings`. A portal config such as `hyprland-portals.conf` with `default=hyprland;gtk` is the shipped default.

### Secrets

- `oo7` 0.6.0 is MIT. Its main branch is 0.7.0-alpha. Pin 0.6.0.
- `oo7` needs Rust 1.92 and `ashpd` 0.13. This matches the `gtk4` floor.
- Flatpak: `oo7` uses an encrypted file keyring. The key comes from the Secret portal. The file stays private to the app.
- Host without a daemon: `oo7` cannot reach `org.freedesktop.secrets`. The app shows one grey line in Settings and keeps the secret in memory. It never writes plaintext. This satisfies the `AGENTS.md` rule on secrets.

### EPUB host

The path is `webkit6` plus a custom scheme plus `@readium/navigator`.

1. Register `storyarc-epub` with `WebContext::register_uri_scheme`.
2. Mark it with `SecurityManager::register_uri_scheme_as_secure` and `register_uri_scheme_as_cors_enabled`. Test whether `local` is needed.
3. Answer each request from the archive reader. Set `Content-Type` and a restrictive `Content-Security-Policy` through `finish_with_response`.
4. Talk to the page through a script message handler. Carry Readium locators both ways.
5. Pin the renderer bundle in the repo. Load it from the same scheme.

Flatpak note: WebKitGTK starts its helper processes through the Flatpak portal. It works for GNOME Flatpak apps today (Inferred). The spike must check it with the final manifest.

### PDF

- `pdfium-render` 0.9.4 (2026-09-06). It binds at run time. It also supports static linking.
- The binary comes from `bblanchon/pdfium-binaries`. Release `chromium/8086` shipped 2026-10-05. Assets exist for x64 and arm64 glibc.
- Repology lists no Debian, Fedora or Arch pdfium package. Flathub apps (Passy, OpenBubbles, Saber) download the same tarball in their manifests. Do the same and pin a `sha256`.
- Match the `pdfium_*` feature of the crate to the binary version. A mismatch fails at run time.

### Packaging

Flathub gate (read this first):

- The current text sits in `docs/for-app-authors/requirements` on docs.flathub.org.
- Flathub accepts AI-assisted apps with disclosure. It bans AI content in the manifest.
- This repo's own manifest (`apps/desktop-linux/build-aux/com.mecedric.StoryArc.json`) may be AI-assisted. The manifest that goes to Flathub may not. A human writes the Flathub copy.
- The owner must also state the disclosure: parts, extent, and the review process.
- The Flathub reviewer may still say no. The first step is a written question to Flathub, as the Linux README already lists.

Flatpak manifest skeleton for the human writer:

```json
{
  "app-id": "com.mecedric.StoryArc",
  "runtime": "org.gnome.Platform",
  "runtime-version": "51",
  "sdk": "org.gnome.Sdk",
  "sdk-extensions": ["org.freedesktop.Sdk.Extension.rust-stable"],
  "command": "storyarc",
  "finish-args": ["--socket=wayland", "--socket=fallback-x11", "--share=ipc",
                  "--device=dri", "--share=network", "--socket=pulseaudio"],
  "build-options": { "append-path": "/usr/lib/sdk/rust-stable/bin" },
  "modules": [ "libarchive module", "pdfium archive source with sha256", "storyarc module with cargo-sources.json" ]
}
```

- Build offline. Generate `cargo-sources.json` from `Cargo.lock`. Set `CARGO_HOME` inside the build directory.
- The freedesktop SDK has a libarchive element. Whether the runtime ships it was not confirmed. Bundle one module.
- Test locally: `flatpak-builder --user --install --force-clean build-flatpak apps/desktop-linux/build-aux/com.mecedric.StoryArc.json`. `flatpak-builder` is not installed on this Mac. Run it in Linux CI or a container.

AUR `PKGBUILD` shape:

```bash
pkgname=storyarc
depends=(gtk4 libadwaita webkitgtk-6.0 libarchive)
makedepends=(cargo)
prepare() { cargo fetch --locked --target "$(rustc -vV | sed -n 's/host: //p')"; }
build()   { cargo build --frozen --release -p storyarc-linux; }
package() { install -Dm755 target/release/storyarc "$pkgdir/usr/bin/storyarc"; }
```

The Arch Rust package guideline wiki page was not readable during this research. Check the exact lines against it.

AppImage: skip (L28).

Distro proof: `apps/desktop-linux/scripts/container-build.sh <ubuntu-24.04|arch|manjaro|fedora>`. Docker 29.5.3 runs on this Mac. Podman is absent.

### Build-from-source dependency table

Names for GTK 4.14 or newer, libadwaita 1.5 or newer, WebKitGTK 6.0, libarchive, `pkg-config`, a C compiler and Rust. Dev packages carry the headers. The Rust toolchain comes from `rustup` for every distro (see L32).

| Need | Ubuntu 24.04, 26.04, Pop!_OS (apt) | Debian 13 (apt) | Arch and Manjaro (pacman) | Fedora 43, 44 (dnf) |
| --- | --- | --- | --- | --- |
| C compiler and linker | `build-essential` | `build-essential` | `base-devel` | `gcc gcc-c++ make` |
| `pkg-config` | `pkg-config` | `pkg-config` | `pkgconf` (in `base-devel`) | `pkgconf-pkg-config` |
| GTK 4 | `libgtk-4-dev` | `libgtk-4-dev` | `gtk4` | `gtk4-devel` |
| libadwaita | `libadwaita-1-dev` | `libadwaita-1-dev` | `libadwaita` | `libadwaita-devel` |
| WebKitGTK 6.0 | `libwebkitgtk-6.0-dev` | `libwebkitgtk-6.0-dev` | `webkitgtk-6.0` | `webkitgtk6.0-devel` |
| libarchive | `libarchive-dev` | `libarchive-dev` | `libarchive` | `libarchive-devel` |
| Rust | `curl` then `rustup` | `curl` then `rustup` | `rustup` (or `rust` 1.99) | `rustup` (or `rust` 1.98) |
| Run: file picker and dark mode | `xdg-desktop-portal-gtk` | `xdg-desktop-portal-gtk` | `xdg-desktop-portal-gtk` | `xdg-desktop-portal-gtk` |
| Run: Secret Service | `gnome-keyring` | `gnome-keyring` | `gnome-keyring` | `gnome-keyring` |
| Run: PDF | `libpdfium.so` from `pdfium-binaries` | same | same | same |

Confidence: package names for GTK, libadwaita, WebKitGTK are **Known** (read in each index). The others are **Inferred** from standard naming. The container proof script confirms them.

Notes:

- Ubuntu 24.04 `libwebkitgtk-6.0-dev` is 2.44.0 in the base pocket and 2.52.6 in updates. Both meet the floor.
- Debian 13 gets WebKitGTK from security updates (2.54.0). Debian does not backport GTK or libadwaita.
- Manjaro Stable trails Arch by about two releases. It passes the floor.
- Pop!_OS 24.04 uses the Ubuntu 24.04 names.
- Fedora's `webkitgtk6.0-devel` has an orphaned source package (L31).

## macOS

### What changes from the macOS README

| README claim | Status |
| --- | --- |
| "Not a separate app. `apps/ios` becomes a multiplatform target." | Replaced by D2: own XcodeGen project in `apps/desktop-macos`. |
| "no security-scoped bookmark dance for user-chosen folders" | False with App Sandbox on. See M4 and M5. |
| "The system already mounts SMB volumes" | Partly true. A sandboxed app needs a user grant. Use the `Smb` package. See M6. |
| "Mac App Store, or direct distribution" is open | Both need the 99 USD program. App Sandbox is on, so the Store stays open. See M10. |

### Shape on macOS 26

- Root: `NavigationSplitView` with a sidebar, content and an optional `inspector`.
- Reader: `WindowGroup(for:)` per publication. `Window` for a single Library window.
- Menus: `commands { ... }` with `CommandGroup` replacing File, View, Go. Bind `keyboardShortcut` for page turns. Bind arrow keys with `onKeyPress`.
- Settings: the `Settings` scene.
- Files: `fileImporter` for folders. Persist bookmarks in `Persistence`.
- Drag and drop: `onDrop` and `onOpenURL` for CBZ, EPUB and PDF. File associations go in `Info.plist` document types.
- Full screen: `windowFullScreenBehavior` (macOS 15).
- Glass: use for toolbars and floating controls only. Never on the artwork.
- AppKit stays a fallback for any control SwiftUI lacks.

### Sandbox entitlements to start from

```
com.apple.security.app-sandbox                    true
com.apple.security.files.user-selected.read-only  true
com.apple.security.files.bookmarks.app-scope      true
com.apple.security.network.client                 true
```

Add `com.apple.security.device.audio-input` only if a spec needs it. It does not today. No other entitlement is justified yet (Inferred).

### Readium and the EPUB path

D6 is confirmed. Readium swift-toolkit cannot serve macOS. The repo already keeps it out of `StoryArcKit` (Known, `apps/ios/project.yml` comment). The Mac app needs a new Swift target, for example `StoryArcEpubMac`, built on `WKWebView`, `WKURLSchemeHandler` and the pinned `@readium/navigator` bundle. The Windows and Linux hosts load the same bundle. One pinned bundle gives one locator model on all three desktops.

### Distribution ladder

1. Local run: ad-hoc signed build. No account. `pnpm build:macos` produces it.
2. Share with testers: ad-hoc build plus the Gatekeeper steps above. Poor experience.
3. Direct download: Developer ID certificate, hardened runtime, `notarytool`, staple. Needs the program.
4. Mac App Store: the same program. App Sandbox is on already. Needs App Store review and a privacy label.

The owner takes steps 3 and 4. They are out of scope for the waves before them.

## Open questions

1. Does the Flathub reviewer accept StoryArc under the disclosure policy? Owner action: ask Flathub in writing.
2. Does WebKitGTK run inside the final Flatpak without extra permissions? Spike.
3. Which async runtime serves `oo7` and the core? Decide before the first secret is stored.
4. Which Ubuntu 24.04 `webkitgtk-6.0` pocket do users have? The base pocket (2.44.0) may need `webkit6` feature checks. Spike.
5. Does a bare Hyprland show a usable `AdwHeaderBar` close control? Spike on a real session.
6. Is the 600 px breakpoint right for a tiled Hyprland column? Spike.
7. Which `NetFS` or open-panel path serves a user who mounted SMB in Finder? Product decision, low priority because the `Smb` package covers it.
8. Pop!_OS 26.04: release date and package versions. Re-check when it ships.

## Parent edits

None required by this file. Two follow-ups for the parent:

- `apps/desktop-macos/README.md`: replace the "no bookmark dance" row and the "Shape" section (D2).
- `docs/decisions` ADR-0018: add the Flathub disclosure policy as a risk of D4 "Flatpak first".

## Sources not fully read

- Hyprland FAQ page: the fetch tool returned no body. Facts about Hyprland come from the wiki source files and the compositor source.
- Arch Rust package guidelines: access denied.
- Apple entitlement page for `com.apple.security.files.bookmarks.app-scope`: no page at the path tried. The key name is Inferred.
