A ticked box here means: the output named in the task exists, and a command or a test named in the
task passes or the file named in the task can be read. A tick does **not** mean a person watched the
result on a real desktop. Every task that changes a screen also owes captures (light and dark, default
and largest text, with a control capture) and those are a separate line in the verify step, not implied by
the tick.

Lanes. Up to four of the six lanes run at one time, one agent each, and no two lanes write the same file.

| Lane | Owns | Files |
| --- | --- | --- |
| **M** | macOS | `apps/desktop-macos/**` |
| **C** | The shared Rust core | `apps/desktop-core/**` except `pdfium/`, root `Cargo.toml`, `Cargo.lock` |
| **L** | Linux interface | `apps/desktop-linux/src/**`, `data/**` |
| **W** | Windows interface | `apps/desktop-windows/**` |
| **P** | Packaging, CI, scripts | `.github/workflows/desktop-*.yml`, `apps/desktop-linux/build-aux/**`, `apps/desktop-linux/scripts/**`, `apps/desktop-core/pdfium/**`, `scripts/**` |
| **E** | The shared EPUB bundle | `apps/desktop-web/epub/**`, including its own check script |
| **X** | Work outside the desktop directories, or the owner | named in the task |

A task tagged **X** waits for the owner of the file it touches. The lane that needs it works around it first.

A task that sits under one lane's heading but carries another lane's tag, such as **[P]**, is written by the tagged lane.
Third party code is never edited from a desktop lane: `third_party/**` is read-only here, because the iOS and Android
workflows build it and `pnpm libarchive:pin` digests it.

Test tasks come before the implementation task they cover. Paths in later waves are proposals: an agent that finds a
better place moves the file and says so in the task. Estimates are not written here.

## 0. Wave 0: preparation

- [x] 0.1 **Parity audit.** Every requirement of the 17 main specs and the changes in flight, classified per desktop.
  Verify: `docs/delivery/desktop-parity-2026-10-07.md` exists.
- [x] 0.2 **Windows, seam, EPUB and PDF research.** Verify: `docs/delivery/desktop-research-windows-2026-10-07.md` exists.
- [x] 0.3 **Linux and macOS research.** Verify: `docs/delivery/desktop-research-linux-macos-2026-10-07.md` exists.
- [x] 0.4 **Design skills vendored** for macOS, Windows and Linux, with licence notices. Verify: the directories
  `.agents/skills/ui-review-tahoe`, `macos-capabilities`, `winui-design`, `winui-code-review`, `winui-dev-workflow`,
  `developing-gtk-apps` and `storyarc-gnome-design` exist and a `THIRD_PARTY_NOTICES.*.md` sits beside them.
- [x] 0.5 **ADR-0018.** Verify: `docs/decisions/0018-desktop-clients.md` exists.
- [x] 0.6 **This change.** proposal, `desktop-experience` delta, design, tasks. Verify: `pnpm spec:validate`,
  `pnpm spec:guard`, `pnpm delta:drop` and `pnpm partial:tasks` pass.
- [x] 0.7 **A Desktop section in STATUS.md**, one row per target. Verify: `docs/openspec/STATUS.md` holds the section.
- [x] 0.8 **Per-platform designs.** Verify: `docs/designs/desktop/macos.md`, `windows.md` and `linux.md` exist.
- [x] 0.9 **Rust workspace base.** Root `Cargo.toml`, `storyarc-core`, `storyarc-ffi` with `storyarc_core_version()`.
  Verify: `pnpm test:desktop:core` passes.
- [x] 0.10 **macOS base.** `apps/desktop-macos/project.yml` and a window that opens. Verify: `pnpm build:macos` passes. **Built 2026-10-07.** `pnpm build:macos` exits 0 and the app launches. **Owed: the light and dark frames.** This session has no macOS Screen Recording permission, so `screencapture` returns "could not create image from window". The owner deferred the frames to Wave 1 on 2026-10-07: the first lane M task that changes a screen captures the base window too.
- [x] 0.11 **Linux base.** `storyarc-linux` opens an empty libadwaita window. Verify: `pnpm build:linux` passes on
  `ubuntu-24.04` or in `container-build.sh ubuntu-24.04`. **Built 2026-10-07.** `container-build.sh` passes on `ubuntu-24.04` (GTK 4.14.5, libadwaita 1.5.0, with `--clippy`), `arch` (4.24.1 / 1.10.0), `manjaro` (4.22.4 / 1.9.3) and `fedora` (4.22.5 / 1.9.4). Frames on Wayland: `docs/designs/screenshots/desktop-linux-base-2026-10-07/`.
- [~] 0.12 **Windows base.** The WinUI project, `StoryArc.Interop` and its tests. Verify: `pnpm test:desktop:interop`
  passes on a host with the .NET 10 SDK and `pwsh apps/desktop-windows/build.ps1` passes on Windows. **Partial 2026-10-07.** `pnpm test:desktop:interop` passes on macOS and fails by name when `storyarc-core` reports a different version. **Owed:** nothing has compiled the WinUI project yet. `build.ps1` needs a Windows host, so the proof is the first `desktop-windows` CI run.
- [x] 0.13 **CI.** `desktop-macos.yml`, `desktop-linux.yml`, `desktop-windows.yml`, path filtered. Verify: each file exists
  and a push that touches only `apps/ios/App` or `apps/android` triggers none of them. A change under
  `apps/ios/Packages/StoryArcKit/**` runs the macOS desktop build on purpose, because the Mac target links that package.
- [x] 0.14 **README build-from-source** per desktop, with the dependency table from the research. Verify: each
  `apps/desktop-*/README.md` carries the commands of this change.
- [x] 0.15 **pnpm scripts** `build:macos`, `test:desktop:core`, `build:linux`, `test:desktop:interop` (parent edit to
  `package.json`). Verify: each runs from a clean checkout.

## 1. Wave 1: foundations

Lanes C, E, M, L, W and P run in parallel, up to four at one time. Nothing here shows a reader a book.

**Lane C: the core's format layer**

- [ ] 1.1 **Corpus harness first.** `apps/desktop-core/storyarc-core/tests/corpus.rs` reads
  `packages/test-fixtures/manifest.json` and fails once per fixture with no reader. Verify: `pnpm test:desktop:core`
  fails naming each fixture, then passes after 1.2 to 1.6.
