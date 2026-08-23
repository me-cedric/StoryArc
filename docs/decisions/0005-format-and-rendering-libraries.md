# ADR-0005 — Format and rendering libraries per platform

- **Status:** Proposed — every row marked *Assumed* needs a spike before it is Accepted
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
| ZIP (CBZ, EPUB container) | **ZIPFoundation** | MIT | Assumed |
| RAR (CBR) | **Unrar.swift**, or UnrarKit | Swift parts MIT; bundled UnRAR source carries its own licence | Assumed — **licence review required before use**, see risk below |
| 7-Zip (CB7), TAR (CBT) | **SWCompression** | MIT | Assumed — documented to read ZIP, TAR and 7-Zip; no RAR |
| Image decoding | **ImageIO** / `CGImageSource` (system) | Apple SDK | Known — incremental decode and downsampling without a dependency |
| SMB | **SMBClient** (kishikawakatsumi), pure Swift, SMB 2 | MIT | Assumed — SMB 3 encryption support to be confirmed in the spike |

### Android

| Need | Library | Licence | Confidence |
| --- | --- | --- | --- |
| EPUB, reflowable + fixed-layout | **Readium Kotlin toolkit** 3.3.x, via Maven Central | BSD-3-Clause | Known |
| PDF | **PdfRenderer** (system) or **pdfium-android** | Apache-2.0 / BSD | Assumed — system `PdfRenderer` first; pdfium only if it proves inadequate |
| ZIP, TAR, 7-Zip | **Apache Commons Compress** | Apache-2.0 | Assumed |
| RAR | **junrar** | UnRAR-derived | Assumed — **licence review required**, see risk below |
| Image decoding | **Coil 3** over the platform decoders | Apache-2.0 | Assumed |
| SMB | **smbkotlin**, or **smbj** | to confirm | Assumed — smbkotlin advertises coroutine-based SMB 3 with no native dependency on API 26+; smbj is the conservative fallback |

### Rejected

- **A single shared C library via FFI** (libarchive, libmupdf). Solves the
  format layer for both platforms at the cost of two FFI boundaries, two build
  integrations, and losing every platform-native affordance around it. See
  [ADR-0001](0001-independent-native-cores.md).
- **Rolling our own EPUB engine.** Readium exists on both platforms, is
  maintained, and is BSD-licensed. Writing one would be the single largest and
  least differentiated piece of work in the project.

## Risks

### RAR licensing is the sharpest edge here

Every practical RAR decoder derives from the reference UnRAR source, whose
licence historically forbids using it to create a RAR *compressor*. StoryArc
only ever decompresses, which is the intended use — but the licence text is not
a standard OSI licence and it propagates into a repository that is otherwise
MIT.

**Required before any CBR code is written:** read the exact licence text shipped
with the chosen decoder on each platform, record it in `THIRD_PARTY_NOTICES.md`,
and confirm it is compatible with distributing StoryArc under MIT. If it is not,
the fallback is to ship CBR support as an optional component rather than to
quietly ship an incompatible licence.

### CB7 may not have a symmetric answer

SWCompression covers 7-Zip on iOS and Commons Compress covers it on Android, but
neither has been proven against real CB7 files. If one platform cannot read CB7
reliably, it is declared unsupported *on that platform* and the UI says so —
this is already written into the format spec's open questions rather than left
to be discovered.

### SMB 3 encryption

`network-share` requires the source screen to state whether a connection is
encrypted. Both SMB library picks are Assumed on this point. If neither
negotiates SMB 3 encryption, the requirement changes to reporting encryption as
unavailable — it does not get quietly dropped.

## Spike before accepting

1. Decode a corpus of real CBZ, CBR, CB7 and CBT files on both platforms,
   including deliberately malformed ones, and record what fails.
2. Read and record every licence into `THIRD_PARTY_NOTICES.md`.
3. Stream one page from a 400 MB archive over SMB on both platforms and measure
   time-to-first-page.
4. Render the same EPUB through both Readium toolkits and compare pagination.

The corpus used by all four lives in `packages/test-fixtures`.
