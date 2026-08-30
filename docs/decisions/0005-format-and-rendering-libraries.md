---
status: proposed
date: 2026-08-24
deciders: Cédric Meyer
---

# ADR-0005 — Format and rendering libraries per platform

**Proposed.** Every library is **chosen**, and the format libraries are now
**proven** rather than assumed: RAR, TAR, PDF and image decoding all read real
files on both platforms, asserted against a shared corpus. What remains is EPUB
(Readium, blocked on a reader view existing) and the SMB connectors. See *What
still blocks acceptance* at the end.

**One decision changed on contact with reality.** libarchive was picked for CBR
*and* CBT. CBT does not need it — TAR is 512-byte blocks with fixed-offset ASCII
fields and no compression, so it is read by hand on both platforms, the same
reasoning [ADR-0008](0008-ranged-reads-and-own-zip-reader.md) applies to ZIP. The
same turned out to be true of RAR *headers*, which carry no compression either:
everything indexing needs is readable without a decoder. libarchive's scope
therefore shrank from "two formats" to one function — decompressing a RAR entry —
and 26 of its 132 sources are vendored rather than all of them. Recorded in
[VENDORING.md](../../third_party/libarchive/VENDORING.md).

**One finding changed what can be promised.** libarchive does not implement solid
RAR4 at all, so such a file is refused rather than download-only. Solid RAR5 reads
completely. That is why the streaming requirement now has three states instead of
two.

## Context and problem statement

[`publication-formats`](../openspec/specs/publication-formats/spec.md)
requires CBZ, CBR, CB7, CBT, EPUB, PDF and plain image folders, on both
platforms. Under [ADR-0001](0001-independent-native-cores.md) each platform
picks its own libraries. This ADR records those picks, their licences, and how
confident each one is — because a licence problem or a missing decoder found
during implementation is far more expensive than one found now.

**Confidence labels are load-bearing.** *Known* means verified against the
project's own documentation. *Assumed* means a reasonable pick that has not yet
been proven in a spike. Nothing here is *Known* until a spike says so.

## Considered options

Two whole-layer approaches were weighed before the per-library picks:

- **A single shared C library via FFI** (libarchive, libmupdf). Solves the
  format layer for both platforms at the cost of two FFI boundaries, two build
  integrations, and losing every platform-native affordance around it. See
  [ADR-0001](0001-independent-native-cores.md). Rejected as a whole-layer
  answer, then accepted for CBR and CBT only — see *RAR licensing* below.
- **Rolling our own EPUB engine.** Readium exists on both platforms, is
  maintained, and is BSD-licensed. Writing one would be the single largest and
  least differentiated piece of work in the project. Rejected.