- [ ] 1.2 **ZIP reader.** Own reader per ADR-0008: central directory, compressed size, zip64, encrypted flag, ranged read.
  File `src/formats/zip.rs`. Verify: the ZIP corpus passes byte for byte.
- [ ] 1.3 **TAR reader** for CBT. File `src/formats/tar.rs`. Verify: the TAR corpus passes.
- [ ] 1.4 **`RandomAccessSource`** trait with a local-file implementation, cancellation and range tests.
  File `src/io/source.rs`. Verify: `cargo test -p storyarc-core io::` passes, including a cancel mid-read.
- [ ] 1.5 **RAR through libarchive** on Linux and macOS hosts: `build.rs` with the `cc` crate over
  `third_party/libarchive`, a desktop-only Linux config header in `apps/desktop-core/storyarc-core/libarchive/` that
  `build.rs` puts ahead of the vendored include path, about ten `extern "C"` declarations. The vendored `config.h` stays
  untouched. Verify: the RAR corpus passes on `ubuntu-24.04` and `macos-26`, `pnpm libarchive:pin` still passes and
  `git diff -- third_party` is empty.
- [ ] 1.6 **Page order, metadata and covers**, mirrored from StoryArcKit `Formats`. Files under `src/formats/`.
  Verify: the corpus's expected metadata and cover digests match.
- [ ] 1.7 **RAR on MSVC.** A desktop-only `_WIN32` config header beside the Linux one, and the BCrypt code paths for x64
  and ARM64. Verify: the RAR corpus passes on `windows-2025-vs2026` for both targets and `git diff -- third_party` is
  empty. Exit: a written result in the task if it fails.
- [ ] 1.8 **The seam, test first. [W]** `apps/desktop-windows/tests/StoryArc.Interop.Tests` calls `storyarc_core_version()`,
  one buffer round trip, one error code and one cancel. Lane W writes the test project and links the generated file of 1.8a
  into `StoryArc.Interop`. Verify: the tests fail to link until 1.8a lands.
- [ ] 1.8a **The seam, exports. [C]** `storyarc-ffi` exports the four calls and `build.rs` writes
  `apps/desktop-core/storyarc-ffi/generated/NativeMethods.g.cs` with csbindgen. Lane C owns that file. Verify:
  `pnpm test:desktop:interop` passes on windows, ubuntu and macOS runners.

**Lane E: the EPUB bundle**

- [ ] 1.9 **Pin check first.** `apps/desktop-web/epub/check-pin.mjs` (lane E owns it, task 1.32 wires it into lint) fails when `apps/desktop-web/epub/package.json` does not
  hold exact versions `@readium/navigator` 2.11.1 and `@readium/shared` 2.7.0, or when `pin.json` does not match the built
  file's digest. Then create the project, lockfile and Vite build. Verify: the check passes and fails on a deliberate bump.
- [ ] 1.10 **The eight-vector egress page** of ADR-0015, ported to `apps/desktop-web/epub/test/egress.html`, with a
  collector that counts arrivals. Verify: opened in any browser, it reports eight attempts and a count of arrivals.

**Lane M: the macOS shell**

- [ ] 1.11 **Entitlement test first.** `apps/desktop-macos/Tests/EntitlementsTests.swift` reads the entitlements file and
  asserts the sandbox, user-selected read-write, app-scope bookmarks and network client keys, plus the keychain group if
  task 1.13 decides on one, and no others. Read-write is for the diagnostic export of task 3.14. Then add the file.
  Verify: `xcodebuild test -scheme StoryArc -destination 'platform=macOS'` passes.
- [ ] 1.12 **Folder bookmarks that survive the sandbox.** A Mac wrapper that creates and resolves with
  `.withSecurityScope`, refreshes a stale bookmark and balances start and stop. A spy test asserts the options. Parent
  task 1.30 moves the fix into `Persistence`. Verify: the spy test passes and a sandboxed run keeps a folder across a relaunch.
- [ ] 1.13 **Data-protection keychain, a spike first.** An ad-hoc build has no team ID, and the data-protection keychain
  needs an application identifier or a keychain access group, so `SecItemAdd` is expected to fail with
  `errSecMissingEntitlement` (-34018) (Inferred). Run the call once in an ad-hoc build and write the result into
  `design.md`, Decision 2. If it fails, ad-hoc builds use the login keychain and the data-protection path waits for
  task 6.8. Then a Mac wrapper picks the path, with a test that saves and reads a secret and a test that the secret is
  absent from the container's files. Verify: the result is in `design.md` and both tests pass for the path the spike chose.
- [ ] 1.14 **The shell.** One `Window` for the library with a `NavigationSplitView` sidebar of the destination set, empty
  states, and a `Settings` scene. Verify: a UI walk opens the window and the settings and `pnpm build:macos` passes. Captures
  in light and dark.

**Lane L: the Linux shell**

- [ ] 1.15 **Window state test first.** A pure `WindowState` value in `apps/desktop-linux/src/window_state.rs` with save and
  restore, including a display that is gone. Verify: `cargo test -p storyarc-linux window_state` passes.
- [ ] 1.16 **The shell.** `AdwApplication` with id `com.mecedric.StoryArc`, a header bar, a minimum size, a breakpoint near
  600 px, Control and W, Control and Q. Verify: `cargo run -p storyarc-linux` shows the window on Wayland, and the
  application id appears in `hyprctl clients` on a Hyprland session (manual capture).
- [ ] 1.17 **The curl spike on Wayland.** A `GtkGLArea` that draws the ADR-0009 projection while a pointer drags. Exit: the
  frame time is written down for one Wayland session and for one X11 session. The curl is present on X11 only if it holds
  the spec's frame budget there. Verify: the numbers sit in `docs/delivery/desktop-spike-curl-linux.md`.

**Lane W: the Windows shell**

- [ ] 1.18 **The shell.** A WinUI window with `TitleBar`, a backdrop and `NavigationView`, a `StoryArc.Interop` reference
  and the cargo `Exec` target. Verify: `pwsh apps/desktop-windows/build.ps1` passes for x64 and ARM64.
- [ ] 1.19 **The curl spike on D3D11.** The ADR-0009 shader as HLSL in a `SwapChainPanel` with independent input. Exit:
  monitor-rate presents on a 120 Hz screen while a flyout animates. Verify: the result sits in
  `docs/delivery/desktop-spike-curl-windows.md`.
- [ ] 1.20 **`dotnet build` without Visual Studio MSBuild**, and the MSIX bundle question. Verify: the answer is written in
  `docs/delivery/desktop-spike-windows-build.md`.

