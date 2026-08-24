# ADR-0005 — Format and rendering libraries per platform

- **Status:** Proposed — every library is now **chosen**; what remains is execution and two spikes. See *What still blocks acceptance* at the end.
- **Date:** 2026-08-24
- **Deciders:** Cédric Meyer

## Context

[`publication-formats`](../../openspec/specs/publication-formats/spec.md)
requires CBZ, CBR, CB7, CBT, EPUB, PDF and plain image folders, on both
platforms. Under [ADR-0001](0001-independent-native-cores.md) each platform
picks its own libraries. This ADR records those picks, their licences, and how
confident each one is — because a licence problem or a missing decoder found
during implementation is far more expensive than one found now.

**Confidence labels are load-bearing.** *Known* means verified against the
project's own documentation. *Assumed* means a reasonable pick that has not yet
been proven in a spike. Nothing here is *Known* until a spike says so.

## Decision

### iOS

| Need | Library | Licence | Confidence |
| --- | --- | --- | --- |
| EPUB, reflowable + fixed-layout | **Readium Swift toolkit** 3.11.x, via SPM | BSD-3-Clause | Known — actively maintained, SPM-distributed, covers ebooks, audiobooks and comics |
| PDF | **PDFKit** (system) | Apple SDK | Known |
| ZIP (CBZ, EPUB container) | **Our own reader** over `RandomAccessSource`; inflate from `Compression` | — | **Known** — superseded by [ADR-0008](0008-ranged-reads-and-own-zip-reader.md). ZIPFoundation removed. |
| RAR (CBR) | **libarchive** via C interop | BSD-2-Clause | **Decided** — its own RAR4/RAR5 readers, not UnRAR-derived. Build unproven; see Phase 0. |
| TAR (CBT) | **libarchive**, same integration | BSD-2-Clause | **Decided** |
| 7-Zip (CB7) | — | — | **Not supported.** Dropped on product scope, not difficulty. libarchive's 7-Zip reader is compiled out. |
| Image decoding | **ImageIO** / `CGImageSource` (system) | Apple SDK | **Decided** — no page decoded to a bitmap yet, so still unproven |
| SMB | **SMBClient** (kishikawakatsumi), pure Swift, SMB 2 | MIT | Assumed — SMB 3 encryption support to be confirmed in the spike |

### Android

| Need | Library | Licence | Confidence |
| --- | --- | --- | --- |
| EPUB, reflowable + fixed-layout | **Readium Kotlin toolkit** 3.3.x, via Maven Central | BSD-3-Clause | Known |
| PDF | **System `PdfRenderer`** — images only, no text layer | Android SDK | **Decided.** `androidx.pdf` has text search but ships a whole `PdfViewerFragment`; pdfium costs 5–8 MB per ABI for a capability comic PDFs never use. |
| ZIP | **Our own reader** over `RandomAccessSource`; inflate from `java.util.zip.Inflater` | — | **Known** — superseded by [ADR-0008](0008-ranged-reads-and-own-zip-reader.md). |
| TAR (CBT) | **libarchive**, same integration as iOS | BSD-2-Clause | **Decided** — symmetric with iOS rather than a second implementation |
| 7-Zip (CB7) | — | — | **Not supported** |
| RAR (CBR) | **libarchive** via JNI | BSD-2-Clause | **Decided** — junrar rejected as UnRAR-derived |
| Image decoding | **`ImageDecoder`** (system) | Android SDK | **Decided** — Coil rejected: its caching duplicates ADR-0008's sparse cache, and it would make Android's decode path structurally unlike iOS's |
| SMB | **smbkotlin**, or **smbj** | to confirm | Assumed — smbkotlin advertises coroutine-based SMB 3 with no native dependency on API 26+; smbj is the conservative fallback |

### Rejected

- **A single shared C library via FFI** (libarchive, libmupdf). Solves the
  format layer for both platforms at the cost of two FFI boundaries, two build
  integrations, and losing every platform-native affordance around it. See
  [ADR-0001](0001-independent-native-cores.md).
- **Rolling our own EPUB engine.** Readium exists on both platforms, is
  maintained, and is BSD-licensed. Writing one would be the single largest and
  least differentiated piece of work in the project.

## What the first slice actually proved

The ZIP path is implemented on both platforms and asserted against the shared
corpus in `packages/test-fixtures` — 23 tests per platform, reading the same
`manifest.json`. That promoted three rows out of *Assumed*, and changed one
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

Image decoding stays *Assumed* on both platforms: the corpus tests verify PNG
magic bytes, not that a page renders.

## Risks

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

### SMB 3 encryption

`network-share` requires the source screen to state whether a connection is
encrypted. Both SMB library picks are Assumed on this point. If neither
negotiates SMB 3 encryption, the requirement changes to reporting encryption as
unavailable — it does not get quietly dropped.

## What still blocks acceptance

Every library is chosen. Nothing here is waiting on a decision any more — it is
waiting on execution and on two spikes that do not affect the choices above.

| Outstanding | Kind |
| --- | --- |
| libarchive builds and links for all six ABIs | Execution — the only real unknown |
| Trimmed binary footprint measured per ABI | Execution |
| A page actually decoded to a bitmap on both platforms | Execution |
| **SMB library** — `SMBClient` vs alternatives on iOS, `smbkotlin` vs `smbj` on Android, and whether SMB 3 encryption is mandatory or best-effort | Spike |
| **Readium pagination** compared across the two toolkits on the same EPUB | Spike |

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
- [ ] **4.** Render the same EPUB through both Readium toolkits and compare
      pagination.
- [ ] **5.** Decode an actual page to a bitmap on both platforms, so image
      decoding stops being *Assumed*.

The corpus used by all of these lives in `packages/test-fixtures`.

**This ADR is not accepted until every row above is checked.** The library
choices are settled; what is left is proving them. The RAR licence question,
which was the only outstanding item that could have changed the product's scope,
is closed.
