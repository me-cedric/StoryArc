# @storyarc/test-fixtures

The shared publication corpus. Both test suites read the same files and assert
the same expected parse.

This is the mechanism that keeps two independent implementations
([ADR-0001](../../docs/decisions/0001-independent-native-cores.md)) honest. Two
codebases can drift; two codebases asserting the same fixture against the same
expectation drift loudly.

## Layout

```
packages/test-fixtures/
├── scripts/generate.py    the generator — fixtures are generated, not hand-authored
├── manifest.json          every fixture and what a correct parse yields
├── comics/                20 archives and 2 PDFs, 36 kB total
└── ebooks/                4 EPUBs, 9 kB total
```

## Status

**20 comic archives, two PDFs and four EPUBs**, covering ZIP, RAR4, RAR5, TAR,
PDF, EPUB 2, EPUB 3, fixed-layout EPUB, and the 7-Zip refusal.

### ZIP

| Fixture | Pins |
| --- | --- |
| `natural-sort.cbz` | page10 sorts after page9, not after page1 |
| `nested-chapters.cbz` | pages order by full path, so ch10 follows ch2 |
| `non-image-entries.cbz` | `ComicInfo.xml`, `Thumbs.db`, `.DS_Store` and `__MACOSX/` resource forks are never pages |
| `mislabelled-zip.cbr` | a ZIP named `.cbr` opens — format comes from content |
| `single-page.cbz` | a one-page publication does not divide by zero |
| `double-page-spread.cbz` | a wide image is one spread, not two pages |
| `stored-entries.cbz` | STORED entries read — a reader must not assume DEFLATE |
| `zip64.cbz` | Zip64 extra fields parse |
| `archive-comment.cbz` | the EOCD is found by scanning backwards, not at a fixed offset |
| `data-descriptor.cbz` | the central directory is the only authority on sizes |
| `large-page.cbz` | a 2000×3000 page, for downsampling and bounded decode |
| `truncated.cbz` | a damaged archive fails cleanly rather than crashing |
| `no-pages.cbz` | an archive with no images reports zero pages, not an error |

### RAR, TAR and 7-Zip

| Fixture | Pins |
| --- | --- |
| `rar4-store.cbr` | a RAR4 container opens and keeps archive order |
| `rar5-store.cbr` | a RAR5 container opens — RAR4 and RAR5 are different formats behind one extension |
| `rar4-solid.cbr` | a solid RAR4 is refused **by name**; libarchive cannot read one at all |
| `rar5-solid.cbr` | a solid RAR5 parses completely — vendored, see below |
| `tar-store.cbt` | a TAR container opens; CBT is a format, not a mislabelled CBZ |
| `tar-nested-chapters.cbt` | chapter directories inside a TAR order by full path |
| `refused.cb7` | a 7z container is refused by name, not by a generic parse failure |

Two of these are worth knowing about before you trust them.

**The RAR fixtures are store-mode, written by `generate.py` itself.** A RAR
*compressor* is proprietary; the RAR *container* is documented, and store mode has
no Huffman coding and no LZ window, so the writer is about eighty lines rather
than a codec. libarchive reads a store-mode RAR through the same reader it uses
for a WinRAR-compressed one, which is the code path these fixtures exist to
exercise. Verified: all three non-solid archives extract byte-identical pages
through `bsdtar` (libarchive 3.7.4). If a fixture ever needs real compression,
shell out to `rar` and commit the output by hand rather than growing the writer.

**`rar4-solid.cbr` pins a hard libarchive limit, not a preference.**
`read_header()` in `archive_read_support_format_rar.c` (3.8.1) returns
`ARCHIVE_FATAL` on any file header carrying `FHD_SOLID`, with no
compression-method check and no fallback — so a solid RAR4 is *unsupported*, and
downloading it changes nothing. Because the first entry in a solid archive is
itself not solid, a reader that delegates straight to libarchive lists page 1 and
*then* dies with a generic error. Detection has to read the flag first.

### EPUB

| Fixture | Pins |
| --- | --- |
| `fixture.epub` | a valid EPUB 3: `mimetype` first and STORED, a nav document, a cover property |
| `epub2.epub` | an EPUB 2: no nav document, an NCX reached through the spine, a cover named by a metadata `meta` |
| `fixed-layout.epub` | `rendition:layout` is `pre-paginated`, so the image reader opens it |
| `no-package.epub` | the right `mimetype` and no container document — refused by name, not opened empty |

Three fixtures cover the four combinations `publication-formats` promises. There
is no EPUB 2 fixed-layout fixture because pre-pagination was introduced in EPUB
3.