**Lane P: packaging and pins**

- [ ] 1.21 **PDFium pin check first. [P]** `scripts/pdfium-pin-check.mjs` fails when `apps/desktop-core/pdfium/pin.json` does not
  name `chromium/7881` with a sha256. Then add the pin. Verify: the check passes and fails on a changed digest.
- [ ] 1.22 **CI matrix runs green** on a push that touches only desktop paths. Verify: the three workflows pass.
- [ ] 1.23 **A Flatpak manifest for the base** that builds `storyarc-linux` offline. File
  `apps/desktop-linux/build-aux/com.mecedric.StoryArc.json`. Verify: `flatpak-builder --user --install --force-clean
  build-flatpak ...` passes in a Linux container or CI.
- [ ] 1.24 **Distro proof** for Ubuntu 24.04, Arch, Manjaro and Fedora. Verify: `container-build.sh <distro>` passes for each
  and the dependency table in the Linux README is corrected where a name was wrong.

**Lane X: decisions and parent edits**

- [ ] 1.25 **Owner: ask Flathub in writing** about the disclosure policy. Deferral: no Flathub packaging work is scheduled
  until the answer is in `docs/delivery/`. Verify: the reply is filed.
- [ ] 1.26 **Owner: answer the open questions** on chrome accent, click zones and the cold-launch budget, or accept the
  spec's defaults. Verify: `design.md` Open Questions 1 to 3 carry the answer and the spec's markers on the accent and the
  click zones are replaced by it.
- [ ] 1.27 **A WebView2 and WebKitGTK feasibility note** for serving archive bytes through a custom scheme with ranges.
  Verify: spikes 6 of the Windows research and the WebKitGTK range question are answered in
  `docs/delivery/desktop-spike-epub-hosts.md`.
- [ ] 1.28 **An async runtime decision** for the core and the Linux app (Open Question 5). Verify: ADR addendum or a line in
  `design.md`.
- [ ] 1.29 **Who builds the EPUB manifest on macOS** (Open Question 6). Verify: a spike note and a line in `design.md`.
- [ ] 1.30 **Parent edit, `apps/ios`:** make `FolderBookmarks` and `CredentialStore` correct under the sandbox and split
  the `Playback` iOS guard from a macOS path. Deferral: the Mac lane carries its own copies (1.12, 1.13, 4.7) until the iOS
  owner agrees. Verify: the same tests pass against the package.
- [ ] 1.31 **[X] Token emitters.** `packages/design-tokens` gains an emitter for the Windows resource dictionary
  (`StoryArcTokens.cs` and the XAML dictionary) and one for the GTK CSS the Linux design reads, per ADR-0007. Test first:
  a drift check that fails when a generated file is edited by hand. Deferral: until `packages/` accepts the emitters,
  lane W and lane L hold the values in one hand-written file each, marked as a copy. Verify: `pnpm tokens:check` covers
  the Windows and GTK outputs and fails on a changed token.
- [ ] 1.32 **[X] Lint wiring (parent edit, `package.json`).** Add the EPUB bundle pin check, the PDFium pin check and the
  desktop strings drift check of task 2.8 to `pnpm lint`. Verify: each fails `pnpm lint` on a deliberate break.

## 2. Wave 2: open and read a comic

All three desktops reach the same state: a library window lists the publications of a chosen folder with their covers and
opens one in a reader window, a dropped file opens in a reader window too, pages turn by key, pointer and drag, and the
place is kept. Home, search, filters, sorting and publication detail are built in this wave, before each lane's walk. Capabilities walked at the end: `comic-reader`, `page-transitions` (not the curl), `library-browsing`,
`local-library`, `publication-formats`, `reading-progress`, `reading-themes`, `localization`, `native-experience`,
`settings-and-about`, `home-screen`, `navigation-shell`, `publication-detail`, `cover-art`, and the requirements of
`desktop-experience` named in each task.

**Lane C**

- [ ] 2.1 **Library records and the progress store, test first.** `tests/progress.rs` asserts the merge against the mobile
  fixtures: furthest position wins, finished stays finished, a device with no watermark. Then SQLite storage in
  `src/store/`. Verify: `pnpm test:desktop:core` passes.
- [ ] 2.2 **Folder source scanning**, reconciliation by modification time and size, the ninety-six-directory ceiling
  recorded as a limit. File `src/sources/local.rs`. Verify: a fixture folder lists every publication and a second scan
  reads no archive.
- [ ] 2.3 **A watcher abstraction** over the native watchers with the system limit as a named error and a rescan fallback.
  File `src/sources/watch.rs`. A folder granted through the Linux document portal passes no native events, so it takes the
  polled path at an interval of 10 seconds or less. Verify: a test adds a file and sees it inside 10 seconds, a test with
  the limit forced to zero falls back and reports "not watched live", and a test with a source marked portal-granted polls
  and sees the file inside 10 seconds.
- [ ] 2.4 **Storage locations per system**, including the Flatpak and MSIX redirects. File `src/paths.rs`. Verify: tests per
  platform assert the paths, and none is a roaming folder.
- [ ] 2.5 **Page decoding** for JPEG, PNG, WebP, GIF, HEIC and AVIF, with a named reason for a page it cannot decode. File
  `src/image/decode.rs`. Verify: the corpus's decode digests match on all three OS runners.
- [ ] 2.6 **Image adjustments and spread detection** mirrored from StoryArcKit (`PageDecoder.isSpread`, brightness,
  contrast, filters). Verify: corpus digests match the mobile output within the tolerance the mobile tests use.
- [ ] 2.7 **Collation and formatting** with ICU4X for sorting, dates and numbers. File `src/locale.rs`. Verify: sorting tests
  in the four supported languages match the iOS expectations.
- [ ] 2.8 **String generator. [P]** One script turns the four-language source into `.resw` and gettext `.po` (the macOS source
  stays `.xcstrings`). Files `scripts/strings-desktop.mjs` and a drift check in `pnpm lint`. Verify: a missing key fails the
  check, and the generated files hold every key in four languages.

**Lane M**

- [ ] 2.8a **Library queries, test first.** `tests/library_query.rs` asserts search (title, series and author, folded for
  accents), the filters (format, source, reading state, downloaded), the sort keys under the collation of 2.7, and the
  Continue reading and Up next ordering, all against the mobile fixtures. Then `src/library/query.rs`. The Mac reads the same
  rules from StoryArcKit. Verify: `pnpm test:desktop:core` passes.
