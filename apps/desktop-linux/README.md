# StoryArc for Linux

**Status: wave 0, base only.** The app opens an `AdwApplicationWindow` with a
split view (Home, Library, Downloads), an About dialog and `Ctrl+Q`. It shows
the core version. No reading feature exists yet. The Flatpak manifest is a
skeleton: it does not build offline until `cargo-sources.json` exists.

[ADR-0018](../../docs/decisions/0018-desktop-clients.md) supersedes the timing in
[ADR-0004](../../docs/decisions/0004-desktop-strategy.md) and chooses GTK4 and
libadwaita in Rust.

- Plan: [`docs/openspec/changes/desktop-clients`](../../docs/openspec/changes/desktop-clients)
- Design: [`docs/designs/desktop/linux.md`](../../docs/designs/desktop/linux.md)
- Research: [`desktop-research-linux-macos-2026-10-07.md`](../../docs/delivery/desktop-research-linux-macos-2026-10-07.md)
  (sources, version matrix, widget substitutes) and
  [`desktop-parity-2026-10-07.md`](../../docs/delivery/desktop-parity-2026-10-07.md)

Confidence labels follow [ADR-0005](../../docs/decisions/0005-format-and-rendering-libraries.md):
**Known** is read in vendor text or source, **Reported** is a secondary source,
**Inferred** is reasoned. Nothing is **Proven** until a spike runs on real hardware.

## Stack

| Part | Choice |
| --- | --- |
| Language and UI | Rust. `gtk4` 0.11 (feature `v4_14`), `libadwaita` 0.9 (`v1_5`). `gtk4` 0.11 needs Rust 1.92 or newer. |
| Floor | GTK 4.14 and libadwaita 1.5. Ubuntu 24.04 and Pop!_OS 24.04 ship these. Never enable a feature above the floor. |
| Package and binary | Cargo package `storyarc-linux`, binary `storyarc`. App id `com.mecedric.StoryArc`. |
| Core | `storyarc-core`, the shared Rust core, used directly. No FFI on Linux. |
| Page curl | A `GtkGLArea` with the ADR-0009 shader in GLSL. It does not depend on the GSK renderer. Wayland only. |
| EPUB | `webkit6` 0.6 (feature `v2_44`) with the pinned Readium ts-toolkit renderer. Archive resources come through a custom URI scheme with a Content-Security-Policy header. |
| PDF | `pdfium-render` with a bundled PDFium. No major distro packages it. |
| RAR | Vendored libarchive, compiled by the `cc` crate. |
| SMB | An in-app Rust client (`smb`, with `smb2` as the swap-in), inside `--share=network`. gvfs is not the data path. |
| Secrets | `oo7` behind a `SecretStore` trait. Secret Service on the host, the Secret portal in Flatpak. With no keyring daemon, the app never writes plaintext. It holds the secret in memory and shows one grey line. |
| Packaging | Flatpak first, with a Flathub gate (below). Source builds are documented. |

Not chosen: Avalonia (experimental Wayland backend), Qt, Vala or C, AppImage
(WebKitGTK helper processes do not fit it).

## Folder layout

```
apps/desktop-linux/
├── Cargo.toml                          package storyarc-linux, binary storyarc
├── src/main.rs                         the window, actions and About dialog
├── data/
│   ├── com.mecedric.StoryArc.desktop
│   ├── com.mecedric.StoryArc.metainfo.xml
│   └── icons/hicolor/scalable/apps/    the app icon
├── build-aux/
│   └── com.mecedric.StoryArc.json      Flatpak manifest (skeleton)
├── scripts/container-build.sh          builds and tests inside a distro container
└── README.md
```

The workspace root `Cargo.toml` lists `apps/desktop-core/storyarc-core`,
`apps/desktop-core/storyarc-ffi` and `apps/desktop-linux`.

## Build and run

```bash
pnpm build:linux                   # cargo build -p storyarc-linux
cargo run -p storyarc-linux        # run the app
pnpm test:desktop:core             # cargo test -p storyarc-core -p storyarc-ffi
```

Distro proof, in a container, with that distro's own packages:

```bash
apps/desktop-linux/scripts/container-build.sh ubuntu-24.04    # or: arch | manjaro | fedora
```

Flatpak, once `cargo-sources.json` exists (generate it with
`flatpak-cargo-generator.py Cargo.lock`):

```bash
flatpak-builder --user --install --force-clean build-flatpak apps/desktop-linux/build-aux/com.mecedric.StoryArc.json
```

The manifest uses runtime `org.gnome.Platform` 51 (GTK 4.24, libadwaita 1.10)
and the `rust-stable` SDK extension. The runtime does not set the build floor:
the code still compiles against the floor features.