The two versions differ in exactly the places a parser gets wrong, which is why
both are here rather than only the modern one: EPUB 2 keeps its table of contents
in an NCX reached through the spine's `toc` attribute, EPUB 3 in a nav document
found by a manifest property; EPUB 2 names its cover with
`<meta name="cover" content="id"/>`, EPUB 3 with `properties="cover-image"`. A
reader that assumes the modern shape silently loses the contents and the cover of
every older book on the shelf.

### PDF

| Fixture | Pins |
| --- | --- |
| `text-pages.pdf` | a real text layer and an outline — the iOS-only capabilities |
| `image-pages.pdf` | an image-only PDF reads as a comic on both platforms, text controls hidden |

Written by `generate.py` rather than by a tool, for the same reasons as every
other fixture. A minimal PDF is a handful of objects and a byte-offset table, so
these are deterministic and under 2 kB each — where a real PDF writer would emit
timestamps and producer strings that change on every run.

`text-pages.pdf` exists to make "hidden, not disabled" testable: it genuinely has
text, so iOS must offer selection, search and the outline over it, and Android
must render it as images with those controls absent. `image-pages.pdf` embeds its
pages as `FlateDecode` RGB samples — PDF has no PNG filter — and its page box is
2:3, matching every other fixture page, so the cross-platform fit assertion has
an exact number rather than a tolerance. Both platforms sample the centre pixel of
a rendered page and assert the same `(37, 91, 151)`.

**`rar5-solid.cbr` is the one vendored fixture, and it proves the opposite.**
libarchive reads a solid RAR5 completely — so the blanket claim that solid means
unreadable was wrong, and only RAR4 is affected. Solid means nothing without
compression and a RAR compressor is proprietary, so `generate.py` cannot write an
honest one; this file is `test_read_format_rar5_solid.rar` from libarchive
3.8.1's own test suite, BSD-2-Clause, 1050 bytes, committed verbatim. Known
origin, known licence, and the exact archive libarchive's suite reads.

Its entries are `.bin` rather than images, so its expected page count is **zero
by design**: it pins solid RAR5 *parsing* and the solid flag, not a solid comic
opening. `generate.py` registers it in the manifest and `--check` verifies it
exists, but nothing regenerates it.

## Generated, then committed

```bash
python3 scripts/generate.py           # rewrite comics/ and manifest.json
python3 scripts/generate.py --check   # fail if the committed output is stale
```

Fixtures are **generated** so they are reproducible from a readable script,
legally clean, and tiny — every page is a 2×3 procedurally-coloured PNG, so there
is no real artwork anywhere in the repository. The output is then **committed**,
so neither test suite needs Python to run. Same generate-then-commit pattern as
the design tokens.

**They are not byte-identical across machines.** DEFLATE output differs between
zlib builds, so regenerating on another machine produces different bytes for the
same logical fixture. That is why `manifest.json` records **no hashes and no file
sizes** — either would make the staleness check machine-specific and therefore
useless. Git pins the archives' bytes; the manifest pins their *meaning*, and
`--check` compares only that. `--check` never writes, so it cannot itself cause
the drift it is looking for.

Colours are distinct per page index, so a wrong page order is visible rather
than merely failing an assertion.

## Rules for a fixture

1. **Small.** Single-digit kilobytes where possible; a 200-page comic is not
   needed to prove page ordering. The repository must not become a comic
   library.
2. **Legally clean.** Public-domain or self-generated artwork only. Never a real
   commercial publication, not even for a private test.
3. **Deliberate.** Every fixture exists to pin one behaviour. Name it after that
   behaviour — `natural-sort-page10-after-page9.cbz`, not `test3.cbz`.
4. **Documented.** `manifest.json` records the expected page count, page order,
   metadata, reading direction and cover for each one. Both suites read it, so
   neither can quietly disagree about what correct means.
5. **The malformed ones are the point.** A truncated archive, a broken central
   directory, a `ComicInfo.xml` with a bad encoding declaration, an EPUB with a
   spine referencing a missing item. `publication-formats` requires the app to
   open what it can and say what it skipped — that requirement is only real if a
   fixture proves it.

## How the two suites consume it

Both read `manifest.json` and assert against the **same** recorded expectations,
which is the mechanism that makes divergence loud:

| Platform | Locates the corpus by | Test |
| --- | --- | --- |
| iOS | walking up from `#filePath` — SPM cannot declare a resource outside its package root | `Tests/FormatsTests/ComicArchiveTests.swift` |
| Android | a `storyarc.fixtures` system property set by `core/format/build.gradle.kts`, with a walk-up fallback for IDE runs | `core/format/src/test/.../ComicArchiveTest.kt` |

Neither copies the files. One corpus, two readers.