Per need, the runners-up and the reason each lost are recorded in the tables
below and in *Risks*: junrar (UnRAR-derived), `androidx.pdf` and pdfium (a
viewer fragment and 5–8 MB per ABI for a capability comic PDFs never use), Coil
(duplicates ADR-0008's sparse cache), and four SMB candidates.

## Decision Outcome

### iOS

| Need | Library | Licence | Confidence |
| --- | --- | --- | --- |
| EPUB, reflowable + fixed-layout | **Readium Swift toolkit** 3.11.x, via SPM | BSD-3-Clause | Known — actively maintained, SPM-distributed, covers ebooks, audiobooks and comics |
| PDF | **PDFKit** (system) | Apple SDK | Known |
| ZIP (CBZ, EPUB container) | **Our own reader** over `RandomAccessSource`; inflate from `Compression` | — | **Known** — superseded by [ADR-0008](0008-ranged-reads-and-own-zip-reader.md). ZIPFoundation removed. |
| RAR (CBR) | **libarchive** 3.8.1, 26 vendored sources compiled by SwiftPM | BSD-2-Clause — verified per file | **Proven** — reads RAR4 and RAR5, stored, compressed and solid RAR5, against a shared corpus. ~180 kB linked and stripped |
| TAR (CBT) | **Our own `TarReader`** | none | **Proven** — libarchive is not needed for TAR. 512-byte headers, no compression; GNU long names and pax `path=` handled |
| 7-Zip (CB7) | — | — | **Not supported.** Dropped on product scope, not difficulty. libarchive's 7-Zip reader is not vendored at all, so it cannot be reached. Refused by name. |
| Image decoding | **ImageIO** / `CGImageSource` (system) | Apple SDK | **Verified** — corpus page decodes; 2000×3000 downsamples to 400×600 |
| SMB | **AMSMB2** (wraps libsmb2), SMB 2/3 | LGPL-2.1 — **must be dynamically linked**, see below | **Decided** — `contents(atPath:range:)` gives the ranged reads ADR-0008 needs |

### Android

| Need | Library | Licence | Confidence |
| --- | --- | --- | --- |
| EPUB, reflowable + fixed-layout | **Readium Kotlin toolkit** 3.3.x, via Maven Central | BSD-3-Clause | Known |
| PDF | **System `PdfRenderer`** for pages, **`PdfRendererPreV`** for text | Android SDK | **Superseded in part by [ADR-0011](0011-pdf-text-on-android.md).** The platform's PDF module gained text extraction, search and selection, so no library is needed after all; `androidx.pdf` and pdfium stay rejected for the reasons below. The document outline is still not exposed. |
| ZIP | **Our own reader** over `RandomAccessSource`; inflate from `java.util.zip.Inflater` | — | **Known** — superseded by [ADR-0008](0008-ranged-reads-and-own-zip-reader.md). |
| TAR (CBT) | **Our own `TarReader`** | none | **Proven** — mirrors iOS file for file, asserted against the same corpus |
| 7-Zip (CB7) | — | — | **Not supported** |
| RAR (CBR) | **libarchive** 3.8.1 via CMake + NDK, behind a JNI shim | BSD-2-Clause | **Proven** — all four ABIs build; 11 instrumented tests pass on an emulator; 137–149 kB stripped per ABI. junrar rejected as UnRAR-derived |
| Image decoding | **`ImageDecoder`** (system) | Android SDK | **Verified** on an emulator — same corpus page, same 400×600 result. Coil rejected: its caching duplicates ADR-0008's sparse cache, and it would make Android's decode path structurally unlike iOS's |
| SMB | **smbj** | Apache-2.0 | **Decided** — 822★, most active and most adopted of every candidate; SMB 2.0.2 → 3.1.1 with encryption, and ranged reads |

## What the first slice actually proved

The ZIP path is implemented on both platforms and asserted against the shared
corpus in `packages/test-fixtures` — 23 tests per platform, reading the same
`manifest.json`. Page *colour* is now compared too, not only page size: both
platforms decode the same flat-colour fixture to the same RGB triple exactly at
full size, and within ±1 per channel when downsampled 5:1 — the recorded
tolerance, since ImageIO and `ImageDecoder` are different resamplers and are not
required to round identically. That promoted three rows out of *Assumed*, and changed one
choice outright.

**Android needs no ZIP dependency.** `java.util.zip.ZipFile` is in the standard
library, so Commons Compress is now only on the hook for TAR and 7-Zip. The
asymmetry with iOS — which needs ZIPFoundation because Apple platforms ship no
ZIP container reader — is real and worth knowing rather than smoothing over.

**One caveat resolved, one still open:**

1. **Ranged reads — resolved by [ADR-0008](0008-ranged-reads-and-own-zip-reader.md).**
   The library choice recorded here was correct for local files and wrong for the
   `network-share` requirement, so both libraries are replaced by our own reader
   over a `RandomAccessSource`. That reversal happened within a day of this ADR
   being written, which is the confidence labels working rather than failing:
   ZIP was marked *Known* for "opens local fixtures", and it was a different
   question that changed the answer.
2. **Partial recovery is still not implemented.** `publication-formats` asks a
   truncated archive to yield what it can and report what it skipped. Today a
   truncated archive fails cleanly as `unreadable`. Both suites pin that
   behaviour, so the day a recovering reader lands, those two tests are what
   change. Our own reader makes this *possible* — scanning forward for local
   header signatures when the central directory is gone — where a library did
   not.

**Image decoding is now verified on both platforms.** A 2000×3000 corpus page
decodes to a bitmap of exactly that size, downsamples to 400×600 when bounded to
600 on the long edge, refuses to upscale, and rejects non-image bytes with a
named error rather than a crash. Both platforms produce identical numbers.

The two suites are asymmetric in *kind* rather than in coverage: ImageIO is
available on the macOS host so iOS tests it as a plain unit test, while
`ImageDecoder` and `Bitmap` are framework stubs off-device, so Android's decode
runs as an instrumented test on an emulator. The pure arithmetic — target-size
computation and spread detection — is unit-tested on both, which is why
`PageDecoder.targetSize` returns a plain `PageSize` rather than
`android.util.Size`.

## Risks

### Phase 0 results — libarchive is proven, with two surprises

Measured rather than estimated.

| Check | Result |
| --- | --- |
| Android arm64-v8a, CMake + NDK 29 | Builds. Static archive 7.24 MB. |
| **Android, linked and stripped** | **235 KB per ABI** — `--gc-sections` drops everything unreachable |
| iOS device + simulator, arm64 | **131/131 sources compile** |
| **iOS, linked and stripped** | **202 KB** |
| Functional | Reads a real TAR: correct entry names, sizes, and format identification |
| Licence, per file | `rar.c` BSD-2 (Kientzle, Mejia) · `rar5.c` BSD-2 (Antoniak) · `tar.c` BSD-2. **No UnRAR reference in any of them.** |

**Surprise one: trimming is automatic, and better than planned.** libarchive's
CMake exposes exactly one option — `BUILD_SHARED_LIBS`. There are no per-format
toggles, so the earlier plan to "compile out 7-Zip" was wrong in mechanism. It is
right in outcome by a better route: the linker's dead-code stripping takes 7.24 MB
down to 235 KB because only the RAR, RAR5 and TAR readers are reachable from our
entry points. That cannot drift the way a hand-maintained file list would.

**Surprise two: `config.h` is not portable across targets.** A host-generated
config defines `HAVE_BLAKE2_H` when Homebrew's `libb2` is present, and iOS has no
such library, so `rar5.c` fails to find `<blake2.h>`. Each target needs its own
generated config — or, minimally, the blake2 defines explicitly undefined so
libarchive falls back to its own bundled implementation. Reusing one config.h
across targets is the trap here, and it fails at compile time rather than
silently.

**iOS should not use libarchive's CMake at all.** Its `CMakeLists.txt` calls
`add_subdirectory` for the `bsdtar`, `bsdcat`, `bsdcpio` and `bsdunzip` tools
unconditionally, and their `install()` rules have no `BUNDLE DESTINATION`, which
fails an iOS configure outright. Compiling the sources directly in an SPM target
sidesteps it and is the idiomatic Apple integration regardless.

**Still unverified:** reading an actual RAR. That needs a real `.cbr`, and
generating one requires a RAR *compressor*, which is proprietary. The fixture has
to be hand-made from freely redistributable input and committed with its
provenance — Phase 1 of the `format-scope-and-libraries` change.

### RAR licensing — resolved by choosing libarchive

Every *easy* RAR decoder derives from the reference UnRAR source, whose licence
is not OSI-approved. Shipping one would put a non-OSI component inside a
repository whose README claims "free and open source" without qualification.

`libarchive` avoids it entirely: BSD-2-Clause, with its own RAR4 and RAR5
readers rather than UnRAR-derived code, and by a wide margin the most audited
RAR implementation in open source — which matters more than usual, because it
parses hostile bytes in C.

The cost is build engineering: six ABIs, and an FFI boundary this ADR originally
rejected. That rejection was reasoned — *the parsing layer is the part with good
native libraries already* — and it stops being true for exactly one format.
Reversing it for CBR and CBT only, and saying so here, beats pretending the
original reasoning still covers this case.

### CB7 — dropped, and the reason matters

Not a licence problem and not a difficulty problem: libarchive reads 7-Zip, and
enabling it would be a one-line format registration. CB7 is dropped because it is
rare and because solid 7-Zip is the worst remote-reading case in the entire
format set.

The consequence of dropping it on *scope* rather than on capability is that
adding it later costs a registration and a fixture, not an integration. Its
7-Zip reader is compiled out of the build so a reader nobody reaches is not dead
weight in every binary.

### SMB — decided, and the deciding factor was not licence

Five candidates were measured rather than argued about:

| Library | ★ | Licence | Dialects | Ranged reads |
| --- | --- | --- | --- | --- |
| `hierynomus/smbj` | 822 | Apache-2.0 | 2.0.2 → 3.1.1, encryption | yes |
| `sahlberg/libsmb2` | 422 | LGPL-2.1 | 2 → 3.1.1, encryption | `smb2_pread` |
| `AgNO3/jcifs-ng` | 344 | LGPL-2.1 | 1, 2 | yes |
| `amosavian/AMSMB2` | 308 | LGPL-2.1 | 2/3 via libsmb2 | `contents(atPath:range:)` |
| `kishikawakatsumi/SMBClient` | 285 | MIT | **2.0 only** | **no** |

**Android takes `smbj`.** Most stars, most active, Apache-2.0, pure Java so it is
a one-line Gradle dependency with no NDK build, and it covers every dialect
through 3.1.1 with encryption. It wins on every criterion at once, which is rare
enough to be worth saying.

**iOS takes `AMSMB2`.** The interesting part is *why not `SMBClient`*, which is
the only MIT option and would have been the licence-clean choice: it speaks
**SMB 2.0 only** and exposes no ranged reads — its file API downloads whole
files. That fails ADR-0008's architecture outright, and no licence preference
survives a library that cannot do the one thing the design is built on.

So iOS accepts LGPL-2.1, which brings one hard requirement.

#### The LGPL consequence, stated rather than discovered

AMSMB2 statically links libsmb2 by default. **StoryArc must link it dynamically
as an embedded framework** — which AMSMB2's own README prescribes for App Store
distribution, so this is a known and handled situation rather than a grey area.
There is precedent: VLC moved from GPL to LGPL specifically to make App Store
distribution possible.

Consequences to carry:

- `THIRD_PARTY_NOTICES.md` records the LGPL-2.1 text and states that the library
  is dynamically linked and therefore replaceable.
- The iOS build must be verified to embed a framework, not a static archive. A
  build that silently static-links is a licence violation, so it needs a check
  rather than a comment.
- If Apple's rules or the library's licence ever make this untenable, the
  fallback is `SMBClient` plus our own SMB2 `READ` on its low-level `Session`
  API — more work, MIT, and it would drop SMB 3 encryption, which
  `network-share` would then have to report as unavailable rather than absent.

#### Encryption

`network-share` requires the source screen to state whether a connection is
encrypted. **Both picks support SMB 3 encryption** — libsmb2 exposes an explicit
seal setting, smbj a `withEncryptData` configuration — so the requirement holds
as written and needs no softening.

#### Why not symmetric, when RAR was

`libarchive` was chosen for *both* platforms because RAR had no clean native
option on either. SMB is the opposite: Android has a best-in-class,
permissively-licensed, actively-maintained library. Forcing libsmb2 onto Android
for symmetry's sake would trade Apache-2.0 for LGPL and a Gradle line for an NDK
build, in exchange for nothing. ADR-0001 says each app uses the best library its
platform has; this is that principle producing an asymmetric answer, not a
compromise of it.

## Consequences

**Positive**

- Every format `publication-formats` asks for, except CB7, has a chosen library
  on both platforms, with the RAR and TAR licences verified file by file.
- libarchive costs 235 KB per Android ABI and 202 KB on iOS once linked and
  stripped, rather than the 7.24 MB static archive, and the trimming is the
  linker's rather than a hand-maintained file list.
- Both SMB picks support SMB 3 encryption, so `network-share` can state the
  encryption status as written, with no softening.

**Accepted costs**

- iOS accepts LGPL-2.1 through AMSMB2, which **must** be linked dynamically as
  an embedded framework. `THIRD_PARTY_NOTICES.md` carries the licence text, and
  the build needs a check rather than a comment — a silent static link is a
  licence violation.
- An FFI boundary this ADR first rejected is accepted for CBR and CBT only, and
  brings six ABIs of build engineering with it. Each target needs its own
  generated libarchive `config.h`; iOS compiles the sources in an SPM target
  instead of using libarchive's CMake.
- CB7 is unsupported. It is dropped on product scope, so adding it later costs a
  format registration and a fixture, not an integration.
- A truncated archive fails cleanly as `unreadable`. The partial recovery
  `publication-formats` asks for is not implemented, and both suites pin the
  current behaviour so the change is visible when it lands.
- Android's PDF path has no text layer, because the system `PdfRenderer` renders
  images only.
- The two decode suites are asymmetric in kind: a unit test on iOS, an
  instrumented emulator test on Android.

**Follow-up**

- The ZIP rows here are superseded by
  [ADR-0008](0008-ranged-reads-and-own-zip-reader.md).
- This ADR stays *proposed* until every table row is verified rather than
  decided.

## What still blocks acceptance

Every library is chosen. Nothing here is waiting on a decision any more — it is
waiting on execution and on two spikes that do not affect the choices above.

| Outstanding | Kind |
| --- | --- |
| ~~libarchive reads an actual RAR~~ | **Done.** It reads RAR4 and RAR5, stored, compressed and solid RAR5, and the decoded bytes are asserted against libarchive's own documented expected values rather than against our own output |
| ~~The remaining ABIs build~~ | **Done.** All four Android ABIs and both Apple slices compile the 26 vendored sources; sizes are in the change's task 6.2 |
| **iOS build embeds AMSMB2 dynamically, not statically** | Execution — a licence requirement, so it needs a check not a comment |
| **Readium pagination** compared across the two toolkits on the same EPUB | **Partly done, and no longer blocked.** Both toolkits render `fixture.epub` in a real reader: Swift 3.11 on iOS, Kotlin 3.3 on Android, same chapters and the same reading order. *Pagination* under matched typography is still uncompared, but the type controls it needed now exist — see task 7.8 of `reader-theming-and-page-transitions`. |
| **Readium is iOS-only, and `StoryArcKit` also builds for macOS** | **Resolved by a split, recorded here because it shapes the tree.** SwiftPM validates a dependency graph for every platform the depending package claims, so adding Readium to `StoryArcKit` fails macOS resolution outright — conditioning the target dependency does not help, the validation happens first. Reflowable rendering therefore lives in `apps/ios/Packages/StoryArcEpub`, which claims iOS alone, and everything host-testable stays where it was. Android splits the same way, into `:feature:epubreader`, because Readium's EPUB navigator is a `Fragment` and nothing else in the app is. |

The two spikes are mine to run and report, not decisions to put to anyone. This
ADR becomes **Accepted** when every row in the tables above is verified rather
than decided.

## Spike before accepting

- [x] **1a.** Decode CBZ on both platforms, including malformed archives.
      Done — 8 fixtures, 23 tests per platform.
- [ ] **1b.** CBR and CBT, same corpus treatment, including a **solid** RAR to
      pin the cannot-stream path. CB7 needs only a refusal fixture.
- [x] **2.** The RAR licence question is answered: libarchive, BSD-2-Clause.
      Recording its text is Phase 0.3 of the `format-scope-and-libraries` change.
- [ ] **3.** Stream one page from a 400 MB archive over SMB on both platforms and
      measure time-to-first-page. Expected to force our own ranged reader.
- [x] **4a.** Render the same EPUB through both Readium toolkits. Done — Swift
      3.11 and Kotlin 3.3 both open `fixture.epub` and `epub2.epub`, resume from a
      stored locator, and report progression.
- [ ] **4b.** Compare *pagination* under matched typography. **No longer blocked**
      — the type controls landed with `reader-theming-and-page-transitions`, so the
      same nine axes can now be set to the same values on both platforms. Still to
      run; it is task 7.8 of that change.
- [x] **5.** Decode an actual page to a bitmap on both platforms. Done — 8 tests
      on iOS, 7 instrumented on Android, same corpus page and same measured
      results.

The corpus used by all of these lives in `packages/test-fixtures`.

## Links

- Specs: [`publication-formats`](../openspec/specs/publication-formats/spec.md),
  [`network-share`](../openspec/specs/network-share/spec.md).
- Change in flight:
  [`format-scope-and-libraries`](../openspec/changes/format-scope-and-libraries/proposal.md)
  carries the fixture and licence-recording phases named above.
- Related decisions: [ADR-0001](0001-independent-native-cores.md) is why the
  picks are per platform. [ADR-0008](0008-ranged-reads-and-own-zip-reader.md)
  supersedes the ZIP rows.
- Licences: [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md).
- Fixtures: `packages/test-fixtures`.

**This ADR is not accepted until every row above is checked.** The library
choices are settled; what is left is proving them. The RAR licence question,
which was the only outstanding item that could have changed the product's scope,
is closed.