- [ ] 2.9 **Window model test first.** `ReaderTarget` is `Codable` and `Hashable`, a second open of the same publication
  focuses the first window, and restoration reopens windows and skips a missing publication. Then the `WindowGroup(for:)`
  readers. Verify: unit tests pass and a UI walk opens two readers, quits and relaunches.
- [ ] 2.10 **Commands and menus test first.** A test lists every command the spec names, its shortcut and its disabled state
  in each window. Then `CommandMenu` and `CommandGroup`. Verify: the test passes and the menus have the same shape in the
  library and in a reader.
- [ ] 2.11 **Key mapping test first.** A pure mapper from key and reading direction to page action, covering mirrored arrows,
  Space and Page Down, a key at the end and a text field in focus. Then `onKeyPress`. Verify: `xcodebuild test` passes.
- [ ] 2.12 **Pointer reading.** Hover reveals chrome, the pointer and chrome hide after three seconds, right-click menus on a
  page and a publication, click zones off by default with a reader setting. Verify: a UI walk and the key-mapper tests.
- [ ] 2.13 **Zoom and pan** with pinch, modifier and wheel, double click and keys, in a Mac page view. The limits come from the
  iOS zoom model (parent task 5.12 shares it). Verify: a pure zoom-model test and a UI walk.
- [ ] 2.14 **Spreads by window shape**, with the cover alone, a lone last page and a placeholder for a page still decoding.
  Verify: tests for the pairing rule across odd and even counts and right-to-left, and a resize walk.
- [ ] 2.15 **Dragging to turn** with the threshold test first. The curl is wave 5. Verify: threshold tests pass and the
  nearest available mode shows when reduced motion is on.
- [ ] 2.16 **Full screen** in a reader with chrome that appears and hides. Verify: a UI walk enters and leaves full screen and
  restores the size.
- [ ] 2.17 **Closing and quitting** write progress no later than five seconds after a turn, before a window closes and before
  quit, and survive a failed write. Verify: tests with an injected store that fails, and a quit walk.
- [ ] 2.18 **Opening files.** Document types and exported UTIs, `onOpenURL`, `onDrop` on the library, a reader and the icon,
  a CB7 refusal by name, many files at once with a stated limit, recent items in the Dock menu. Verify: a drop walk for each
  case and a test that a vanished file leaves the list silently.
- [ ] 2.19 **Folders.** `fileImporter`, stored bookmarks, a source that shows grey and offers one action when access is
  withdrawn, an offline volume that returns. Verify: tests on the bookmark states and a sandboxed run.
- [ ] 2.20 **Live folder watching** with FSEvents, batching a burst. Verify: a test copies 2,000 files and the library updates
  in batches without a blocked window.
- [ ] 2.21 **Preferences window** with search, and reading settings that apply to an open reader. Verify: a walk searches a
  word and changes a theme with a reader open.
- [ ] 2.22 **Keep the display awake** with a power assertion held while a reader is in front. Verify: a test asserts the
  assertion is created and released, and that a refusal is silent.
- [ ] 2.23 **Appearance, text size and motion.** Light and dark switch live, the reader's own size control, reduced motion.
  Verify: a walk toggles the system appearance and the largest size, with captures.
- [ ] 2.23a **Library grid and list, test first.** A view-model test over StoryArcKit's library store asserts the grid and
  the list for an empty library, for 10,000 publications, grouping by series, single selection and modifier-click selection.
  Then the SwiftUI grid and list with the cover ladder (placeholder, thumbnail, full cover; a decode never blocks a scroll)
  and the entry for a file that could not be opened. Verify: the tests pass, a UI walk scrolls a fixture library, and
  captures in light and dark.
- [ ] 2.23b **Search, filters and sorting, test first.** A query-state test asserts that the toolbar field stays in place
  while its results take over the content column, the filters by format, source, reading state and download state, and the
  sort keys. Then the `searchable` field, the filter menu and the sort menu. Verify: the tests pass and a walk searches a
  word, filters and sorts.
- [ ] 2.23c **Home.** The window opens on Home with Keep reading and Up next. An empty shelf is absent. Test first for the
  order and the absence. Verify: the test passes and a walk opens the app with and without history.
- [ ] 2.23d **Publication detail.** A pushed page in the content column with the cover wash, one primary action, a menu, and
  one line that names where the file lives. Test first for a publication with no cover, with progress and on an offline
  source. Verify: the tests pass and a walk opens a publication and reads it from the page.
- [ ] 2.24 **Conformance walk.** Run the scenarios of the capabilities listed at the top of this wave against the Mac app and
  record each failure. Verify: `docs/delivery/desktop-conformance-macos-wave2.md` lists every scenario with a result.

**Lane L**

- [ ] 2.25 **Window model test first** for restoration, one window per publication, a gone display and a missing publication,
  on the `WindowState` of 1.15. Then reader windows. Verify: `cargo test -p storyarc-linux` passes and a walk opens two readers.
- [ ] 2.26 **Menus and commands** in a header-bar menu with the same command list as 2.10, and shortcuts using Control. A
  custom `AdwDialog` lists them. Verify: a unit test of the command table and a walk.
- [ ] 2.27 **Key mapping and pointer reading** against the same table as 2.11 and 2.12, with Escape and Tab leaving a book's
  text in wave 4. Verify: `cargo test -p storyarc-linux keys::` passes and a walk shows hover chrome.
- [ ] 2.28 **Zoom, pan, spreads and drag to turn** as in 2.13 to 2.15, over the core's decoder. Verify: the same pure tests run
  against a Rust copy of the zoom and pairing rules, and a resize walk passes.
- [ ] 2.29 **Full screen** that fills the monitor on GNOME, KDE Plasma and COSMIC, and does nothing alarming on a tiling
  layout that refuses it. Verify: captures on each, and the grey menu note on Hyprland.
- [ ] 2.30 **Opening files.** First restore the `MimeType` line and `Exec=storyarc %F` in the `.desktop` file, and build the
  application with `ApplicationFlags::HANDLES_OPEN` (the base declares neither, so it never claims a file it cannot open).
  Then single instance through `GApplication`, drop targets, argv,
  opened files recorded with `GtkRecentManager`, the static actions Continue Reading, Library and Downloads in the desktop
  entry, a CB7 refusal. Verify: `desktop-file-validate` passes and a walk opens a file from the
  file manager, from argv and by drop.
