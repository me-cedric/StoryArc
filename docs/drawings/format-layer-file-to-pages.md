# The format layer: a file becomes pages

Companion to [`format-layer-file-to-pages.mmd`](format-layer-file-to-pages.mmd).

## Why this one exists

`SECURITY.md` names archive parsing as the largest attack surface in the app,
and the format layer is also the seam most changes touch. It is implemented
twice — once per platform, under [ADR-0001] — against one shared corpus. A
newcomer who understands this picture can read most of the repository; one who
does not will not know why `ComicArchiveOpener` never looks at a file extension.

## Read from

| File | What it settled |
| --- | --- |
| `docs/architecture/format-layer.md` | the shape, the four rules, the asymmetries |
| `apps/ios/Packages/StoryArcKit/Sources/Formats/ComicArchive.swift` | `ComicArchiveReading`, `ComicArchiveOpener.open`, the three archive types, the named refusals |
| `apps/ios/Packages/StoryArcKit/Sources/Formats/PublicationFormat.swift` | `FormatSniffer`, `probeLength = 265`, `Container` cases |
| `apps/ios/Packages/StoryArcKit/Sources/Formats/PublicationIndexer.swift` | the ZIP-or-EPUB branch, lines 70-92 |

The Android side is `:core:format`, with matching file names on purpose so the
two can be diffed by eye.

## What the picture is claiming

**The extension is never consulted.** A ZIP named `.cbr` is common enough that
`publication-formats` requires it to open, and the corpus pins it with
`mislabelled-zip.cbr`. The sniff reads 265 bytes rather than 8 because TAR
announces itself at offset 257, and one 265-byte read is the same single round
trip as one 8-byte read.

**Everything takes a `RandomAccessSource`, not a path.** That is the whole point
of [ADR-0008]: indexing a 400 MB archive on a share must not transfer 400 MB. A
CBZ reads its central directory from the tail, a CBT hops 512-byte headers, a
CBR walks its header chain. The one exception is `RarDecoder`, which needs a
local file, because decompressing a RAR entry is sequential by nature.

**An EPUB is a ZIP, and only its contents tell the two apart.** That is the one
branch in the diagram that is not a sniff — `PublicationIndexer` tries
`EpubReader` on anything that sniffed as `zip` and falls through to the comic
archive when it fails. `EpubReader` reads structure, not content layout, which
is everything the *library* needs to shelve a book; Readium is needed only when
someone opens one to read, and that is not built.

**PDF sits deliberately outside `ComicArchiveReading`.** A PDF page is rendered,
not extracted. Making it conform would mean encoding every rendered page to PNG
and decoding it again, once per page turn — so the reader above holds either an
archive or a PDF, and takes the difference on itself.

**A refusal is named.** `Container.displayName` is why a 7-Zip comic is refused
as "7-Zip" rather than "could not open file". There are four distinct refusals —
unsupported container, solid archive, password protected, unreadable — and they
are not interchangeable, because the named one tells the reader what to do. The
diagram draws two of them; the other two are properties of an archive that did
open.

**Open what you can, and say what you skipped.** A truncated archive yields its
readable pages plus a count. That is the `skippedPageCount` branch, and it is
also how a page that will never decode is carried: a zero-length entry, or a
compressed RAR entry with no decoder, counts as skipped rather than failing
later and looking like corruption.

## What the picture deliberately leaves out

`ZipReader.recovering` — the linear rescan for local file headers when the
central directory is gone — is a separate entry point rather than a step in this
flow, and drawing it as one would misrepresent it. It gives up the ranged-read
property the rest of the layer is built on, which is inherent: recovery exists
precisely because there is no index to seek with. `isRecovered` tells a caller
which kind of index it is holding.

`PublicationIndexer` and `LibraryScanner` sit above this diagram: they are the
layer's exit, turning a file into a `Publication` with metadata precedence
applied. They are the only types here that mention the domain at all.

[ADR-0001]: ../decisions/0001-independent-native-cores.md
[ADR-0008]: ../decisions/0008-ranged-reads-and-own-zip-reader.md
