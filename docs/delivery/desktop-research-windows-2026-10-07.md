# Desktop research R3: Windows, the Rust-to-C# seam, the desktop EPUB renderer, desktop PDF

Date: 2026-10-07. Wave 0 (preparation). No code. Scope: decisions D3, D5, D6 of the `desktop-clients` change.

Labels follow [ADR-0005](../decisions/0005-format-and-rendering-libraries.md) and
[`apps/desktop-windows/README.md`](../../apps/desktop-windows/README.md):
**Known** = vendor documentation or source read on 2026-10-07.
**Reported** = credible secondary source.
**Inferred** = reasoned from Known facts, not run.
Nothing here is **Proven**. The .NET SDK is not installed on the machine that wrote this file, so no .NET command was run.

## Recommendations

| # | Question | Answer | Confidence | Source |
| --- | --- | --- | --- | --- |
| 1 | Windows App SDK line | Start on **2.x**. Pin `Microsoft.WindowsAppSDK` **2.5.1** (stable, 2026-09-16, "Current"). Track monthly patches. Do not start on 1.8: it ends servicing 2026-09-24. | High | https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-channels |
| 2 | .NET and project shape | .NET 10 LTS (end of life 2028-11-14). Single-project packaged WinUI 3 app, TFM `net10.0-windows10.0.26100.0`, platforms x86/x64/ARM64. Use `winapp new --template winui-navview` or `dotnet new winui-navview` once, then keep the csproj by hand. | High | https://github.com/microsoft/WindowsAppSDK/blob/main/dev/Templates/Source/ProjectTemplates/Desktop/CSharp/SingleProjectPackagedApp/ProjectTemplate.csproj |
| 3 | Windows floor to declare | **Windows 11 24H2, build 26100.** `TargetPlatformMinVersion` `10.0.26100.0`, manifest `MinVersion` `10.0.26100.0`. It matches the template default and the CI image SDK. Lower floors cannot be tested in CI. | Medium | https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/support |
| 4 | Shell controls | Use the built-in `TitleBar`, Mica or Desktop Acrylic through `SystemBackdrop`, `NavigationView`, `TabView`. All ship in the stable line. The artwork stays the interface: use them for chrome only. | High | https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-notes/windows-app-sdk-2-0 |
| 5 | Win2D for the page curl | **No.** Win2D 1.4.0 (2026-03-16) targets WinAppSDK 1.8. No release targets 2.x. Use a **D3D11 swap chain** in a `SwapChainPanel` (`ISwapChainPanelNative`) with the ADR-0009 shader as HLSL. | High | https://www.nuget.org/packages/Microsoft.Graphics.Win2D/1.4.0 |
| 6 | Rust core to C# | **Hand-designed C ABI** (opaque handles, byte buffers, JSON records, integer error codes) with **csbindgen**-generated `DllImport` declarations and hand-written C# wrappers. Not uniffi. Revisit uniffi-bindgen-cs if the ABI passes about 40 functions. | Medium | https://github.com/Cysharp/csbindgen |
| 7 | CI runner | `runs-on: windows-2025-vs2026` (the `windows-latest` label points there). .NET SDK 10.0.401, Windows SDK 26100, Rust 1.98.1, Visual Studio 2026 18.10 with ARM64 tools. | High | https://github.com/actions/runner-images/blob/main/images/windows/Windows2025-VS2026-Readme.md |
| 8 | `dotnet build` of WinUI 3 without Visual Studio MSBuild | Microsoft's own WinUI CI page still uses VS MSBuild. The 2026 `winapp` CLI and templates build with the .NET SDK. Use `dotnet build` for compile checks. Use VS `msbuild` for the MSIX step until a spike proves `dotnet`. | Medium | https://learn.microsoft.com/en-us/windows/apps/get-started/start-here |
| 9 | Interop library and tests on macOS and Linux | Yes. `StoryArc.Interop` is plain `net10.0`, so `dotnet build` and `dotnet test` work on any OS with the .NET 10 SDK. Both GitHub runners already carry SDK 10.0.x. Not run here. | Medium | https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md |
| 10 | Store | Free registration for individuals and companies. Store signs the MSIX. Canonical channel. | High | https://blogs.windows.com/windowsdeveloper/2025/09/10/free-developer-registration-for-individual-developers-on-microsoft-store/ |
| 11 | winget | Ride the Store listing first. Add a `microsoft/winget-pkgs` manifest only if a signed direct installer ever exists. | Medium | https://learn.microsoft.com/windows/package-manager/package/repository |
| 12 | Unsigned dev builds and sideload | Dev: `winapp run` (loose-layout identity, Developer Mode on) or `dotnet publish` unpackaged. Sideload: MSIX must be signed with a trusted certificate. Use `winapp cert generate`. | High | https://learn.microsoft.com/en-us/windows/apps/dev-tools/winapp-cli/usage |
| 13 | Secrets from Rust on Windows | **keyring v4** with `windows-native-keyring-store` (uses `CredWrite` through `windows-sys`). Store secrets as bytes. Keep each blob under 2560 bytes. | Medium | https://github.com/open-source-cooperative/windows-native-keyring-store |
| 14 | SMB on Windows and Linux | **In-app Rust SMB client**, not the OS redirector. First choice: `smb` 0.12.x. Watch: `smb2` 0.27.x. Add an SMB 1 probe for the named remedy. | Medium | https://github.com/afiffon/smb-rs |
| 15 | Shared desktop EPUB renderer | **Readium ts-toolkit**: `@readium/navigator` 2.11.1, `@readium/shared` 2.7.0, pinned exactly. Not foliate-js. The core must supply the manifest and the positions list. | Medium | https://github.com/readium/ts-toolkit |
| 16 | Serving EPUB resources without a socket | WKWebView: `WKURLSchemeHandler`. WebView2: custom scheme plus `WebResourceRequested` (virtual-host mapping serves folders only). WebKitGTK: `webkit_web_context_register_uri_scheme`. | Medium | https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/working-with-local-content |
| 17 | PDF on Windows and Linux | **pdfium-render 0.9.4** with a bundled PDFium from `pdfium-binaries`, pinned to `chromium/7881`. One path for both OSes. `Windows.Data.Pdf` has no text API, so it fails the `ebook-reader` spec. | High | https://github.com/ajrcarey/pdfium-render |
| 18 | RAR from Rust | **Vendored libarchive 3.8.9 compiled by the `cc` crate** behind a small hand-written FFI. Same 26 sources, same `pin.json`. Not a crate. | Medium | https://github.com/libarchive/libarchive |
| 19 | Arm64 | Build both `x86_64-pc-windows-msvc` and `aarch64-pc-windows-msvc`. Every chosen component has an arm64 build. | Medium | https://github.com/bblanchon/pdfium-binaries/releases |