- [ ] 2.31 **Folders through the portal** with `GtkFileDialog`, a stored grant that the core watches by polling at 10 seconds
  or less because the portal passes no native events, a revoked grant shown grey, and a missing portal named once. Verify: a Flatpak run and a source-build run, with captures of the revoked state.
- [ ] 2.32 **Closing and quitting** with the same write cadence as 2.17, Control and W and Control and Q on a compositor that
  draws no title bar. Verify: tests with a failing store and a Hyprland capture of the header bar.
- [ ] 2.33 **Display, appearance and any size.** Wayland first, X11 working with the curl absent and named until spike 1.17 shows it holds the frame budget there, fractional scaling,
  dark mode through the settings portal with a light default when absent, a tiled column down to the minimum size. Verify:
  captures on Wayland and X11 and a resize walk down to 360 px.
- [ ] 2.34 **Idle inhibit** through the application's inhibit call, a refusal silent. Verify: a walk on Hyprland and one on KDE.
- [ ] 2.35 **Preferences dialog** with search through `AdwPreferencesDialog`. Verify: a walk as 2.21.
- [ ] 2.35a **Library grid and list, test first.** Pure Rust view-model tests (`cargo test -p storyarc-linux library::`) for
  the cases of 2.23a, over the queries of 2.8a. Then `GtkGridView` and `GtkListView` over a `GListModel`, the cover ladder
  and the entry for a file that could not be opened. Verify: the tests pass and a walk scrolls a fixture library of 10,000
  publications on Wayland and X11.
- [ ] 2.35b **Search, filters and sorting, test first.** The query-state tests of 2.23b. Then a `GtkSearchEntry` in the
  header bar whose results take over the content column, a filter menu and a sort menu. Verify: the tests pass and a walk
  searches, filters and sorts.
- [ ] 2.35c **Home.** As 2.23c, with `AdwStatusPage` for an empty library. Verify: as 2.23c.
- [ ] 2.35d **Publication detail.** As 2.23d, as a pushed `AdwNavigationPage`, side by side from 1024 px. Verify: as 2.23d.
- [ ] 2.36 **Conformance walk** as 2.24. Verify: `docs/delivery/desktop-conformance-linux-wave2.md`.

**Lane W**

- [ ] 2.37 **Window model test first** in `StoryArc.Interop.Tests` for the window-state record, then a `Window` per reader and
  restoration through the app's own saved state. Verify: `dotnet test` passes and a walk restores two readers.
- [ ] 2.38 **Menus and commands** in a `MenuBar` with the command list of 2.10, accelerators using Control. Windows has no
  Quit key of its own: the File menu holds Quit with no accelerator, Alt and F4 closes the window, and Control and W closes
  the window. Verify: a unit test
  of the command table and a walk.
- [ ] 2.39 **Key mapping and pointer reading** as 2.11 and 2.12, including focus returning from the book's text. Verify:
  `dotnet test` and a walk with Narrator off.
- [ ] 2.40 **Zoom, pan, spreads and drag to turn** as 2.13 to 2.15 over the interop decoder. Verify: the same pure tests in C#
  and a resize walk.
- [ ] 2.41 **Full screen** with `AppWindow` presenter, chrome that hides. Verify: a walk enters and leaves and restores size.
- [ ] 2.42 **Opening files.** First restore the `windows.fileTypeAssociation` extension in `Package.appxmanifest` (the base
  declares none, so it never claims a file it cannot open) with the activation handler that opens the file. Then the ProgID,
  single instance redirection, drop targets, argv,
  Jump List recent items, a CB7 refusal. Verify: a walk from Explorer, from `pwsh` and by drop, and a Jump List capture.
- [ ] 2.43 **Folders** through the folder picker, a stored path, a withdrawn or offline volume shown grey, live watching through
  the core. Verify: tests on the states and a walk with a disconnected volume.
- [ ] 2.44 **Closing and quitting** with the cadence of 2.17, and the app exits when the last window closes. Verify: tests with
  a failing store and a walk.
- [ ] 2.45 **Appearance, text size, contrast and motion** through the system settings: light and dark live, text scale,
  high contrast, transparency off gives opaque Mica, reduced motion. Verify: a walk at 225 percent text and with transparency off.
- [ ] 2.46 **Keep the display awake** with `SetThreadExecutionState`, silent on refusal. Verify: a test around the wrapper.
- [ ] 2.47 **Preferences** page with search. Verify: a walk as 2.21.
- [ ] 2.47a **Library grid and list, test first.** View-model tests in `StoryArc.Interop.Tests` for the cases of 2.23a, over
  the queries of 2.8a. Then `ItemsView` with a uniform grid layout and a list layout, the cover ladder and the entry for a
  file that could not be opened. Verify: the tests pass and a walk scrolls a fixture library of 10,000 publications.
- [ ] 2.47b **Search, filters and sorting, test first.** The query-state tests of 2.23b. Then an `AutoSuggestBox` in the
  title bar whose results take over the content area, a filter flyout and a sort flyout. Verify: the tests pass and a walk
  searches, filters and sorts.
- [ ] 2.47c **Home.** As 2.23c. Verify: as 2.23c.
- [ ] 2.47d **Publication detail.** As 2.23d, as a page in the navigation frame. Verify: as 2.23d.
- [ ] 2.48 **Conformance walk** as 2.24. Verify: `docs/delivery/desktop-conformance-windows-wave2.md`.

**Lane P and E**

- [ ] 2.49 **Wave 2 CI.** The workflows run the core tests, the Mac tests, the Linux unit tests and the Windows tests on every
  desktop push. Verify: the three workflows are green.

## 3. Wave 3: sources, secrets, sync and downloads

Capabilities walked: `sources`, `network-share`, `kavita-server`, `opds-catalog`, `offline-downloads`,
`collections-and-reading-lists`, `library-portability`, `library-sync`.

**Lane C**

- [ ] 3.1 **The SMB spike first.** `smb` against Samba in Docker (`pnpm smb`), a Windows share and a NAS with encryption
  required. Exit: dialect and encryption reported, an SMB 1-only server refused with a named remedy. Verify: the result sits in
  `docs/delivery/desktop-spike-smb.md` and names the winner between `smb` and `smb2`.
- [ ] 3.2 **The SMB source behind `RandomAccessSource`** with the four named failures, the two-second and sixty-second rules,
  reconnect after sleep and an SMB 1 probe. File `src/sources/smb.rs`. Verify: the Samba fixture suite passes.