CI: `.github/workflows/desktop-linux.yml` on `ubuntu-24.04`, which matches the
floor. It is path-filtered, so mobile CI is unaffected.

## Distros and build dependencies

Targets: Arch, Manjaro, Ubuntu 24.04, Pop!_OS 24.04 and Fedora. All versions were
read from each distro's package index on 2026-10-07.

| Distro | GTK 4 | libadwaita | WebKitGTK 6.0 | Floor | Install |
| --- | --- | --- | --- | --- | --- |
| Ubuntu 24.04 LTS | 4.14.5 | 1.5.0 | 2.44.0 base, 2.52.6 updates | Meets it exactly | `apt` |
| Pop!_OS 24.04 LTS | 4.14.5 (**Inferred**, Ubuntu base) | 1.5.0 | 2.52.6 | Meets it exactly | `apt` |
| Fedora 43 and 44 | 4.20.4 and 4.22.5 | 1.8.8 and 1.9.4 | 2.54.1 | Passes | `dnf` |
| Arch Linux | 4.24.1 | 1.10.0 | 2.54.1 | Passes | `pacman` |
| Manjaro Stable | 4.22.4 | 1.9.3 | 2.52.6 | Passes | `pacman` |

Dev packages. The wave 0 base needs GTK, libadwaita, a compiler and Rust. WebKitGTK
and libarchive are listed because later waves link them.

| Need | Ubuntu 24.04, Pop!_OS | Arch, Manjaro | Fedora |
| --- | --- | --- | --- |
| Compiler, linker | `build-essential pkg-config` | `base-devel` | `gcc gcc-c++ make pkgconf-pkg-config` |
| GTK 4 | `libgtk-4-dev` | `gtk4` | `gtk4-devel` |
| libadwaita | `libadwaita-1-dev` | `libadwaita` | `libadwaita-devel` |
| WebKitGTK 6.0 | `libwebkitgtk-6.0-dev` | `webkitgtk-6.0` | `webkitgtk6.0-devel` |
| libarchive | `libarchive-dev` | `libarchive` | `libarchive-devel` |
| Rust 1.92 or newer | `rustup` | `rustup` or `rust` | `rustup` or `rust` |
| Run: file picker, dark mode | `xdg-desktop-portal-gtk` | same | same |
| Run: secrets | `gnome-keyring` | same | same |

Rust: Ubuntu 24.04 ships at most `rustc-1.91`, which is below the `gtk4` 0.11
floor of 1.92. Use `rustup`. The workspace sets `rust-version = "1.92"`.

Fedora risk: the `webkitgtk` source package is orphaned. Updates still flow. If
Fedora retires it, a Fedora source build loses `webkitgtk6.0-devel`. The Flatpak
is not affected.

Package names for GTK, libadwaita and WebKitGTK are **Known**. The rest are
**Inferred** from standard naming. `container-build.sh` confirms them.

## Display servers and desktops

Wayland is first. X11 still works, because GDK falls back to it. GTK deprecated
its X11 backend in 4.17.4. GNOME 50 dropped the X11 session. KDE Plasma 6.8 is
Wayland only.

| Topic | Behaviour |
| --- | --- |
| Page curl | Present on Wayland. Absent on X11 until the wave 1 spike shows it holds the frame budget there; never degraded. |
| Fractional scaling | Works from GTK 4.14. |
| Renderer | Leave it to GTK. On NVIDIA, document `GSK_RENDERER=ngl` as the fallback. Use driver 555 or newer. |
| Portals | GTK uses portals in Flatpak. The file picker is `GtkFileDialog`. |
| Idle inhibit | `Application::inhibit(IDLE)`. GTK tries the Wayland protocol first. |
| Window state | Persist it in the app. GTK will not restore sessions before 4.26. |
| Minimum size | Set it yourself (360 by 294 today). Collapse the split view below 600 px with `AdwBreakpoint`. |

| Desktop | Notes |
| --- | --- |
| **GNOME** | The reference. Client-side decorations. Portals complete. |
| **KDE Plasma** (Manjaro KDE, Fedora KDE) | `xdg-desktop-portal-kde` covers file picker, inhibit and settings. KWallet supplies Secret Service (**Reported**). |
| **Hyprland** | Hyprland always answers with server-side decorations and draws no title bar. `AdwHeaderBar` stays. Add `Ctrl+W` and `Ctrl+Q`. `xdg-desktop-portal-hyprland` has no file chooser, settings, inhibit or secrets: install `xdg-desktop-portal-gtk` and a Secret Service daemon (`gnome-keyring`, KeePassXC or `oo7-daemon`). Set dark mode with `gsettings set org.gnome.desktop.interface color-scheme prefer-dark`. Window class is the app id, `com.mecedric.StoryArc` (**Inferred**). Idle inhibit works through the Wayland protocol. Tiled windows get any size, hence the minimum size above. |
| **COSMIC** (Pop!_OS 24.04) | `xdg-desktop-portal-cosmic` has file chooser and settings but no inhibit. The compositor supports decorations, fractional scale and the idle-inhibit protocol. Secrets go through `oo7-portal` or `gnome-keyring`. |

