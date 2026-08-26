# StoryArc for Windows — planned, not implemented

**Status:** documented only. No code. The framework choice remains **Assumed**
— WinUI 3 — but the spike questions have now been researched on paper
(August 2026), so the spike is smaller and more sharply aimed. See
[ADR-0004](../../docs/decisions/0004-desktop-strategy.md).

Confidence labels follow
[ADR-0005](../../docs/decisions/0005-format-and-rendering-libraries.md):
**Known** is verified against the vendor's own documentation or source,
**Reported** is a credible secondary source, and nothing below is **Proven**
until a spike runs it on real hardware.

## What changed since ADR-0004 wrote the questions

Three decisions landed after this document was first written, and each one
reshapes a Windows question:

- [ADR-0009](../../docs/decisions/0009-page-curl-as-a-fragment-shader.md) —
  the curl is one fragment shader over two decoded page textures, no mesh, no
  re-raster. "Does WinUI 3 hold 120 Hz" narrows to "can it run a custom
  two-texture fragment shader, driven per-frame by pointer input, at monitor
  refresh". That narrower question is answerable on paper, and is answered
  below.
- [ADR-0008](../../docs/decisions/0008-ranged-reads-and-own-zip-reader.md) —
  the format layer is ranged reads over `RandomAccessSource`, with our own ZIP
  and TAR readers, mirrored deliberately between the two mobile apps. A
  Windows implementation is a **third mirror of the drift hotspot, in a third
  language**. That is the real recurring cost of this target, and it is also
  the strongest argument Avalonia has (one new mirror instead of two).
- [ADR-0005](../../docs/decisions/0005-format-and-rendering-libraries.md) —
  the RAR answer is vendored libarchive, chosen because everything
  UnRAR-derived carries a non-OSI licence. The same criterion disqualifies the
  obvious .NET library — see the format table.

## Leading candidate: WinUI 3 (Windows App SDK)

Healthier in 2026 than its 2024 reputation, with the caveats named. Windows
App SDK 2.0 shipped April 2026 on semantic versioning with monthly servicing
(**Known**); Build 2026 recommitted to WinUI as the path for new native
Windows apps, and the open-sourcing plan reached Phase 3 in May 2026
(**Reported**). Against that: issue triage is backlogged, there is no visual
designer, and users still report XAML-side animation jank in 2026
(**Reported**). The curl path below routes around the janky layer rather than
depending on it.

### The curl question, answered on paper

The obvious route is the wrong one, and the right one is documented:

- **Composition brushes are a dead end.** `CompositionEffectBrush` cannot host
  custom shaders — effect graphs compile only against the built-in effect set,
  and Win2D's `PixelShaderEffect` is marked `[NoComposition]` (**Known**).
- **A D2D1 custom pixel shader is first-class.** Win2D's `PixelShaderEffect`
  takes up to 8 texture inputs and per-frame constants; the curl's non-1:1
  sampling is covered by its `SamplerCoordinateMapping` modes (**Known**).
  ComputeSharp.D2D1 authors the same shaders in C# and is production-proven in
  Paint.NET (**Known**).
- **The host is a swap chain, not the XAML frame timer.** `SwapChainPanel`
  exists precisely so real-time content can present independently of the XAML
  refresh timer, and `CreateCoreIndependentInputSource` delivers pointer, pen
  and touch on a background thread — input and render both off the UI thread
  (**Known**). The 2021-era 60 Hz cap bugs are closed; a Win2D swap chain has
  been reported running far above monitor rate while XAML struggled in the
  same app (**Reported**).

So the shape is: two decoded pages as textures → the ADR-0009 projection as a
D2D1 pixel shader → presented each frame from a dedicated render thread fed by
the independent input source. This is more machinery than iOS's
`Rectangle().fill(shader)` — a real cost, recorded rather than smoothed over.

**The sharpest risk is version skew, not capability:** Win2D 1.4.0
(March 2026) still targets Windows App SDK 1.8, and WinAppSDK packages enforce
same-major dependency ranges — so the least-machinery shader path currently
pins the app to the 1.8 line, or forces raw D3D11 on 2.x (**Known/Inferred**).
The spike must settle which line StoryArc-Windows starts on.

### The format layer on .NET