- [ ] 3.3 **Secrets, test first.** `tests/secrets.rs` runs against an in-memory store and asserts no secret reaches a file, a
  log or a diagnostic in any encoding. Then the `SecretStore` trait and the Windows and Linux backends and the session-only
  fallback. Verify: the test passes and the backends are exercised on their own runners.
- [ ] 3.4 **OPDS client and parser** with the certificate pin flow. File `src/sources/opds.rs`. Verify: `pnpm opds` fixtures pass.
- [ ] 3.5 **Kavita client** with progress mapping fixed by the shared rule. File `src/sources/kavita.rs`. Verify: `pnpm kavita`
  mock passes.
- [ ] 3.6 **Downloads and the queue** with metered-aware policy, resume after quit and integrity checks. File
  `src/downloads/`. Verify: tests kill the process mid-download and resume byte for byte.
- [ ] 3.7 **Collections and reading lists** with the offline edit queue, and **metadata cache, source health and refresh**.
  Verify: the shared collection fixtures pass.
- [ ] 3.8 **Library portability and sync** documents, mirrored with the mobile format and the five reconciliations. Verify: a
  document written on iOS and one on Android decode here and the reverse, as the portability change asserts.
- [ ] 3.9 **Metered flag provider** trait, with a Windows and a Linux implementation (NetworkCostType, NetworkManager). Verify:
  tests with a fake provider and a manual check on a phone tether.

**Lane M**

- [ ] 3.10 **Sources and the sandbox.** Source screens over `Smb`, `Catalogue` and `Kavita`, the data-protection keychain
  wrapper, discovery through Bonjour with the permission text. The `Smb` package has no SMB 3 encryption (ADR-0018), so the source
  says it is not encrypted and a server that requires encryption fails to connect with encryption named as the reason.
  Verify: a walk adds each source type against the mock servers, and a walk against a server that requires encryption shows
  the named failure.
- [ ] 3.11 **Metered networks, test first** with a fake path monitor, then the policy. Verify: tests for metered, unmetered,
  unknown and a mid-download change.
- [ ] 3.12 **Downloads UI** with a quit prompt that says the download pauses, resume at launch, no notification. Verify: a walk
  quits during a download and relaunches.
- [ ] 3.13 **Sync at start and quit** within five seconds and non-blocking. Verify: a test with a slow location.
- [ ] 3.14 **Diagnostics export to a file** with a save panel, a failure that names the location, a cancel that writes nothing.
  Verify: tests for the three, and the redaction test of the mobile export passes unchanged.
- [ ] 3.15 **Storage preferences** with each store clearable and a full-disk message. Verify: a walk clears each.
- [ ] 3.15a **Collections and reading lists screens, test first.** A model test for membership, pinned order and the offline
  edit queue shown grey. Then the shelves in the sidebar, the shelf page, Add to Shelf in the context menu, bulk actions and
  the shelves on Home. Verify: the tests pass and a walk creates a shelf, adds publications and sees it on Home.
- [ ] 3.16 **Conformance walk** for the Wave 3 capabilities. Verify: `docs/delivery/desktop-conformance-macos-wave3.md`.

**Lane L**

- [ ] 3.17 **Sources UI** over the core's SMB, OPDS and Kavita, discovery through avahi where present (Assumed), manual entry
  always. Verify: a walk adds each source type against the mock servers.
- [ ] 3.18 **Secret store states.** A grey line when no service runs, the session-only secret, the file keyring in Flatpak.
  Verify: walks on Hyprland without a daemon, on GNOME with `gnome-keyring`, and in a Flatpak.
- [ ] 3.19 **Metered, downloads, sync, diagnostics and storage** as 3.11 to 3.15, over the core. Verify: a unit test per rule and
  a walk.
- [ ] 3.19a **Collections and reading lists screens** as 3.15a, over the core of 3.7, with shelves as a section of the
  sidebar. Verify: as 3.15a.
- [ ] 3.20 **Conformance walk** as 3.16. Verify: `docs/delivery/desktop-conformance-linux-wave3.md`.

**Lane W**

- [ ] 3.21 **Sources UI** over the core, discovery stated absent with manual entry as the path. Verify: a walk as 3.17.
- [ ] 3.22 **Secrets** through `StoryArc.Interop` with Credential Manager, the 2560-byte rule, no secret in files. Verify: a test
  with a long token and a search of the data directory.
- [ ] 3.23 **Metered, downloads, sync, diagnostics and storage** as 3.19. Verify: as 3.19.
- [ ] 3.23a **Collections and reading lists screens** as 3.15a, over the core of 3.7. Verify: as 3.15a.
- [ ] 3.24 **Conformance walk** as 3.16. Verify: `docs/delivery/desktop-conformance-windows-wave3.md`.

## 4. Wave 4: EPUB, PDF, audio and speech

Capabilities walked: `ebook-reader`, `audio-playback`, `read-aloud-beyond-the-reader`.

**Lane E**

- [ ] 4.1 **Bundle API test first.** A browser test loads the bundle with a fixture manifest and asserts a locator round trip,
  the preferences axes as CSS properties, a footnote event and a link event that leaves the page. Then the glue in
  `apps/desktop-web/epub/src/`. Verify: the test passes in headless WebKit.
- [ ] 4.2 **Themes, search and highlights** carried to the host as messages. Verify: tests for each message.

**Lane C**

- [ ] 4.3 **Manifest and positions, test first.** `tests/epub_positions.rs` asserts equal `position` values with iOS and
  Android for every corpus book (the compressed entry size divided by 1024, rounded up, minimum 1). Then the builder in
  `src/epub/`. Verify: `pnpm test:desktop:core` passes.
- [ ] 4.4 **PDF** through `pdfium-render` on one thread, with `Read + Seek` over `RandomAccessSource`, text, search and the
  outline. File `src/pdf/`. Verify: the first page of a 300 MB file over SMB shows without a full transfer, and the corpus PDF
  text and outline match.

**Lane M**

- [ ] 4.5 **EPUB host test first.** The eight-vector page shows zero arrivals in `WKWebView` with the scheme handler, the rule
  list and the header. Then `StoryArcEpubMac`. Verify: the egress test passes, and a walk reads, themes and searches a book.
- [ ] 4.6 **PDF window** over PDFKit with the overlay and text model ported to `NSColor` and `NSPasteboard`. Verify: tests for
  selection and search, and a walk.