## 1. Windows App SDK, .NET, project shape

Facts.

- **Known.** Stable channel: **2.5.1**, released 2026-09-16. Servicing level "Current". The 2.0 line shipped 2026-04-29 on semantic versioning. Stable majors come at most every six months, with minor releases about monthly (2.1.3 May, 2.2.0 June, 2.3.1 July, 2.4.0 August, 2.5.1 September).
- **Known.** 1.8 is in "Maintenance" with end of servicing on 2026-09-24. 1.7 and older are out of support.
- **Known.** The package family name changes with each major version. A 3.0 release would use a v3 family.
- **Known.** The Windows App SDK still runs back to Windows 10 1809, but Microsoft supports it only on Windows releases still in servicing.
- **Known.** .NET 10 is LTS. Latest runtime 10.0.12 (2026-09-08). End of life 2028-11-14.
- **Known.** The official template (`SingleProjectPackagedApp`) uses `net10.0-windows10.0.26100.0`, `Platforms` x86;x64;ARM64, `UseWinUI`, `EnableMsixTooling`, and three package references: `Microsoft.WindowsAppSDK`, `Microsoft.Windows.SDK.BuildTools`, `Microsoft.Windows.SDK.BuildTools.WinApp`. Release builds set `PublishReadyToRun` and `PublishTrimmed`. They do not set `PublishAot`.
- **Known.** The `dotnet new` pack is `Microsoft.WindowsAppSDK.WinUI.CSharp.Templates`. Latest version 0.0.7-alpha (still alpha). Short names: `winui`, `winui-mvvm`, `winui-navview`, `winui-tabview`. It merged on 2026-05-18. The Learn quickstart now recommends the `winapp` CLI (public preview, 0.7.1 on 2026-10-01): `winapp new --name X --template winui`, then `winapp run`.
- **Known.** The template default for `targetPlatformMinVersion` is `10.0.26100.0`. The choices run from 17763 to 28000.
- **Known.** Release notes: `SystemBackdropElement` (Mica or Acrylic anywhere in XAML) arrived in 2.0. `TitleBar` drag-region APIs (`IsDragRegion`, `AutoRefreshDragRegions`, `RecomputeDragRegions`) arrived in 2.1.3. `NavigationView` has crash fixes in 2.5.1 and no breaking changes in 2.0 to 2.5.1. `TabView` is a template (`winui-tabview`).
- **Reported.** Mica Alt (tabbed title bar look) needs Windows 11 build 22621 or later. Base Mica needs 22000.
- **Reported.** Native AOT for WinUI 3 arrived in Windows App SDK 1.6. The Release notes for 2.x do not mention it. The templates do not enable it.
- **Inferred.** Ship ReadyToRun plus trimming (the template default). Try `PublishAot` in a spike only after the curl and the interop layer run. Trimming needs the C# side of the seam to avoid reflection: this is a second reason to prefer csbindgen over uniffi.

Floor decision.

- Windows 11 servicing ends: 23H2 Home and Pro ended 2025-11-12. 24H2 Home and Pro end 2026-10-14. 25H2 ends 2027-10-13. 26H1 and 26H2 are current (**Known**, Microsoft lifecycle page).
- Build 26100 is the template default and the CI image SDK. CI can build against it and run tests on it. A floor of 22621 would need a real 22H2 device or VM to back the claim.
- Recommendation: floor 10.0.26100.0. Re-open if users report 23H2 devices. Cost of the lower floor: test on an older VM, and check the Mica Alt fallback.

## 2. Win2D and the D3D11 path

- **Known.** `Microsoft.Graphics.Win2D` latest is **1.4.0**, published 2026-03-16. Its only dependency is `Microsoft.WindowsAppSDK.WinUI >= 1.8.260204000` with **no upper bound**.
- **Known.** The Win2D repository default branch is `winappsdk/main`. Its last merged pull request is 2026-03-12 ("Reference WinUI only instead of WASDK"). The README still says the transition is "in progress". The GitHub releases page is empty. Open issue 1000 is "Update to WinAppSDK 1.8".
- **Known.** No release, tag or issue says Win2D runs on 2.x. NuGet will restore it on 2.x because the range is open.
- **Inferred.** Restore success does not prove the native `Microsoft.Graphics.Canvas.dll` activates against the 2.x WinUI package. The 2.x line uses a new package family. Treat Win2D on 2.x as unproven.
- **Known.** Starting on 1.8 is closed: 1.8 left servicing on 2026-09-24.
- **Known.** `ISwapChainPanelNative` exists for WinUI 3 (`microsoft.ui.xaml.media.dxinterop.h`). `SetSwapChain` must run on the UI thread. `ISwapChainPanelNative2::SetSwapChainHandle` exists for the composition-handle variant.
- **Known.** NuGet has current wrappers: `Vortice.Direct3D11` 3.8.3 (stable), `ComputeSharp.D2D1.WinUI` 3.2.0.
- **Correction to the Windows README.** The old risk "pins the app to the 1.8 line, or forces raw D3D11 on 2.x" resolves to the second branch.