Hyprland sample, for the user guide (check the Hyprland wiki for your version, as
the rule syntax changed in 0.53):

```
windowrule = match:class com.mecedric.StoryArc, idle_inhibit fullscreen
```

## Flathub gate

Flathub replaced its AI ban with a disclosure policy on 2026-09-04. StoryArc is
developed with AI assistance. Flathub requires disclosure of AI-generated code,
docs and packaging, forbids AI-generated content in the Flathub manifest, and
lets reviewers reject on extent or role. A human must write and submit the
Flathub copy of the manifest. **The owner must ask Flathub in writing before any
packaging work is scheduled.** The fallback is source builds, an AUR package, and
container-proven distro builds.

Flatpak facts that shape the plan:

1. **Folder grants persist.** A FileChooser portal grant survives restarts, and
   the granted tree allows recursive reads and `pread` ranges. The re-pick path
   in the `local-library` spec stays load-bearing.
2. **Watching does not cross the portal.** No inotify events reach the sandbox, so a portal-granted folder uses
   polled reconciliation by mtime and size at an interval of 10 seconds or less.
3. **FUSE overhead is unmeasured.** A spike benchmarks a 10,000-item library
   against a static grant before the manifest picks one.
4. **Finish args** start at `--socket=wayland`, `--socket=fallback-x11`,
   `--share=ipc`, `--device=dri`, `--share=network`. No broad `--filesystem`.

## What it inherits and what changes

The contract holds as written for 60 of 95 main requirements, with 27 needing a
desktop reading. The format layer, connectors, downloads and progress merge come
from the shared core.

| Spec wording | Linux reading |
| --- | --- |
| Finger-tracked curl, pinch, tap zones | Pointer drag. Ctrl+scroll and touchpad pinch. Click zones. |
| Screen does not auto-lock while reading | The idle-inhibit protocol, then the portal. |
| Backgrounded or killed | Window close, focus loss, quit, crash. The 15 s progress cadence stays. |
| Secrets in the platform secure store | Secret Service or portal through `oo7`. |
| Share sheet for diagnostics | Save to file and open the containing folder. Redaction stays. |
| Metered or data saver | NetworkManager hints. Weaker than mobile. |
| Excluded from device backup | No mechanism. A documented location. |
| Media controls for read-aloud | MPRIS. Speech through speech-dispatcher. |
| File handling | `.desktop` MIME entries. |
| Screen readers | Orca over AT-SPI2. GTK4 supports it natively. |

Dropped: CarPlay, Android Auto, app icon chooser, haptics, orientation lock,
brightness, volume-key page turns.

Desktop-new: menu and keyboard reading, two-page spreads, full screen, one
`AdwApplicationWindow` per reader, open from the file manager (MIME, drag and
drop, argv), pointer reading, live folder watching (inotify limits apply),
MPRIS, `GtkRecentManager` for recent files with static `.desktop` actions (Continue Reading, Library, Downloads), a stable app id for tiling rules.
Later: a GNOME thumbnailer for covers, `storyarc://`.

Widgets lost at the 1.5 floor have substitutes: BottomSheet becomes a
`GtkRevealer` bar, ToggleGroup a linked `GtkToggleButton` group, Sidebar an
`AdwNavigationSplitView` with a `GtkListBox`. The research file has the table.

## Open questions

1. Does Flathub accept StoryArc under the disclosure policy? Owner action.
2. Does WebKitGTK run inside the final Flatpak without extra permissions?
3. Which async runtime serves `oo7` and the core? Decide before the first secret is stored.
4. Does a bare Hyprland show a usable close control on `AdwHeaderBar`? Is 600 px the right breakpoint for a tiled column?
5. Does the curl hold 120 FPS on Mesa and NVIDIA under both `vulkan` and `ngl`? Does GTK ever restore scene-graph shaders?
6. HEIC: bundled libheif (LGPL) and HEVC patents, or refused by name?
7. Does the system accent colour reach the app at the 1.5 floor? The accent API arrived after 1.5 (**Inferred**).
8. Pop!_OS 26.04: release date and package versions. Recheck when it ships.