- [ ] 4.7 **Media keys and Now Playing** in the Mac target (parent task 1.30 moves it later), remote commands, an entry that
  leaves when playback ends, hidden windows keep playing. Verify: tests with a fake remote command centre and a walk with a
  keyboard.
- [ ] 4.8 **Read aloud** over AVSpeech, absent where no voice exists. Verify: a test with no voices.
- [ ] 4.9 **Screen reader walk** with VoiceOver on the library, a reader and the player. Verify: the walk's findings sit in
  `docs/delivery/desktop-a11y-macos.md`.

**Lane L**

- [ ] 4.10 **EPUB host test first** for `webkit6`: zero arrivals on the oldest WebKitGTK the floor allows and on the Flatpak
  runtime. Then the scheme, the filter store and the header. Verify: the egress test passes in both, and the range-request
  answer is recorded.
- [ ] 4.11 **PDF window** over the core with selection, search and outline. Verify: the same PDF tests as 4.4.
- [ ] 4.12 **Audio and speech spike** for GStreamer and speech-dispatcher (Assumed in the design). Exit: a chapter plays, seeks
  and reports position, and a sentence speaks, or the gap is written down. Verify:
  `docs/delivery/desktop-spike-audio-linux.md`.
- [ ] 4.13 **Media keys and MPRIS** with title, cover and position, keys another application holds left alone. Verify: `playerctl`
  controls playback and shows the metadata.
- [ ] 4.14 **Player and read-aloud UI**, a mini player in a revealer, idle inhibit while playing. Verify: a walk.
- [ ] 4.15 **Screen reader walk** with Orca on GNOME and on Hyprland, and with no accessibility service. Verify:
  `docs/delivery/desktop-a11y-linux.md`.

**Lane W**

- [ ] 4.16 **EPUB host test first** for WebView2: custom scheme on a custom environment, CSP header, navigation filter, zero
  arrivals. Then the host. Verify: the egress test passes and a walk reads a book.
- [ ] 4.17 **PDF window** over the interop PDF calls. Verify: as 4.11.
- [ ] 4.18 **Audio and speech spike** for `MediaPlayer` and `SpeechSynthesizer` (Assumed). Verify:
  `docs/delivery/desktop-spike-audio-windows.md`.
- [ ] 4.19 **Media keys and system media controls** through the transport controls. Verify: the overlay shows title, cover and
  position, and the keys work with another player running.
- [ ] 4.20 **Player and read-aloud UI** and the sleep rule for playback. Verify: a walk.
- [ ] 4.21 **Screen reader walk** with Narrator. Verify: `docs/delivery/desktop-a11y-windows.md`.

**Lane X**

- [ ] 4.22 **Conformance walk** across the three desktops for the Wave 4 capabilities. Verify: three files named
  `docs/delivery/desktop-conformance-<os>-wave4.md`.

## 5. Wave 5: the curl, polish and the LATER list

- [ ] 5.1 **[M] The curl on Metal**, reusing `PageCurl.metal`, proved by `xcodebuild`. Verify: a build with the shader library
  present and a frame-time capture.
- [ ] 5.2 **[L] The curl on Wayland** from the spike 1.17. On X11 it follows the spike's result: present if it held the frame
  budget, otherwise absent with the grey line. Verify: a frame capture and the X11 walk.
- [ ] 5.3 **[W] The curl on D3D11** from the spike 1.19. Verify: a presents-per-second trace on a 120 Hz display.
- [ ] 5.4 **[M] Thumbnails in Finder** and Quick Look through a generator. Verify: Finder shows covers for a folder of
  fixtures and a damaged file shows the generic icon.
- [ ] 5.5 **[L] Thumbnailer CLI** and its `.thumbnailer` file, for source and AUR builds only. A Flatpak does not export a
  thumbnailer to the host file manager (Inferred): research that first, and state in the task result that the Flatpak build
  shows no covers. Verify: a file manager shows covers for a source build and nothing is written to history.
- [ ] 5.6 **[W] Thumbnails in Explorer.** Decide the native shim (Open Question 15). Deferral: left out of the first release if
  the shim is not accepted. Verify: the decision is recorded in `design.md`.
- [ ] 5.7 **[M] Handoff from iPhone and Spotlight titles**, clearing history clears the index. Depends on task 6.8: Handoff
  needs both apps signed by one Apple team. The Mac opens the book at the position it holds, never one read from the phone.
  Verify: a walk with an iPhone and a
  test that clearing history deletes the entries.
- [ ] 5.8 **[M, L, W] The `storyarc://` link** and command line open, with an unknown title and a link carrying a command.
  Verify: tests for the three scenarios on each desktop.
- [ ] 5.9 **[M, L, W] The cold-launch budget.** Measure the first running shells on a mid-range machine and write the number
  into the spec's marker through `/opsx:update`. Verify: the number is in `design.md` and the marker is resolved.
- [ ] 5.10 **[M, L, W] Scroll, resize and frame rate** for a library of 10,000 publications. Verify: a frame trace per desktop.
- [ ] 5.11 **[M, L, W] Chrome accent and click zones** per the owner's answers of task 1.26. Verify: captures and the setting.
- [ ] 5.12 **[X] Parent edit, `apps/ios`:** an `AppSupport` package that holds the iOS shell code the Mac duplicates. Deferral:
  the Mac keeps its copy until the iOS owner schedules it. Verify: the Mac target builds against the package.
- [ ] 5.13 **[L, W] The pseudo-locale walk** on each desktop for the longest language at the largest size. Verify: each walk's
  findings sit in `docs/delivery/desktop-pseudo-<os>.md`.

## 6. Wave 6: release readiness

- [ ] 6.1 **[X] Accessibility sweep** on each desktop with its screen reader at the largest text size. Verify: the three
  `desktop-a11y-<os>.md` files list every finding closed or deferred by name.
- [ ] 6.2 **[X] Visual proof matrix.** Captures per desktop in light and dark, default and largest size, with controls. Linux
  on GNOME, KDE Plasma, Hyprland and COSMIC with the session type. Verify: `docs/delivery/desktop-captures-<os>.md` lists each
  row, and a missing row is named as unproved.
- [ ] 6.3 **[P] Licence notices** for the Rust crates, the .NET packages, PDFium and libarchive, in the About windows. Verify:
  `pnpm notices:check` covers the desktop manifests and fails on an unlisted component.
