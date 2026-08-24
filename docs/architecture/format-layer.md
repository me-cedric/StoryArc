# The format layer

Turns a file into an ordered list of pages, and a page into bytes a decoder can
use. Nothing above it knows what a container is; nothing below it knows what a
comic is.

Implemented twice, once per platform, asserted against one shared corpus
([ADR-0001]). `Formats` on iOS, `:core:format` on Android — the file names match
across the two on purpose, so a reviewer can diff them by eye.

## What it reads today

| Format | Reader | Dependency |
| --- | --- | --- |
| CBZ, and any ZIP | `ZipReader` | none — ours ([ADR-0008]) |
| CBT | `TarReader` | none — ours |
| CBR | `RarReader` + `RarDecoder` | libarchive, for decompression only |
| PDF | `PdfDocumentReader` | the platform: PDFKit, `PdfRenderer` |
| Plain folder | `ImageFolderArchive` | none |
| EPUB structure | `EpubReader` | none — ours |
| EPUB *rendering* | — | Readium, not built yet |
| CB7 | — | refused by name |

Page bytes are then decoded by `PageDecoder`, which is ImageIO on Apple and
`ImageDecoder` on Android — the platform in both cases ([ADR-0005]).

Metadata comes from `ComicInfo` for comics and `EpubReader` for books. Both are
ours, both need no dependency, and both feed the library rather than the reader.

`PublicationIndexer` is the layer's exit: a file in, a `Publication` out, with
metadata precedence applied — embedded beats a filename guess, field by field, and
every record says where it came from so an authoritative source can replace it
without raising a conflict. `LibraryScanner` walks a folder and emits those as it
finds them. Between them they are the only types here that mention the domain's
`Publication`, and the only ones the library layer needs to know about.

The scan emits rather than returns, which is what satisfies four `local-library`
requirements at once: progress as a count, browsing what is already found,
cancellation, and resumability from the events already delivered. iOS uses an
`AsyncStream` and Android a `Flow` — different idioms, same contract.

One rule in the walk is worth knowing: **a directory holding images and no
publication files is itself one publication**; a directory holding publication
files is a shelf. Deciding per directory is what lets an unpacked comic sit beside
packed ones without either being mistaken for the other.

## The shape

```
                    ComicArchiveOpener
                            │  sniffs content, never the extension
        ┌───────────┬───────┴────┬─────────────┬──────────────┐
        ▼           ▼            ▼             ▼              ▼
  ZipComicArchive  Tar…      Rar…      ImageFolderArchive   (refusal)
        └───────────┴────────┬───┴─────────────┘
                             ▼
                    ComicArchiveReading
                    pages · skippedPageCount · data(for:)
```

`PdfDocumentReader` and `EpubReader` sit deliberately outside that protocol. A
PDF page is *rendered*, not extracted, and an EPUB's reading order is a list of
XHTML documents rather than a list of images — pretending either is a comic
archive would mean inventing bytes for it.

`EpubReader` is worth a note: it reads structure, not content layout. Metadata,
reading order, table of contents, cover and the fixed-layout flag all come out of
the package document with no dependency, which is everything the *library* needs
to shelve a book. Readium is needed only when someone opens one to read.

## Four rules, and why each exists

**1. Format comes from content, never from the extension.** A ZIP named `.cbr` is
common enough that `publication-formats` requires it to open, and
`mislabelled-zip.cbr` in the corpus pins it. Sniffing reads 265 bytes: TAR
announces itself at offset 257 where everything else uses the first eight, and
one 265-byte read is the same single round trip as one 8-byte read.

**2. Every reader takes a `RandomAccessSource`, not a path.** That is the whole
point of [ADR-0008]: indexing a 400 MB archive on an SMB share must not transfer
400 MB. A CBZ reads its central directory from the tail; a CBT hops 512-byte
headers; a CBR walks its header chain. None of them downloads anything.

The one exception is `RarDecoder`, which takes a local file. Decompressing a RAR
entry is sequential by nature and a remote publication is downloaded before it is
read anyway. Marked `ponytail:` in both implementations with the upgrade path.

**3. Open what you can, and say what you skipped.** A truncated archive yields
its readable pages plus a count, rather than refusing the publication. The same
mechanism carries a page that will never decode: a zero-length entry, or a
compressed RAR entry with no decoder available, counts as skipped rather than
failing later and looking like corruption.

For a ZIP this goes further than skipping. When the central directory is gone —
a truncated download, a partial copy off a failing disk — `ZipReader.recovering`
rebuilds an index by scanning for local file headers. The corpus's
`truncated.cbz` is 60% of a twelve-page archive and opens eleven of them, all of
which decode. Owning the reader is what makes that possible at all, which is one
of the reasons [ADR-0008] gives for owning it.

