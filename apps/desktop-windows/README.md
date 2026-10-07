# StoryArc for Windows

**Status: wave 0, base only.** The base has three parts: a WinUI 3 shell that
opens an empty window, an interop library, and interop tests. They prove that
the C# side loads the Rust core. No reading feature exists yet. The author of
wave 0 had no .NET SDK and no Windows machine, so **nothing here has run on
Windows**. Every Windows claim is **Known** (read in vendor text) or **Inferred**
until a spike runs it.

[ADR-0018](../../docs/decisions/0018-desktop-clients.md) supersedes the timing in
[ADR-0004](../../docs/decisions/0004-desktop-strategy.md) and chooses WinUI 3.

- Plan: [`docs/openspec/changes/desktop-clients`](../../docs/openspec/changes/desktop-clients)
- Design: [`docs/designs/desktop/windows.md`](../../docs/designs/desktop/windows.md)
- Research: [`desktop-research-windows-2026-10-07.md`](../../docs/delivery/desktop-research-windows-2026-10-07.md)
  (sources, the full seam comparison, every spike) and
  [`desktop-parity-2026-10-07.md`](../../docs/delivery/desktop-parity-2026-10-07.md)

## Stack

| Part | Choice |
| --- | --- |
| UI | WinUI 3 on Windows App SDK **2.5.1** (stable, 2026-09-16). 1.8 left servicing on 2026-09-24, so no start on 1.x. |
| Language | C# on **.NET 10 LTS** (end of life 2028-11-14). TFM `net10.0-windows10.0.26100.0`. Platforms x64 and ARM64. |
| Shape | One single-project packaged WinUI app. Release builds use ReadyToRun and trimming. Native AOT is not enabled. |
| Floor | Windows 11 24H2, build 26100. `TargetPlatformMinVersion` and the manifest `MinVersion` are `10.0.26100.0`. |
| Chrome | `TitleBar`, Mica through `SystemBackdrop`, `NavigationView`. Chrome only: the artwork stays the interface. |
| Core | The shared Rust core, `storyarc-core`, through the C ABI crate `storyarc-ffi` (cdylib `storyarc_ffi`). |
| Seam | A hand-designed C ABI. `csbindgen` generates the `DllImport` file. C# wrappers use `SafeHandle`. Not uniffi: its C# generator lags one minor behind. Revisit above about 40 functions. |
| Page curl | Direct3D 11 swap chain in a `SwapChainPanel`, ADR-0009 shader as HLSL, input from `CreateCoreIndependentInputSource`. **Not Win2D**: 1.4.0 targets Windows App SDK 1.8 and nothing says it runs on 2.x. |
| EPUB | `WebView2` with the pinned Readium ts-toolkit renderer. Archive resources come through a custom scheme and `WebResourceRequested`. Virtual-host mapping serves folders only, so it cannot serve archive bytes. |
| PDF | `pdfium-render` with a bundled PDFium (`chromium/7881`). `Windows.Data.Pdf` has no text, search or outline API, so it fails the `ebook-reader` spec. |
| RAR | Vendored libarchive, compiled by the `cc` crate. The MSVC build needs its own config header, kept under `apps/desktop-core` so `third_party/` stays untouched. This is the largest risk of that item. |
| SMB | An in-app Rust client (`smb`, with `smb2` as the swap-in). Not the OS redirector: it hides encryption and dialect, and Windows 11 24H2 requires signing by default. |
| Secrets | `keyring` v4 with `windows-native-keyring-store` (Credential Manager, `CredWrite`) behind a `SecretStore` trait. Keep each blob under 2,560 bytes. |
| Packaging | MSIX. The Microsoft Store is the canonical channel. Registration is free and the Store signs the package. |

Not chosen: Avalonia (draws every control itself), .NET MAUI (renders through
WinUI 3 anyway), WPF (maintenance mode), Electron and Tauri (the
`native-experience` spec forbids web-view UI outside EPUB reflow).

## Folder layout

