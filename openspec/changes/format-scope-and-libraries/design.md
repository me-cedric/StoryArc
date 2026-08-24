# Design — format scope and libraries

## libarchive, and why it reverses a decision

ADR-0005 originally rejected "a shared C library via FFI" with a specific
reason: *the parsing layer is the part with good native libraries already.* That
was true for ZIP, EPUB and PDF. It is not true for RAR.

| Option | Licence | Verdict |
| --- | --- | --- |
| UnrarKit / Unrar.swift (iOS), junrar (Android) | UnRAR-derived — **not OSI** | Rejected. Puts a non-OSI component in an MIT repository. |
| unarr | LGPL, RAR support partly UnRAR-derived | Rejected. Same problem, plus copyleft. |
| **libarchive** | **BSD-2-Clause** | **Chosen.** Its own RAR4 and RAR5 readers, not UnRAR-derived. |
| Write our own RAR decoder | — | Rejected. RAR5 is far harder than ZIP, and unlike ZIP there is a clean library. |

libarchive is also, by a wide margin, the most audited RAR implementation in open
source — which matters more than usual here, because it parses hostile bytes in
C. That is simultaneously the reason to choose it and the reason it earns a
`SECURITY.md` entry.

**Assumed, and the change's only real unknown:** that libarchive builds cleanly
for all six ABIs. iOS device and simulator, plus four Android ABIs. Task 0.1
proves or disproves it before anything is built on top.

### Trimming it

libarchive supports dozens of formats. We need two. Everything else is compiled
out — `--without-*` for the compression backends we do not use, and the format
readers disabled individually. **7-Zip is compiled out too**, even though it
would work, because CB7 is not being supported and a reader nobody reaches is
dead weight in every binary.

Expected footprint after trimming: well under 1 MB per ABI. Task 0.2 measures it
rather than trusting that sentence.

### What libarchive does not solve

Solid RAR still cannot stream. That is a property of the container, not of the
library: a solid archive compresses files together, so page 40 needs pages 1–39
decompressed first. `publication-formats` now states this per format, and the app
offers a download instead of streaming badly.

## CB7: dropped on scope, not on difficulty

Worth being precise, because the two reasons lead to different futures. CB7 is
**not** hard — libarchive reads 7-Zip, and enabling it is a one-line format
registration. It is dropped because it is rare and because solid 7-Zip is the
worst remote-reading case in the whole format set.

Consequence: adding CB7 later costs a registration and a fixture, not an
integration. The named-refusal path is already implemented and tested, so a CB7
today gets a useful message rather than a crash.

## PDF on Android: three options, none good

| Option | Text layer | Shape | Verdict |
| --- | --- | --- | --- |
| System `PdfRenderer` | No | A renderer — pages to bitmaps | **Chosen** |
| `androidx.pdf` | Yes | `PdfViewerFragment`: a complete viewer with its own FAB and search UI | Rejected |
| pdfium-android | Yes | A renderer, with full control | Rejected for now |

`androidx.pdf` is the frustrating one: it has exactly the feature we want and
exactly the wrong shape. StoryArc's reader owns its chrome, its transitions, its
theming and its page-turn gesture. Dropping in a prebuilt Fragment with its own
search menu means fighting it on every one of those. It is also still
`1.0.0-alpha19`.

pdfium would work and costs 5–8 MB per ABI plus a second FFI boundary. Not worth
it for a capability that comic PDFs — which have no text layer — never use.

So Android renders PDF pages as images. `ebook-reader` now says this explicitly,
and adds the requirement that matters more than the gap itself: **nothing in the
UI may suggest text search is available and failing.** A hidden control is
honest; a disabled one that looks broken is not.

This is the project's first platform-conditional requirement. Stated rather than
discovered.

## Page decoding: the platform on both sides

| Need | iOS | Android |
| --- | --- | --- |
| Decode from bytes | `CGImageSourceCreateWithData` | `ImageDecoder.createSource(ByteBuffer)` |
| Downsample to display size | `kCGImageSourceThumbnailMaxPixelSize` | `OnHeaderDecodedListener` + `setTargetSize` |
| Re-decode higher on zoom | re-create at a larger max size | re-decode at a larger target |

Those are the only three things the reader needs, and both platforms have all
three natively. Coil 3 is an excellent library whose main additions — memory and
disk caching — substantially duplicate the sparse cache and prefetch window
ADR-0008 already puts in our hands.

Taking it would also make Android's decode path structurally different from
iOS's for no behaviour any spec asks for, on a layer that has already produced
one silent cross-platform divergence.

## What is still Assumed after this change

| Assumption | Proven by | Fallback |
| --- | --- | --- |
| libarchive builds for six ABIs | Task 0.1 | CBR and CBT unsupported, with the named refusal already in place |
| Trimmed footprint under 1 MB per ABI | Task 0.2 | Accept the size, or drop CBT and keep RAR only |
| `ImageDecoder` downsampling matches ImageIO's output closely enough | Task 3.3 | Per-platform tolerance in the visual comparison |
| System `PdfRenderer` handles large PDFs page-on-demand | Task 4.2 | pdfium after all |

Two things remain outside this change and still block ADR-0005 from being
accepted: the **SMB library** choice and the **Readium pagination** comparison.
Both are spikes rather than decisions, and neither affects the format scope
settled here.