Recovery is a separate entry point rather than a silent fallback, for two
reasons. It reads the archive **linearly**, giving up the ranged-read property
that the rest of this layer is built on — inherent, since recovery exists
precisely because there is no index to seek with. And it trusts local headers for
sizes, which [ADR-0008] otherwise forbids, because in recovery there is nothing
better to trust. `isRecovered` says which kind of index a caller is holding.

**4. A refusal is named.** `Container.displayName` exists so a 7-Zip comic is
refused as "7-Zip" and not as "could not open file". `publication-formats` forbids
the generic failure, because the named one tells the user what to do. There are
four distinct refusals and they are not interchangeable:

| Refusal | Means |
| --- | --- |
| unsupported container | StoryArc does not read this format |
| solid archive | The format is supported; this file cannot be read |
| password protected | Readable, but StoryArc does not manage archive passwords |
| unreadable | Damaged. Not a format problem, so do not suggest converting it |

## Why so little of it is a library

The ladder was walked deliberately, and most rungs held before a dependency was
needed:

- **ZIP** — the platform has inflate; the container is a documented layout. Ours.
- **TAR** — 512-byte blocks with fixed-offset ASCII fields. No compression at all.
  Ours.
- **RAR headers** — a documented layout with no compression in them. Everything
  indexing needs — names, sizes, the cover, solid, encrypted, whether an entry is
  stored — lives there. Ours.
- **RAR entry data** — real LZ and PPMd coding. *This* is the dependency.
- **Image decoding, PDF** — the platform ships both.
- **EPUB structure** — a ZIP holding XML. Container and metadata are ours; only
  laying out reflowable XHTML with per-axis typography controls needs Readium, and
  that is a rendering engine rather than a parser.

So libarchive's job is one function, `packed bytes → unpacked bytes`, and 26 of
its 132 sources are vendored. That is a smaller attack surface as well as a
smaller repository, which matters because `SECURITY.md` names archive parsing as
the largest one in the app.

See [VENDORING.md](../../third_party/libarchive/VENDORING.md) for the file list
and the refresh procedure.

## Untrusted input

Every parser here reads bytes an attacker may have chosen. The rules applied
uniformly, and each has a test:

- No length from a header is used to allocate before it is checked against the
  source.
- Every offset is bounds-checked; a header claiming more than the file holds stops
  the walk rather than seeking past the end.
- Entry counts are capped — 50 000, where a comic has hundreds.
- Header sizes are capped at 1 MB.
- A walk never moves backwards, so a crafted file cannot loop it.
- RAR5's variable-length integers are capped at ten groups, so a run of
  continuation bytes cannot spin the reader.
- A folder does not follow symlinks, and a resolved path is re-checked against
  the root at read time.

## The corpus is the contract

Both suites read `packages/test-fixtures/manifest.json` and assert the *same*
recorded expectations. That is the only thing stopping two independent
implementations from privately disagreeing about what a correct parse is — there
is nothing at compile time to catch it.

Fixtures are generated by a script and then committed, so neither suite needs
Python to run. Three are vendored instead, all from libarchive's own test suite,
because producing them needs a proprietary compressor; their provenance and the
reason are recorded in `generate.py` and the corpus README.

## Where the asymmetries are, and why

Two independent implementations are allowed to differ where the platforms differ.
Each of these is specified, not accidental:

| Asymmetry | Reason |
| --- | --- |
| PDF text, search and outline are iOS-only | Android has no PDF text API that is also a renderer. `ebook-reader` makes this explicit, and requires the controls to be *hidden* rather than disabled |
| Android's `PdfDocumentReader` has no `hasTextLayer` at all | The platform cannot answer the question, and a property hard-coded to `false` would invite a caller to treat it as an answer |
| Page-decoding tests are unit tests on iOS, instrumented on Android | ImageIO runs on the macOS host; `ImageDecoder` and `Bitmap` are framework stubs off-device |
| The RAR decoder is JNI on Android, a SwiftPM C target on iOS | Two build systems, one copy of the sources |
| Cover loading is one test on iOS and two on Android | The byte-level half is a unit test; decoding to a `Bitmap` needs a device |
| Android does not read a PDF's page count while indexing | `PdfRenderer` is a framework class, and a folder scan must not need a device |

**A warning the instrumented suite earned.** Android's regex engine is ICU, not
the JVM's. `\{[^}]*}` compiles on a desktop JVM and throws
`PatternSyntaxException` on a device, so a filename parser passed every unit test
and crashed the first time it ran on hardware. Escape every metacharacter in a
pattern, including closing braces and brackets, and do not treat a green JVM suite
as evidence that a regex works.

[ADR-0001]: ../decisions/0001-independent-native-cores.md
[ADR-0005]: ../decisions/0005-format-and-rendering-libraries.md
[ADR-0008]: ../decisions/0008-ranged-reads-and-own-zip-reader.md