Recommendation: skip Win2D. Write the ADR-0009 projection as an HLSL pixel shader. Run it with Direct3D 11 through Vortice (or TerraFX) on a dedicated render thread. Present into a `SwapChainPanel`. Keep input on `CreateCoreIndependentInputSource`. The first spike keeps its exit criterion: sustained present at monitor rate on a 120 Hz display. Cost: more code than Win2D. No XAML effect pipeline is involved, so no version skew.

## 3. Rust core to C#

Facts.

| Option | Maintained in 2026 | Native AOT and trimming | Async and callbacks | Records and errors | Cargo inside MSBuild | Arm64 |
| --- | --- | --- | --- | --- | --- | --- |
| **uniffi-rs** 0.32.2 (2026-09-23) with **uniffi-bindgen-cs** 0.11.0 | Weak. The C# generator targets uniffi **0.31.0** (released 2026-06-23). Issues 176 and 183 ask for 0.32 and are open. An April 2026 issue (172) asked who maintains it. A "merge outstanding pull requests" pass closed in June. | Unproven on Windows. Open issue 175 reports a callback-interface crash under full AOT on iOS and Mac Catalyst (the generator uses `Marshal.GetFunctionPointerForDelegate`). Two issues about emitting `LibraryImport` on .NET 8+ closed in June 2026 (merge status not checked). | Has an `Async.cs` template (Task). Open issue 165: async callback interfaces generate sync return types. | Strong: records, enums, errors, objects, callbacks all have templates. | No | Via cargo target |
| **csbindgen** 1.9.8 (2026-05-20, repository pushed 2026-10-07, MIT) | Good (Cysharp) | Good: emits `DllImport` with blittable types and `delegate* unmanaged[Cdecl]` callbacks. No reflection. | Callbacks as function pointers. No async. You wrap it. | None. Primitives and pointers only, by design. | `build.rs` writes the `.cs` file | Via cargo target |
| **Hand-written `LibraryImport`** | n/a | Best (source-generated marshalling) | Same as csbindgen | None | n/a | n/a |
| **cbindgen** 0.29.4 | Good | n/a | n/a | n/a | n/a | n/a |

All **Known** (generator repositories, issues and crates.io, read 2026-10-07), except the AOT column for Windows, which is **Inferred**.

Recommendation.