- [ ] 6.4 **[P] `SECURITY.md`** lists PDF parsing next to archive parsing. Verify: the file names both.
- [ ] 6.5 **[P] Flatpak for release**, human-written Flathub copy, after Flathub's answer (task 1.25). Verify: the submission is
  filed or the fallback recorded.
- [ ] 6.6 **[P] AUR `PKGBUILD`** and a documented source build per distro. Verify: `container-build.sh` passes for Arch and
  Manjaro with the `PKGBUILD`.
- [ ] 6.7 **[P] Windows MSIX**, a Store dry run with the `runFullTrust` friction written down. Decide the publish
  settings here: trimming and ReadyToRun need a self-contained app (NETSDK1102), so the base sets neither. Verify:
  `docs/delivery/desktop-spike-store.md`.
- [ ] 6.8 **[X] Owner: Apple Developer Program and notarisation**, and the Windows signing identity. Deferral: builds stay ad
  hoc and unsigned until the owner decides. Verify: the decision is in `design.md`.
- [ ] 6.9 **[X] Verify and archive.** Run `/opsx:verify` on this change, resolve each critical finding, update the `Desktop`
  section of `docs/openspec/STATUS.md`, then `/opsx:archive`. Verify: `pnpm spec:guard` reports no error.

## Coverage of the parity audit

Every requirement the audit classified as INH, READ or PART has a task or a deferral below. DROP rows need no task: the audit
records them and the proposal names them as non-goals. INH rows share a conformance walk and the module tasks named.

| Capability | READ and PART requirements | Tasks |
| --- | --- | --- |
| `collections-and-reading-lists` | none (all INH, built as screens in wave 3) | 3.7, 3.15a, 3.19a, 3.23a, 3.16, 3.20, 3.24 |
| `comic-reader` | Page transitions, Page fitting and zoom, Auto-hiding chrome, Reader performance (READ), System integration (PART) | 2.11 to 2.16, 2.22, 2.34, 2.46, 5.1 to 5.3 |
| `ebook-reader` | Reflowable rendering, Reader themes, Navigation and annotation, PDF rendering, Reading aloud (READ) | 4.1 to 4.8, 4.10, 4.11, 4.16 to 4.18 |
| `kavita-server` | none | 3.5, 3.16, 3.20, 3.24 |
| `library-browsing` | Presentation (READ), Search, Filtering and Sorting need desktop screens, Sorting needs collation | 2.7, 2.8a, 2.23a, 2.23b, 2.35a, 2.35b, 2.47a, 2.47b, 2.24, 2.36, 2.48 |
| `local-library` | Folder libraries, Opening a single file, Watched changes (READ) | 2.2, 2.3, 2.18 to 2.20, 2.30, 2.31, 2.42, 2.43 |
| `localization` | none (INH, needs ICU and string generator) | 2.7, 2.8, 5.13 |
| `native-experience` | Platform-native interface (READ and PART), Dynamic colour (PART), Adaptive layout (PART), Reader chrome material, Accessibility, Visual proof, Chrome for a mode (READ) | 1.14, 1.16, 1.18, 2.23, 2.33, 2.45, 4.9, 4.15, 4.21, 5.11, 6.1, 6.2 |
| `network-share` | SMB connection (READ on Windows and Linux, PART on the Mac for encryption), Streaming reads, Discovery (READ) | 3.1, 3.2, 3.9, 3.10, 3.17, 3.21 |
| `offline-downloads` | Queue management, Network policy (READ), Storage management (PART) | 3.6, 3.11, 3.12, 3.15, 3.19, 3.23 |
| `opds-catalog` | none | 3.4, 3.16, 3.20, 3.24 |
| `page-transitions` | The curl, Transition performance (READ), Turn triggers (PART) | 2.12, 2.15, 5.1 to 5.3, 5.10 |
| `publication-formats` | Page decoding (READ on Windows and Linux) | 1.2 to 1.7, 2.5 |
| `reading-progress` | none | 2.1, 2.17, 2.24 |
| `reading-themes` | none | 2.21, 2.24, 4.2 |
| `settings-and-about` | Settings organisation, About (READ) | 2.21, 2.35, 2.47, 6.3 |
| `sources` | Credential storage (READ) | 1.13, 3.3, 3.10, 3.18, 3.22 |
| `audio-playback` | Playback controls, Reaching the player without sight (READ) | 4.7, 4.13, 4.19, 4.9, 4.15, 4.21 |
| `cover-art` | Finding a cover on the web (READ), the cover ladder | 2.23a, 2.35a, 2.47a, 2.24, 2.36, 2.48 |
| `library-portability` | none | 3.8 |
| `library-sync` | When a sync happens (READ) | 3.8, 3.13, 3.19, 3.23 |
| `home-screen` | none | 2.23c, 2.35c, 2.47c, 2.24, 2.36, 2.48 |
| `navigation-shell` | Destination set, Reaching search, Chrome that gets out of the way (READ) | 1.14, 1.16, 1.18, 2.10, 2.23b, 2.26, 2.35b, 2.38, 2.47b |
| `publication-detail` | none | 2.23d, 2.35d, 2.47d, 2.24, 2.36, 2.48 |
| `read-aloud-beyond-the-reader` | The transport outside the reader (READ) | 4.7, 4.13, 4.19, 4.14, 4.20 |

Deferrals, each named here so none is a silent drop:

- Thumbnails on Windows: task 5.6 may drop the feature after the native-shim decision.
- Thumbnails on Linux: task 5.5 covers source and AUR builds only. The Flatpak build shows no cover thumbnails, because a Flatpak does not export a thumbnailer to the host file manager.
- Flathub packaging: no work until the owner's answer (task 1.25). The fallback is source builds and the AUR.
- Notarisation and signing: task 6.8, owner purchase.
- SMB 3 encryption on the Mac: the `Smb` package has none. A parent edit under `apps/ios/Packages` adds it. Until then the
  Mac states the source is not encrypted and refuses a server that requires encryption.
- Sharing the iOS shell code with the Mac: task 5.12, parent edit, the Mac keeps its copy until then.
- The cold-launch budget, the chrome accent and edge click zones: the spec carries the owner's answer or its marker until
  tasks 1.26, 5.9 and 5.11 close them.
- Mobile-only requirements (the app icon chooser, CarPlay and Android Auto, volume-key turns, orientation lock, haptics):
  dropped on desktop by the audit.
