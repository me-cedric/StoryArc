# Format scope and libraries

## Why

`publication-formats` lists seven formats as supported. That list was written
before anyone had checked whether each one *could* be supported cleanly, and its
own Open Questions section flagged CB7 as unresolved. Two of the seven now have
answers that change what the app should promise.

**CBR.** Every easy RAR decoder derives from the reference UnRAR source, whose
licence is not OSI-approved. Shipping one would put a non-OSI component inside a
repository whose README says "free and open source" without qualification.
`libarchive` is the way out: BSD-2-Clause, with its own RAR4 and RAR5 readers
rather than UnRAR-derived code, and the most heavily audited RAR implementation
in open source.

**CB7.** Not a licence problem — `libarchive` reads 7-Zip too, so enabling it
would be a one-line registration. It is a product-scope decision: CB7 is rare,
and it is the worst possible streaming case because solid blocks mean one page
can require decompressing everything around it. It is being dropped because
nobody has it, not because it is hard.

**PDF text on Android** turns out to have no good middle option, and the honest
answer changes what the reader can promise there.

## What changes

### Modified: `publication-formats`

The supported-format table becomes six entries, not seven. **CB7 is removed** and
joins RAR-when-unavailable in the named-refusal path that already exists.

A new requirement makes each format's **streaming capability** explicit, because
ADR-0008 established that ranged reads are not uniformly possible: ZIP and PDF
stream beautifully, TAR streams once an index is built, and a solid RAR cannot
stream at all. The app must say "this one needs downloading first" rather than
stream badly and look broken on someone's NAS.

The Open Questions section goes away — it is answered.

### Modified: `ebook-reader`

PDF text selection, in-publication search and outline navigation are **iOS-only**
in 1.0. Android renders PDF pages as images with the text-dependent controls
hidden — the same path the spec already defines for scanned PDFs, now applied to
all PDFs on that platform.

This is the first requirement in StoryArc that differs by platform, so it says so
explicitly rather than quietly under-delivering on one side.

## Library decisions

Recorded in [ADR-0005](../../../docs/decisions/0005-format-and-rendering-libraries.md).

| Need | Decision |
| --- | --- |
| CBR (RAR4, RAR5) | **libarchive** via FFI, BSD-2-Clause, both platforms |
| CBT (TAR) | **libarchive**, same integration |
| CB7 (7-Zip) | **Not supported.** The linker drops its reader automatically, since nothing reaches it |
| PDF, iOS | **PDFKit** — full text layer |
| PDF, Android | **System `PdfRenderer`** — images only, no text layer |
| Page decoding, iOS | **ImageIO** |
| Page decoding, Android | **`ImageDecoder`** — no Coil, keeping the two decode paths symmetric |

`libarchive` reverses ADR-0005's original rejection of a shared C library via
FFI. That rejection was reasoned — "the parsing layer is the part with good
native libraries already" — and it stops being true for exactly one format,
because RAR's native options are licence-encumbered and libarchive's is not.
Reversing it for CBR and CBT only, and saying so, beats pretending the original
reasoning still covers this case.

## Non-goals

- **CB7.** Named refusal, not silent failure. Cheap to add later if anyone asks.
- **PDF text on Android.** Revisit when `androidx.pdf` ships something that is a
  renderer rather than a prebuilt `Fragment` with its own search UI.
- **Streaming solid archives.** Physically impossible, not deferred.
- **Archive passwords.** Already refused by `publication-formats`; unchanged.

## Risks

| Risk | Detail |
| --- | --- |
| **libarchive build engineering** | **Resolved.** arm64 builds and links on both platforms; the remaining four Android ABIs are mechanical. Two traps found and recorded in ADR-0005: `config.h` is not portable across targets, and libarchive's own CMake cannot configure for iOS. |
| **Binary size** | **Measured: 235 KB per Android ABI, 202 KB on iOS**, linked and stripped — far below the ~1 MB first assumed. Dead-code stripping does the trimming automatically; libarchive exposes no per-format toggles, so the earlier plan to compile 7-Zip out was wrong in mechanism and right in outcome. |
| **FFI on untrusted input** | libarchive parses hostile bytes in C. It is the most audited RAR implementation available, which is the reason to prefer it, but `SECURITY.md` gains an entry rather than a footnote. |
| **A platform-conditional requirement** | The first one in the project. Stated in the spec so it is a decision rather than a gap someone discovers. |
