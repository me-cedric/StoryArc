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

### Trimming it — the linker does it, not the build config

The original plan here was wrong and the measurement corrected it. libarchive's
CMake exposes exactly **one** option, `BUILD_SHARED_LIBS`. There are no
per-format toggles, so "compile out 7-Zip" was not a thing that could be done.

It turns out not to matter, because dead-code stripping does it better:

| | Bytes |
| --- | --- |
| Android static archive, all objects | 7,240,128 |
| **Android, linked and stripped, per ABI** | **235,000** |
| **iOS, linked and stripped** | **202,000** |

Only the RAR, RAR5 and TAR readers are reachable from our entry points, so
`--gc-sections` on Android and `-dead_strip` on Apple discard the rest. That is
strictly better than a hand-maintained file list, which would have needed
updating every time libarchive moved code between files.

An App Bundle ships one ABI per device, so the real user-facing cost on Android
is 235 KB, not four times it.

### Two traps, found by building rather than by reading

**`config.h` is not portable across targets.** Generated on the macOS host it
defines `HAVE_BLAKE2_H`, because Homebrew's `libb2` is installed — and iOS has no
such library, so `rar5.c` fails on a missing `<blake2.h>`. Each target needs its
own generated config, or the blake2 defines explicitly undefined so libarchive
uses its bundled implementation. This fails loudly at compile time, which is the
good case.

**libarchive's CMake cannot configure for iOS.** It calls `add_subdirectory` for
the `bsdtar`, `bsdcat`, `bsdcpio` and `bsdunzip` tools unconditionally, and their
`install()` rules carry no `BUNDLE DESTINATION`, which is fatal once
`CMAKE_SYSTEM_NAME=iOS`. Compiling the sources directly in an SPM target avoids
it entirely — and is the idiomatic Apple integration anyway, so the constraint
pushes toward the right answer.

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
| ~~libarchive builds for six ABIs~~ | **arm64 verified on both platforms.** The other four Android ABIs are the same CMake invocation with a different `ANDROID_ABI`. | — |
| ~~Trimmed footprint~~ | **Measured: 235 KB / 202 KB.** | — |
| ~~`ImageDecoder` matches ImageIO~~ | **Verified.** Same corpus page, same 400×600 downsample, on both platforms. | — |
| libarchive reads an actual RAR | Phase 1 — needs a hand-made `.cbr`, since generating one requires a proprietary compressor | CBR unsupported, refusal path already in place |
| System `PdfRenderer` handles large PDFs page-on-demand | Task 4.2 | pdfium after all |

Two things remain outside this change and still block ADR-0005 from being
accepted: the **SMB library** choice and the **Readium pagination** comparison.
Both are spikes rather than decisions, and neither affects the format scope
settled here.