```
apps/desktop-windows/
├── build.ps1                       the Windows build entry
├── global.json                     pins .NET SDK 10.0.401
├── Directory.Build.props           shared build properties
├── StoryArc.Windows.slnx           the solution
├── src/
│   ├── StoryArc.Windows/           WinUI 3 app (the only Windows-only project)
│   └── StoryArc.Interop/           net10.0 library: DllImport + wrappers, no WinUI reference
├── tests/
│   └── StoryArc.Interop.Tests/     net10.0 tests; run on Windows, Linux and macOS
└── README.md
```

The Rust side lives in `apps/desktop-core/` (`storyarc-core`, `storyarc-ffi`) at
the repository root workspace.

## Build and run

```powershell
pwsh apps/desktop-windows/build.ps1      # core, interop tests, then the WinUI project
```

On any OS with the .NET 10 SDK and Rust, the interop layer builds and tests
without Windows:

```bash
pnpm test:desktop:core        # cargo test -p storyarc-core -p storyarc-ffi
pnpm test:desktop:interop     # cargo build -p storyarc-ffi && dotnet test apps/desktop-windows/tests/StoryArc.Interop.Tests
```

Requirements on Windows: Windows 11 24H2, Visual Studio 2026 (or the .NET SDK and
the `winapp` CLI), the Rust toolchain with `x86_64-pc-windows-msvc`, and Developer
Mode for `winapp run`. Unsigned dev builds run through `winapp run` or an
unpackaged `dotnet publish`. A sideloaded MSIX needs a trusted certificate:
`winapp cert generate`.

CI: `.github/workflows/desktop-windows.yml` on `windows-2025-vs2026`. It is
path-filtered, so mobile CI is unaffected.

## What it inherits

Everything in the 17 capability specs holds. The parity audit finds 60 of 95 main
requirements hold as written on Windows, and 27 need a desktop reading. The
format layer, connectors, download queue and progress merge come from the Rust
core, not from a Windows implementation. `packages/design-tokens` gains a C#
emitter, `StoryArcTokens.cs` ([ADR-0007](../../docs/decisions/0007-design-token-pipeline.md)).

## What drops or changes

| Mobile feature | On Windows |
| --- | --- |
| CarPlay, Android Auto | Dropped. |
| App icon chooser | Dropped. |
| Haptics, brightness, orientation lock | Dropped. |
| Volume-key page turns | Dropped. Arrow keys replace them. |
| Cellular data | The Windows metered-connection flag. |
| Screen stays awake while reading | `SetThreadExecutionState`. |
| Share sheet for the diagnostic export | Save to file, reveal in Explorer. Redaction stays. |
| Media controls for read-aloud | System Media Transport Controls. |
| File handling | `windows.fileTypeAssociation` in the manifest. The app can register but never set itself as default. |
| Screen readers | Narrator and NVDA through UI Automation. |
| Excluded from device backup | No API. A location choice plus documentation. |

## Desktop-new features

Menu and keyboard reading, two-page spreads by window shape, full screen, one
window per reader, open from Explorer (file association, drag and drop, command
line), pointer reading (wheel zoom, hover chrome, right-click), live folder
watching, media keys, Jump List recent items. Later: Explorer thumbnails (a shell
extension cannot run on managed .NET, so it needs a native shim), `storyarc://`.

## Open questions

1. Does the D3D11 curl hold monitor rate on a 120 Hz display while a XAML flyout animates? This is the first spike.
2. Does `dotnet build` compile the WinUI project on the runner without `setup-msbuild`? **Inferred**: yes. The MSIX step uses VS `msbuild` until a spike proves `dotnet`.
3. Can a single-project app produce an MSIX bundle? Two Microsoft pages conflict.
4. Does Store review accept `runFullTrust` for a comic reader, and does it ask for more on user-provided content?
5. Which RAR corpus results does the MSVC libarchive build give, on x64 and ARM64?
6. Is `PublishAot` workable across WinUI 3 and the interop layer? Try it only after the curl and the seam run.
7. Does 23H2 matter? The floor is 24H2. Reopen if users report 23H2 devices.
8. Signing for direct download: Azure Artifact Signing is closed to individuals outside the US and Canada. Direct download waits on a signing identity. The Store route needs none.

The full spike list, with exit criteria, is in the research file and in the
`tasks.md` of the change.