| Need | Answer | Licence | Confidence |
| --- | --- | --- | --- |
| ZIP (CBZ, EPUB container) | **Our own reader**, third mirror: `System.IO.RandomAccess` offset reads + raw-inflate `DeflateStream` over a self-written bounded sub-stream — the BCL's own internal `ZipArchive` pattern | — | **Known** — primitives verified; pitfalls listed below |
| TAR (CBT) | **Our own `TarReader`**, third mirror | — | **Known** — trivial by design |
| RAR (CBR) | **Vendored libarchive** behind a small custom P/Invoke layer (~300 lines: `archive_read_open2` + read/seek/skip callbacks bridging `RandomAccessSource`) | BSD-2-Clause | **Known** — same library, same reasoning as mobile |
| 7-Zip (CB7) | — | — | **Not supported**, per ADR-0005. Refused by name |
| EPUB | **Readium ts-toolkit** (`@readium/navigator`) inside **WebView2**, resources served in-process via virtual-host mapping — inside the one sanctioned web-view exception | BSD-3-Clause | **Reported** — actively released; locator model shared with the Swift and Kotlin toolkits |
| PDF | **`Windows.Data.Pdf`** (system) — render-to-image only, exactly Android's `PdfRenderer` posture | Windows SDK | **Known** — no text layer, ever; PDFium (BSD) is the upgrade path if that changes |
| Image decoding | **WIC** via `BitmapDecoder` + `BitmapTransform` — decode-time downsampling, the ImageIO/`ImageDecoder` analogue | Windows SDK | **Known** — but AVIF/HEIC/JXL are optional Store extensions, HEVC is paid; feature-detect at runtime |
| SMB | **No client library.** UNC paths through the OS redirector; `RandomAccess.Read` at offsets is the ranged read | — | **Inferred** — see below |

**SharpCompress is disqualified for RAR, checked at the source.** Its RAR5
decoder is a mechanical port of the official unrar C++ sources — the files are
named after unrar's own (`Unpack.unpack50_cpp.cs`, …), the repository vendors
`reference/unrar` as the porting reference, and its legacy RAR path descends
from the NUnrar/JUnrar lineage (**Known**). That is the exact heritage this
project rejected junrar for, and the top-level MIT licence does not launder
it. The libarchive row above is the answer, mirroring mobile.

**Own-ZIP-reader pitfalls found in advance** (**Known**): the BCL's bounded
`SubReadStream` is internal, so we write our own or `DeflateStream` reads past
the slice; no public `DeflateStream` overload takes an expected size, so
decompression bombs are bounded by capping bytes read out; Deflate64 has no
public raw API — refused by name like CB7; CRC-32 comes from
`System.IO.Hashing`, not the BCL core.

### SMB — the OS does it, with one spec tension

A full-trust Windows app opens `\\server\share\file.cbz` with plain file I/O;
offset reads map to SMB READ-at-offset natively, so ADR-0008 costs nothing
here (**Inferred**). Credentials follow the platform idiom: prompt with
`CredUIPromptForWindowsCredentials`, persist via `CredWrite` as a domain
credential, and the redirector uses it from then on — the app never touches
the password again (**Reported**). Persist UNC paths, never drive letters.

The tension: [`network-share`](../../docs/openspec/specs/network-share/spec.md)
requires stating whether the connection is encrypted and refusing SMB 1 with a
named remedy — obligations written for an in-app client with protocol
visibility. Whether the OS redirector surfaces dialect and encryption to the
app (WMI `MSFT_SmbConnection` or equivalent) is **unverified** and belongs in
the spike; if it cannot, that is a spec conversation, not a silent softening.

### Packaging, signing, and the one hard constraint

MSIX packaging is **not** a sandbox problem: a packaged WinUI 3 app runs full
trust — raw Win32 paths after a folder pick, no `FutureAccessList`, no
`broadFileSystemAccess`, and the WASDK 2.0 pickers return plain path strings
(**Known**). Scanning avoids `Windows.Storage` entirely for its documented
bulk-enumeration slowness (**Known**). `FileSystemWatcher` overflows discard
changes and demand a rescan — which is the architecture the specs already
require — and the USN journal is disqualified outright (requires
administrator) (**Known**).

The hard constraint is **code signing, not sandboxing**:

| Channel | Cost | Catch |
| --- | --- | --- |
| Microsoft Store | Free — registration fees removed in 2025, Store signs the MSIX | Certification discretion; the cheapest respectable channel (**Known**) |
| winget → Store package | Free | Rides the Store signature (**Known**) |
| Sideloaded MSIX / `.appinstaller` | Needs a publicly trusted certificate | Azure Artifact Signing is **closed to EU-based individuals** (US/Canada only; organisations need 3 years of tax history) (**Known**) |
| SignPath Foundation | Free for qualifying OSS | Publisher name shows as SignPath Foundation, not StoryArc (**Known**) |

Posture to validate in the spike: Store-signed MSIX as canonical, the same
package through winget, direct download later only if a signing identity
materialises.

### Spec reinterpretations this target owes

The capability specs are platform-neutral in obligation and mobile in
vocabulary. The Windows readings, to be proposed as spec deltas when this
target starts (`/opsx:propose`, per the workflow):