1. Design one small C ABI. Rules: opaque handles (`StoryArcHandle*`), caller-owned byte buffers or Rust-owned buffers freed by one `storyarc_buffer_free`, UTF-8 JSON for records (parsed on the C# side with `System.Text.Json` source generation, so no reflection), integer error codes plus `storyarc_last_error` for the message, and a `storyarc_cancel(token)` call.
2. Keep the contract that exists: `storyarc_core_version()` returns a static NUL-terminated pointer the caller never frees.
3. Generate the C# `DllImport` file from the Rust source with csbindgen in `build.rs`. One source of truth. No drift.
4. Wrap handles in `SafeHandle` subclasses. Run blocking core calls on `Task.Run` with a `CancellationToken` mapped to `storyarc_cancel`. Make callbacks `[UnmanagedCallersOnly]` static methods.
5. Reasons against uniffi today: the generator lags one minor behind uniffi-rs, review capacity is thin, and the async-callback and AOT bugs are open. Reasons for uniffi later: a large record-heavy surface. The switch costs one rewrite of the wrapper layer, not of the core.

Cargo inside MSBuild. **Known**: no maintained NuGet package does it (searched NuGet for cargo and MSBuild integrations). **Inferred**: use one `Exec` target.

```xml
<PropertyGroup>
  <CargoTarget Condition="'$(Platform)' == 'ARM64'">aarch64-pc-windows-msvc</CargoTarget>
  <CargoTarget Condition="'$(Platform)' != 'ARM64'">x86_64-pc-windows-msvc</CargoTarget>
  <CargoProfile Condition="'$(Configuration)' == 'Release'">release</CargoProfile>
  <CargoProfile Condition="'$(Configuration)' != 'Release'">debug</CargoProfile>
  <CargoFlags Condition="'$(CargoProfile)' == 'release'">--release</CargoFlags>
</PropertyGroup>
<Target Name="BuildStoryArcFfi" BeforeTargets="BeforeBuild" Condition="'$(SkipCargo)' != 'true'">
  <Exec Command="cargo build -p storyarc-ffi $(CargoFlags) --target $(CargoTarget)" WorkingDirectory="$(RepoRoot)" />
</Target>
<ItemGroup>
  <None Include="$(RepoRoot)target\$(CargoTarget)\$(CargoProfile)\storyarc_ffi.dll"
        Link="storyarc_ffi.dll" CopyToOutputDirectory="PreserveNewest" />
</ItemGroup>
```

The repository command `pnpm test:desktop:interop` builds the host-target library without `--target`. Its output is `target/debug/…`. The test project copies the host library by glob (`storyarc_ffi.dll`, `libstoryarc_ffi.so`, `libstoryarc_ffi.dylib`). The cdylib names match what .NET probes for `DllImport("storyarc_ffi")` (**Known**: .NET adds the platform prefix and suffix).

## 4. CI

- **Known.** `windows-latest`, `windows-2025` and `windows-2025-vs2026` map to one image: Windows Server 2025 build 26100 with **Visual Studio Enterprise 2026 18.10**. Image 20260925.250.1. .NET SDKs 8.0.x, 9.0.x, 10.0.112, 10.0.204, 10.0.303, **10.0.401**. Windows SDK 10.0.26100. Rust and Cargo 1.98.1. Component `WindowsAppSdkSupport.CSharp` is installed. `VC.Tools.ARM64` is installed. Docker, Node 22.23.3, Git 2.55 are present.
- **Known.** A second file in the repository, `Windows2025-Readme.md`, still describes a Visual Studio 2022 image. Pin `windows-2025-vs2026` so the image cannot change under the workflow.
- **Known.** `windows-11-arm` (Arm64) moves to a Visual Studio 2026 image in September 2026.
- **Known.** `ubuntu-24.04` carries .NET SDK 10.0.401 and Rust 1.98.1. The macOS 15 Arm64 image carries .NET SDK 10.0.400 (the macOS 26 image behind `macos-latest` was not read). Ubuntu and macOS need no .NET setup step; pin the SDK with `global.json` anyway.
- **Known.** Microsoft's WinUI CI page (updated 2026-08-30) shows `microsoft/setup-msbuild` plus `msbuild` for restore, build and package. It still names .NET 8 in its sample. For unpackaged apps it says: use `dotnet publish`.
- **Known.** `winapp` CLI has a GitHub Action, `microsoft/setup-winapp@v1`, and `winapp run`, `winapp pack` need only the .NET SDK. "Visual Studio: Optional (winapp is standalone)".
- **Inferred.** `dotnet build -c Release -p:Platform=x64` on a single-project WinUI app compiles on the runner without `setup-msbuild`, because the templates add `Microsoft.Windows.SDK.BuildTools` and `Microsoft.Windows.SDK.BuildTools.WinApp` through NuGet. No source says "supported for CI". The spike must run it once.
- **Known.** A packaged build needs `/p:GenerateAppxPackageOnBuild=true`. Store upload needs `/p:UapAppxPackageBuildMode=StoreUpload`.
- **Known, with a conflict.** The single-project page says it "doesn't currently support producing MSIX bundles". The CI page shows a Store bundle with `AppxBundlePlatforms="x86|x64"` and `AppxBundle=Always`. The spike resolves it. Fallback: the MSIX Bundler GitHub Action, or one upload per architecture.

Commands for `.github/workflows/desktop-windows.yml` (path-filtered to `apps/desktop-core/**`, `apps/desktop-windows/**`, `Cargo.*`, `third_party/libarchive/**`).

```yaml
runs-on: windows-2025-vs2026
steps:
  - uses: actions/checkout@v4          # check for the current major
  - run: rustup target add aarch64-pc-windows-msvc
  - run: cargo test -p storyarc-core -p storyarc-ffi
  - run: dotnet test apps/desktop-windows/tests/StoryArc.Interop.Tests -c Release
  - run: dotnet build apps/desktop-windows/src/StoryArc.Windows -c Release -p:Platform=x64
  - run: dotnet build apps/desktop-windows/src/StoryArc.Windows -c Release -p:Platform=ARM64   # cross-build, build only
```

`dotnet test` of `StoryArc.Interop.Tests` needs the native library first. `pnpm test:desktop:interop` already does `cargo build -p storyarc-ffi` first. Pin the SDK in `global.json` (`10.0.401`, `rollForward: latestFeature`).

Interop on macOS and Linux (**Inferred**, not run): `StoryArc.Interop` and its tests target `net10.0` with no `-windows` suffix and no Windows App SDK reference. `AllowUnsafeBlocks` on. The WinUI project is the only Windows-only project. Run the interop job on `ubuntu-24.04` and `macos-latest` too: it catches ABI drift on the platforms the contributor probably uses.

## 5. Packaging and signing

- **Known.** Store registration costs nothing for individuals (since June 2025, nearly 200 markets, no credit card) and for companies (since May 2026, Entra work accounts, D-U-N-S number speeds approval).
- **Known.** The Store signs the package after submission. Build with `AppxPackageSigningEnabled=false` for the upload. The manifest identity must match the identity Partner Center assigns.
- **Reported.** A full-trust packaged app declares the restricted capability `runFullTrust`, and Store review asks for a justification. Spike item: submit a hello-world MSIX and record the friction.
- **Known.** Sideloaded MSIX must be signed with a certificate the machine trusts. `winapp cert generate --publisher "CN=StoryArc Dev" --install-cert` and `winapp pack --generate-cert --install-cert` make a dev certificate. `winapp run` registers a loose-layout package with identity and needs Developer Mode.
- **Known.** Unpackaged self-contained builds (`dotnet publish`, `WindowsAppSDKSelfContained`) run without a certificate.
- **Reported.** Unsigned or low-reputation binaries trigger SmartScreen and may be blocked by Smart App Control. Plan for it only for direct downloads.
- **Known.** Azure Artifact Signing (generally available 2026-01): public-trust certificates for organisations in the US, Canada, EU, UK, Australia, New Zealand, Japan, South Korea, Singapore, Switzerland, Norway and Israel. **Individuals must be in the US or Canada.** It needs a paid Azure subscription (free, trial and sponsored subscriptions are refused). It issues no EV certificates. This confirms the Windows README claim for EU individuals.
- **Known.** winget accepts MSIX, MSI and EXE installers through pull requests to `microsoft/winget-pkgs`. `winget` CLI is at 1.29.380 (2026-09-21).
- **Reported.** Store apps appear in winget's `msstore` source without a manifest. A direct MSIX manifest in `winget-pkgs` needs a trusted signature (**Inferred**).

Posture: Store listing is canonical. Skip winget manifests until a signing identity exists. Dev builds use `winapp`.

## 6. Secrets from Rust on Windows

- **Known.** `keyring` 4.2.0 (2026-08-29) is now a thin layer over `keyring-core`. Platform backends are separate crates: `windows-native-keyring-store` 1.1.0 (2026-05-24), `dbus-secret-service-keyring-store` 1.0.1 (2026-08-15), `apple-native-keyring-store`, `linux-keyutils-keyring-store`, `zbus-secret-service-keyring-store`. Maintained by Dan Brotsky.
- **Known.** `windows-native-keyring-store` calls `CredWrite` and `CredRead` through `windows-sys` 0.61. It exposes a `CredPersist` choice, converts password strings to UTF-16, and warns that same-entry access from several threads is not sequenced.
- **Known.** The Windows credential blob limit is 2560 bytes. Strings stored as UTF-16 halve that to 1280 characters. **Reported** (secondary sources): large OAuth sessions fail on this limit.
- **Known.** Windows README: `PasswordVault` adds nothing at full trust.

Recommendation: use `keyring` v4 behind one trait, `SecretStore`, in `storyarc-core`. On Windows use `windows-native-keyring-store`. On Linux use `dbus-secret-service-keyring-store` (the Secret Service API reaches GNOME Keyring, KWallet and COSMIC through D-Bus; Flatpak needs `--talk-name=org.freedesktop.secrets`, **Inferred**). Store secrets with the **bytes** API, not the string API. Kavita tokens and OPDS passwords fit in 2560 bytes. Single-thread access per entry, behind a mutex in the core. Direct `CredWrite` is about 80 lines and removes two crates. Take it only if keyring v4 shows churn: **Inferred** ceiling.

Use `CRED_PERSIST_LOCAL_MACHINE` (no roaming, no enterprise sync): secrets stay on the device. Set it explicitly (**Inferred**: check the `CredPersist` default in the spike).

## 7. SMB from the shared core

The obligations (`network-share` spec): SMB 2 and 3; validate and report host unreachable, share not found, authentication rejected, protocol unsupported; refuse SMB 1 and name the setting; negotiate encryption and state whether the connection is encrypted; reconnect; ranged reads.

| Criterion | OS redirector over UNC paths | In-app Rust client |
| --- | --- | --- |
| State encryption | **Known**: WMI `MSFT_SmbConnection` has `Dialect`, `Encrypted`, `Signed`, `ServerName`. It describes live connections only. **Inferred**: a reader needs WMI from C#, and whether it needs elevation is unknown. | **Known**: `smb` exposes the negotiated dialect, the encryption cipher, and capabilities in `ConnectionInfo.negotiation`. `smb2` documents the negotiated dialect and AES-128/256 CCM and GCM encryption. |
| Refuse SMB 1 with a remedy | **Known**: SMB 1 is not installed by default in any Windows 11 edition. The refusal is the OS's, with an OS error. The app can map the error. It cannot name the server setting from a protocol fact. | Neither crate speaks SMB 1 (**Known**: `smb2` lists SMB1 as out of scope; `smb` supports "all SMB 2.X and 3.X dialects"). **Inferred**: add a small SMB 1 negotiate probe on failure to classify "SMB 1 only" and name the server setting, like the mobile apps do. |
| Third-party NAS compatibility | **Known**: Windows 11 24H2 requires SMB signing by default. This blocks guest shares and NAS firmware without signing. The same Microsoft page warns not to disable signing as a workaround. | The client chooses what to offer. Signing can be negotiated per server. Guest access is a decision the app owns. |
| Transient drops, timeouts, cancel | **Inferred**: UNC file I/O can block inside the kernel for a long time on a dead link, so it cannot meet "indicator only if blocked more than 2 seconds" without a watchdog thread. | Full control of timeouts, reconnect, and the 2 and 60 second rules. |
| Credentials | Windows Credential Manager `DOMAIN_PASSWORD` entries (README approach). Not portable to Linux. | Same `SecretStore` as every other secret. One code path on Windows and Linux. |
| Linux | Needs `cifs` mounts (root) or GVfs (not available in a Flatpak sandbox by default). | Works unchanged. |
| Licence and risk | n/a | `smb` 0.12.1 (2026-09-20): MIT (crates.io; GitHub reports "no assertion"), 86 stars, one maintainer, Rust 1.89, edition 2024, pinned `sspi =0.21.3`, release-candidate RustCrypto crates. `smb2` 0.27.2 (2026-10-07): MIT OR Apache-2.0, first release 2026-04-21, 45 releases, 31 stars, Rust 1.85, compound requests and pipelined reads. Both are pre-1.0. |

**Recommendation: in-app client for Windows and Linux.** ADR-0010 rejected libsmb2 over LGPL-2.1 static linking, and that holds. Start the spike with `smb` (older, MIT, wider API). Run the same `scripts/smb-server.sh` fixture suite. Keep `smb2` as the swap-in: put the client behind a core trait, `RandomAccessSource` as ADR-0008 already defines. Gain over the mobile clients: both Rust crates implement SMB 3 encryption, which neither jcifs-ng nor SMBClient does (ADR-0010). The "Encrypted transport" scenario becomes meetable on desktop. Spike exit: read ranges from Samba (Docker), a Windows share, and a real NAS (Synology or QNAP) with `smb encrypt = required`.

## 8. The shared desktop EPUB renderer

### Candidates (all **Known**, read 2026-10-07)

| Criterion | Readium ts-toolkit | foliate-js |
| --- | --- | --- |
| Maintained | Yes. Repository pushed 2026-10-07. `@readium/navigator` 2.11.1 (2026-09-30), `@readium/shared` 2.7.0 (2026-10-01), releases every week or two. | Last push 2026-05-01. "Not stable. Expect it to break and the API to change at any time." No releases. |
| Licence | BSD-3-Clause | MIT |
| Locator model | **Readium `Locator`** (`href`, `locations.progression`, `position`, `totalProgression`, text context). Same model as swift-toolkit and kotlin-toolkit. Navigator accepts locators without `href` and resolves them from `position` or `totalProgression`. | EPUB CFI. Not the Readium model. Needs a converter. |
| Pagination and reflow | `EpubNavigator`: paged, scrolled, two-page spreads, RTL, vertical writing, fixed layout. Styling goes through ReadiumCSS properties (**Reported**: npm `@readium/css` 2.0.5 is the matching package; the dependency was not checked). Preferences editor (font size, line height, spacing, background). | Own paginator (CSS columns). Fewer settings. |
| Fonts and themes | Preferences API plus app CSS properties. Same ReadiumCSS family the mobile apps use. | Manual CSS. |
| Reading order input | Needs a **Readium Web Publication Manifest** and a **positions list**. It has no EPUB container parser. | Parses the EPUB itself (`epub.js` module) through a loader (`loadText`, `loadBlob`, `getSize`). |
| Resource access | Loads each resource by URL through a `Fetcher`. A custom scheme or intercepted `https` host works. | Builds `blob:` URLs for sections (same origin for all content). Its own security note says scripts cannot be isolated this way. |
| Network egress (ADR-0015) | Sets a per-frame CSP that includes `upgrade-insecure-requests`. That does not deny egress. The host still installs its own deny rule. | Needs the host to add CSP. Same duty. |
| Extra | Also ships `DivinaNavigator` (2.11.0) and `AudioNavigator`. Not used here: comics and audio stay native. | PDF.js adapter "highly experimental". |

### Recommendation: ts-toolkit, pinned

- Pin `@readium/navigator@2.11.1` and `@readium/shared@2.7.0` exactly. Bundle with Vite into one JS file committed under `packages/` or built in CI. Record the digest in a `pin.json` like libarchive's. Refresh on a schedule: weekly releases mean fast fixes and fast drift.
- Locators match mobile in shape. **Position numbers match only if the core computes them the same way.** swift-toolkit's `EPUBPositionsService` uses `ceil(archiveEntryLength / 1024)`, minimum 1, where the length is the **archive entry length** (the ZIP compressed size for deflated entries) (**Known**, source read). The Rust ZIP reader already exposes the compressed size from the central directory (ADR-0008). Test against the shared fixtures: same book, same `position` on iOS, Android and desktop.
- **Cost to plan:** the core must build the Web Publication Manifest (reading order, TOC, metadata, `layout`, `readingProgression`) from the OPF, and `positions.json`. swift-toolkit's streamer does this on iOS. No Rust crate does it (**Known**: crates.io has `epub`, `rbook`, `ebook-rs` and none emits a Readium manifest). Budget it as one core module with a shared-corpus test. **Inferred** size: a few hundred lines on top of an XML parser.
- Kavita progress: **Reported/Inferred** that Kavita stores its own page number and an XPath-like scroll id, not a Readium locator. No toolkit syncs through Kavita. The app maps `position` and `totalProgression` to Kavita's fields the same way on all platforms. ADR-0006 keeps the locator local.
- ADR-0015 stays binding. The web view may fetch nothing outside the app's own scheme.

### Serving resources and denying egress, per web view

| Web view | Serve archive resources | Deny everything else |
| --- | --- | --- |
| WKWebView (macOS) | `WKURLSchemeHandler` on a per-publication scheme or host (`storyarc-pub://<uuid>/`, like iOS `readium://<UUID>/`). **Known** API. | `WKContentRuleList` deny-all except the app scheme: **Known**, measured on iOS in ADR-0015 and the same WebKit on macOS. Add a CSP response header. |
| WebView2 (Windows) | **Known**: `SetVirtualHostNameToFolderMapping` maps a host to a **folder on disk** only, so it cannot serve bytes inside an archive. Use `AddWebResourceRequestedFilter` plus the `WebResourceRequested` event, answering with `CoreWebView2WebResourceResponse` over a stream. Register a custom scheme through `CoreWebView2CustomSchemeRegistration` on the environment. **Known costs**: the event runs on the host UI thread and is slower than folder mapping. The doc's sample warns that WebView2 does not dispose response streams. | **Inferred**: (1) CSP header `default-src 'none'; …; connect-src 'none'` on every response served from the archive. (2) `NavigationStarting` cancels anything outside the app scheme. (3) `WebResourceRequested` with filter `*` answers 403 to non-app URLs. WebSockets may bypass `WebResourceRequested`, so the CSP carries that case, as in ADR-0015's Android finding. Measure with the eight-vector page. |
| WebKitGTK (Linux) | **Known**: `webkit_web_context_register_uri_scheme` with a callback that answers through `WebKitURISchemeResponse` (stream and `stream-length`, since 2.36). Ubuntu 24.04 `libwebkitgtk-6.0-4` is 2.52.6 (**Known**); the Rust crate is `webkit6` 0.6.1. **Not found in the docs**: range-request handling and whether subresources of a page loaded through the scheme use it. Spike item. | **Known**: `WebKitUserContentFilterStore` imports JSON rule sets in the WebKit content-blocker format (since 2.24) and `webkit_user_content_manager_add_filter` applies them. The iOS rule list can be reused as is (**Inferred**). Add the CSP header as well. |

Windows runtime: **Reported** that the WebView2 Evergreen Runtime ships with Windows 11. The WinUI 3 `WebView2` control comes with the Windows App SDK. Custom scheme registration needs a custom `CoreWebView2Environment` passed to `EnsureCoreWebView2Async` (**Inferred** from the API shape).

## 9. PDF on Windows and Linux

- **Known.** The `ebook-reader` spec says PDF text selection, in-publication search and the outline "work", renders only the pages needed, and reports geometry in PDF points. A text layer is detected, not assumed.
- **Known.** `Windows.Data.Pdf.PdfDocument` exposes `PageCount`, `IsPasswordProtected`, `GetPage`, `LoadFromFileAsync` and `LoadFromStreamAsync`. It has **no text, search or outline API**. It would force the spec's "device that cannot read PDF text" fallback on every Windows device. It also needs `IRandomAccessStream` (WinRT), which is not available on Linux.
- **Known.** `pdfium-render` 0.9.4 (2026-09-06, MIT OR Apache-2.0, repository pushed 2026-08-16, Rust 1.61): renders pages to bitmaps with `PdfRenderConfig`; has `PdfPageText`, `PdfPageTextSearch`, `PdfPageTextSegments`, `PdfBookmarks`; binds at run time to a PDFium library next to the executable, or links statically with the `static` feature.
- **Known.** `load_pdf_from_reader` takes a `Read + Seek` and "will only load the portions of the document it actually needs into memory". A `RandomAccessSource` adapter gives ranged reads from SMB and HTTP. This meets the "Large PDF" scenario.
- **Known.** PDFium is not thread safe. The `thread_safe` feature serialises every call behind one mutex. Use one dedicated PDF thread instead and keep the feature off, or use the feature and accept the lock.
- **Known.** `bblanchon/pdfium-binaries` (MIT build scripts, repository pushed 2026-10-05) builds PDFium every Monday. Latest `chromium/8086` (2026-10-05). Assets: `pdfium-win-x64.tgz` (3.9 MB), `pdfium-win-arm64.tgz` (3.6 MB), `pdfium-linux-x64.tgz` (3.8 MB), `pdfium-linux-arm64.tgz` (3.7 MB), musl builds, mac builds. PDFium itself is under the Chromium BSD-style licence text (**Known**: the `LICENSE` file read). The tarballs carry third-party licence files: audit them as the libarchive audit did.
- **Known.** `pdfium-render` 0.9.4's `pdfium_latest` feature is `pdfium_7881`. Binaries `chromium/7881` exist (2026-06-08).
- **Inferred.** Pin `chromium/7881`, record its sha256 in a `pin.json`, and bump only with a `pdfium-render` release that raises `pdfium_latest`.
- Flatpak: the PDFium tarball becomes one `archive` source with a sha256 in the manifest (**Inferred**). MSIX: `pdfium.dll` sits beside the executable. Windows needs `pdfium.dll` in the same folder as `storyarc_ffi.dll`.
- Cost: about 3.9 MB per architecture; one C++ binary of Google origin handling untrusted input. `SECURITY.md` already names archive parsing as the largest attack surface; add PDF parsing to that list. Note: mobile uses system PDF libraries (ADR-0005). This is the first bundled PDF engine in the project, and the Linux and Windows apps need it for the same spec.
- Alternative kept in reserve: MuPDF. AGPL, so no.

One path for both OSes: pdfium-render with bundled PDFium. macOS keeps PDFKit through StoryArcKit.

## 10. Archives: RAR from Rust

- **Known** (local files): ADR-0005 chose libarchive 3.8.x for RAR4 and RAR5 decompression only, vendored as 26 `.c` files plus headers under `third_party/libarchive/Sources/CLibarchive`. `pin.json` pins 3.8.9, the tarball sha256, the signing key and a digest of the vendored sources. `config.h` is hand-authored for Apple and Android. Entry names, sizes, solid and encrypted flags come from our own header reader (`RarReader`). The seam is one function, `RarDecoder`. ADR-0008 makes the ZIP and TAR readers our own.
- **Known.** Rust crates for libarchive are the wrong shape. `libarchive3-sys` was last released 2016-06-29, and `libarchive` 2016-03-22. `compress-tools` 0.16.1 (2026-04-23, MIT OR Apache-2.0) is alive but links the **system** libarchive through `pkg-config` or `vcpkg` with the full format set, and is built around extracting whole archives. That reopens the attack surface the vendoring removed and gives a different libarchive on each distro.
- **Recommendation.** Compile the same vendored sources with the `cc` crate (1.6.0) from `apps/desktop-core/storyarc-core/build.rs`, with `third_party/libarchive` as the only source. Hand-write about 10 `extern "C"` declarations (`archive_read_new`, `archive_read_support_format_rar`, `…_rar5`, `archive_read_open2` with read, skip and seek callbacks over `RandomAccessSource`, `archive_read_next_header`, `archive_read_data`, `archive_read_free`). No `bindgen`. The mobile shims (`rar_decoder.c` on Android, the Swift side) already prove the call shape.
- **Inferred, per platform.**
  - Linux: the POSIX `config.h` needs `__linux__` guards (`sys/sysmacros.h` for `major` and `minor`). Same family of change as the existing Android guard.
  - Windows (MSVC): the vendored list includes `archive_windows.h` but not `archive_windows.c`, and the hand-authored `config.h` covers Apple and Android only. A third `config.h` branch for `_WIN32` is required, and `archive_cryptor.c` and `archive_hmac.c` select Windows BCrypt code. Treat this as the biggest risk of this item. The spike compiles it on `windows-2025-vs2026` for x64 and ARM64 and runs the RAR corpus.
- The `pin.json` check (`pnpm libarchive:pin`) keeps one copy of the sources for three build systems: SwiftPM, CMake (Android) and `cc` (desktop).
- Rejected again: `sharpcompress` (UnRAR lineage, see the Windows README), `unrar` crates (UnRAR licence).

## Corrections owed to `apps/desktop-windows/README.md`

The parent decides whether to edit it. This file is the newer source.

1. Windows App SDK is at **2.5.1** (2026-09-16), not "2.0 shipped April 2026" alone. 1.8 left servicing on 2026-09-24. "Start on 1.8" is closed.
2. The Win2D dependency range is **open** (`>= 1.8.260204000`), not same-major. The real unknown is runtime compatibility on 2.x, which no source states.
3. "Resources served in-process via virtual-host mapping" is wrong for archives. Virtual-host mapping serves folders. Use `WebResourceRequested` plus a custom scheme.
4. "`Windows.Data.Pdf` as the posture" conflicts with the `ebook-reader` PDF requirement for text selection, search and outline. Use pdfium-render.
5. "UNC paths through the OS redirector" for SMB: replaced by the in-app client. Reasons: encryption and dialect visibility, Windows 11 24H2 default signing requirement, timeout control, one code path with Linux.
6. "Readium locator model shared" is true, but ts-toolkit needs a manifest and a positions list from the host. Add the work to the core.
7. Floor: Windows 11. Declare 10.0.26100.0.
8. The "Open questions" list item 2 (Windows floor) is answered here. Item 1 (Win2D on 2.x) is answered as "do not wait".

## Spikes this research hands to wave 1 and later

Each has an exit criterion. None runs in wave 0.

1. **Curl on D3D11.** HLSL port of the ADR-0009 shader, `SwapChainPanel`, independent input. Exit: monitor-rate presents on a 120 Hz screen during drag, with a XAML flyout animating.
2. **Seam.** csbindgen generates `NativeMethods.g.cs`. `StoryArc.Interop.Tests` passes on windows, ubuntu and macOS runners. Exit: one `storyarc_core_version()` round trip per OS, plus one buffer round trip and one cancel.
3. **CI build.** `dotnet build` of the WinUI project on `windows-2025-vs2026` without `setup-msbuild`. Exit: green x64 build, ARM64 build, and an MSIX from `msbuild`. Record the bundle question.
4. **Store dry run.** Submit a hello-world MSIX. Exit: certification result and `runFullTrust` friction written down.
5. **SMB.** `smb` against Samba (Docker), a Windows share, and a NAS with encryption required. Exit: dialect and encryption reported, SMB 1-only server refused with the remedy.
6. **EPUB.** ts-toolkit in WebView2 with a custom scheme. Exit: pagination works, the eight-vector egress page shows 0 arrivals, a saved locator round-trips with the iOS and Android `position` for the same book.
7. **PDF.** pdfium-render over a `RandomAccessSource` with the `chromium/7881` binary on Windows and Linux. Exit: first page of a 300 MB PDF over SMB without a full transfer; search and outline work.
8. **RAR on MSVC.** `cc` build of the vendored libarchive for x64 and ARM64. Exit: the RAR corpus passes byte-identically.
9. **Win2D on 2.x (optional).** Only if the D3D11 path stalls: restore Win2D 1.4.0 on WinAppSDK 2.5.1 and open a `CanvasSwapChainPanel`. Exit: a written yes or no.

## Not verified

- No .NET SDK on the research machine. No .NET command, no WinUI build, no interop test ran.
- No Windows machine. No Store submission, no SMB test, no WebView2 egress measurement.
- The Win2D, dotnet-without-Visual-Studio, libarchive-on-MSVC and WebKitGTK range-request points are **Inferred** or unknown, as marked.
- Release notes for Windows App SDK were read through a summarising fetch. Dates and version numbers were cross-checked against the downloads and release-channels pages. Feature attributions (TitleBar, SystemBackdropElement) come from the summary only. Re-read the release notes before quoting them in an ADR.
- Not rechecked: SignPath Foundation terms and the "three years of tax history" rule for Artifact Signing organisations (the Windows README states both).

## Sources

- Windows App SDK: https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-channels, …/downloads, …/support, …/release-notes/windows-app-sdk-2-0, …/single-project-msix
- Templates and CLI: https://github.com/microsoft/WindowsAppSDK/pull/6407, https://learn.microsoft.com/en-us/windows/apps/get-started/start-here, https://learn.microsoft.com/en-us/windows/apps/dev-tools/winapp-cli/usage
- CI: https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/ci-for-winui3, https://github.com/actions/runner-images
- Win2D: https://github.com/microsoft/Win2D, https://www.nuget.org/packages/Microsoft.Graphics.Win2D/1.4.0
- SwapChainPanel interop: https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/win32/microsoft.ui.xaml.media.dxinterop/nn-microsoft-ui-xaml-media-dxinterop-iswapchainpanelnative
- Seam: https://github.com/NordSecurity/uniffi-bindgen-cs (issues 165, 172, 175, 176, 183), https://github.com/mozilla/uniffi-rs, https://github.com/Cysharp/csbindgen
- Store and signing: https://blogs.windows.com/windowsdeveloper/2025/09/10/free-developer-registration-for-individual-developers-on-microsoft-store/, https://blogs.windows.com/windowsdeveloper/2026/05/07/publish-to-microsoft-store-as-a-company-now-with-free-registration-and-faster-onboarding/, https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart, https://learn.microsoft.com/en-us/azure/artifact-signing/faq, https://learn.microsoft.com/windows/package-manager/package/repository
- Windows lifecycle: https://learn.microsoft.com/en-us/lifecycle/products/windows-11-home-and-pro
- Secrets: https://docs.rs/crate/keyring/4.2.0, https://github.com/open-source-cooperative/windows-native-keyring-store
- SMB: https://github.com/afiffon/smb-rs, https://github.com/vdavid/smb2, https://learn.microsoft.com/en-us/previous-versions/windows/desktop/smb/msft-smbconnection, https://learn.microsoft.com/en-us/windows-server/storage/file-server/troubleshoot/detect-enable-and-disable-smbv1-v2-v3
- EPUB: https://github.com/readium/ts-toolkit, https://github.com/johnfactotum/foliate-js, https://github.com/readium/swift-toolkit (`EPUBPositionsService.swift`), https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/working-with-local-content, https://webkitgtk.org/reference/webkitgtk/stable/
- PDF: https://github.com/ajrcarey/pdfium-render, https://docs.rs/pdfium-render/0.9.4, https://github.com/bblanchon/pdfium-binaries, https://learn.microsoft.com/en-us/uwp/api/windows.data.pdf.pdfdocument
- Archives: https://crates.io/crates/compress-tools, https://crates.io/crates/libarchive3-sys, `third_party/libarchive/VENDORING.md`, `docs/decisions/0005-…`, `0008-…`, `0010-…`, `0015-…`