| Spec wording | Windows reading |
| --- | --- |
| Finger-tracked curl, pinch, tap zones | Pointer drag; Ctrl+scroll / trackpad pinch; click zones — keyboard is already mandated |
| Screen does not auto-lock while reading | `SetThreadExecutionState` display-required |
| Backgrounded / killed by the system | Window close, focus loss, quit, crash — the 15 s progress-write cadence stays load-bearing |
| Secrets in the platform secure store | Credential Manager via `CredWrite` (`CRED_TYPE_GENERIC` for Kavita tokens); `PasswordVault` adds nothing at full trust (**Known**) |
| Share sheet for diagnostic export | Save-to-file + reveal in Explorer; the show-before-it-leaves and redaction rules stand |
| Metered / data saver | The Windows metered-connection flag |
| Excluded from device backups | No API equivalent — a location choice plus documentation |
| Media controls for read-aloud | System Media Transport Controls |
| File handling | `windows.fileTypeAssociation` in the manifest; UCPD means the app can register but never set itself default programmatically (**Known**) |
| Screen readers | Narrator and NVDA replace VoiceOver/TalkBack |

One more inherited cost: `packages/design-tokens` gains a third emitter
(`StoryArcTokens.cs`), per
[ADR-0007](../../docs/decisions/0007-design-token-pipeline.md)'s pattern.

## Runner-up: Avalonia

Stronger in 2026 than when ADR-0004 recorded it: MIT, funded (a three-year
Devolutions sponsorship), the 60 FPS render cap lifted in 12.1 for
non-default Windows modes, a WebView open-sourced in 12.0 (WebView2 on
Windows), and the curl is expressible as an SKSL `SKRuntimeEffect` with two
image children inside a render-thread `CompositionCustomVisualHandler` — an
officially documented pattern (**Known**).

Still the wrong default for StoryArc, for the original reason sharpened by
research: every control is a Skia-drawn lookalike — context menus, scrollbars,
popups, text rasterisation — and the **default** Windows composition mode has
conflicting evidence about ever compositing above 60 Hz (**Known**,
unresolved). Its real argument is unchanged and honest: one C# implementation
would cover Windows *and* Linux, making one new format-layer mirror instead of
two. If the WinUI 3 spike fails its exit criteria, Avalonia's spike (in
[the Linux document](../desktop-linux/README.md), which it would share) is the
fallback — run against the same criteria.

## Rejected — unchanged

| Option | Why |
| --- | --- |
| .NET MAUI | On Windows it renders through WinUI 3 anyway — an extra layer, no extra capability |
| Electron / Tauri + web UI | Fails the native-feel requirement, and `native-experience` forbids web-view UI outside reflowable EPUB |
| WPF | Maintenance mode for new Fluent work |

## The spike, sharpened

Each item has an exit criterion; together they settle the ADR-0004 "assumed".

1. **Curl loop** — SwapChainPanel + independent input source + two-texture
   D2D1 shader on a dedicated thread. *Exit:* sustained presents at monitor
   rate on a 120 Hz display during continuous drag, unaffected by a XAML
   flyout animating simultaneously.
2. **Shader port** — the ADR-0009 projection as HLSL (Win2D) and as
   ComputeSharp.D2D1, `SamplerCoordinateMapping` chosen deliberately. *Exit:*
   output matches the iOS reference render; constants update per frame without
   allocation.
3. **SDK line** — Win2D 1.4 against WinAppSDK 2.x: record the failure or
   success, and the migration cost of starting on 1.8 vs raw D3D11 on 2.x.
   *Exit:* a written decision.
4. **Format layer** — libarchive P/Invoke over `RandomAccessSource` (local +
   ranged HTTP), own ZIP reader against the shared corpus in
   `packages/test-fixtures`, including the hostile fixtures. *Exit:*
   byte-identical pages versus both mobile implementations.
5. **EPUB** — `@readium/navigator` in WebView2, archive-served resources, no
   localhost socket. *Exit:* pagination works and a saved locator round-trips
   against the locator the mobile toolkits produce.
6. **SMB + credentials** — packaged app, UNC ranged reads on a real NAS, the
   CredUI → `CredWrite` flow, dialect/encryption visibility. *Exit:* zero
   prompts after reboot; a definitive answer on the encryption-status
   obligation.
7. **Distribution** — free Store registration → signed MSIX → winget manifest.
   *Exit:* install and auto-update on a clean VM; certification friction
   recorded.

## Open questions research could not close

1. When Win2D ships a WinAppSDK 2.x build — no public roadmap (**unknown**).
2. The Windows floor: docs still say Windows 10 1809+, but Windows 10 left
   support in October 2025. Likely Windows 11 only; needs an ADR-0003-style
   decision when the target starts.
3. Native AOT across the full stack (WinUI 3 + Win2D/ComputeSharp together) —
   each claims support, the combination is unproven.
4. Whether Store certification treats a comic reader's user-provided content
   as needing extra review.

## Do not start this

Until both mobile apps have shipped a 1.0. The research above makes the spike
cheaper; it does not make it due sooner.
