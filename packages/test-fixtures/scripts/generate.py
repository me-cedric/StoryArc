#!/usr/bin/env python3
"""Generate the comic fixture corpus.

Fixtures are generated rather than hand-authored so they are deterministic,
legally clean (no real artwork anywhere), and tiny. The generated files are then
committed, so neither test suite needs Python to run — the same
generate-then-commit pattern the design tokens use.

    python3 scripts/generate.py          # write comics/ and manifest.json
    python3 scripts/generate.py --check  # fail if the committed output is stale

Every fixture exists to pin one behaviour and is named after it.
"""

from __future__ import annotations

import argparse
import io
import json
import pathlib
import shutil
import struct
import subprocess
import tarfile
import zipfile
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
COMICS = ROOT / "comics"
AUDIOBOOKS = ROOT / "audiobooks"

# Audio is the one family here that is not hand-written, and the reason is honest:
# a decodable AAC frame is not something to encode by hand in a fixture script, and
# a fixture the platform decoders refuse is worse than no fixture. `ffmpeg` writes
# them, deterministically, with `-bitexact` on both the container and the codec.
#
# That does NOT make ffmpeg a requirement of this repository. The output is
# committed, exactly like the archives, so nothing that reads the corpus needs it;
# and `--check` never rewrites audio, for the same reason it never rewrites a
# DEFLATE archive — a different encoder build would produce different bytes and
# report a false staleness. On a machine without ffmpeg the audio section is
# skipped with a note and everything else still regenerates.
FFMPEG = shutil.which("ffmpeg")

_parser = argparse.ArgumentParser()
_parser.add_argument("--check", action="store_true", help="fail if committed output is stale")
ARGS = _parser.parse_args()
# `--check` must not touch the archives. DEFLATE output is not byte-identical
# across zlib builds, so rewriting them on another machine would produce
# different bytes and report a false staleness.
WRITE = not ARGS.check

# A 2x3 page keeps the whole corpus in single-digit kilobytes. The aspect ratio
# is portrait so spread-detection logic has something honest to look at.
PAGE_W, PAGE_H = 2, 3
SPREAD_W, SPREAD_H = 6, 3


def png(width: int, height: int, rgb: tuple[int, int, int]) -> bytes:
    """Minimal PNG encoder. No dependencies, byte-identical across runs."""

    def chunk(kind: bytes, payload: bytes) -> bytes:
        body = kind + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)  # 8-bit truecolour
    rows = b"".join(b"\x00" + bytes(rgb) * width for _ in range(height))
    # Fixed compression level so the bytes never drift between Python builds.
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(rows, 9))
        + chunk(b"IEND", b"")
    )


def hue(index: int) -> tuple[int, int, int]:
    """A distinct, deterministic colour per page, so a wrong order is visible."""
    return (37 * index % 256, 91 * index % 256, 151 * index % 256)


def write_archive(name: str, entries: list[tuple[str, bytes]]) -> pathlib.Path:
    path = COMICS / name
    if not WRITE:
        return path
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        for entry_name, payload in entries:
            # A fixed timestamp keeps the archive byte-identical between runs.
            info = zipfile.ZipInfo(entry_name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, payload)
    return path


def page(index: int) -> bytes:
    return png(PAGE_W, PAGE_H, hue(index))


COMIC_INFO = b"""<?xml version="1.0" encoding="utf-8"?>
<ComicInfo>
  <Series>Fixture Series</Series>
  <Number>1</Number>
  <Title>Natural Sort</Title>
  <PageCount>12</PageCount>
  <LanguageISO>en</LanguageISO>
</ComicInfo>
"""

fixtures: list[dict] = []


def register(name: str, why: str, pages: list[str], **extra) -> None:
    """Record what a correct parse of this fixture yields.

    Deliberately no hash and no byte count: DEFLATE output differs between zlib
    builds, so either field would make this manifest machine-specific and the
    staleness check useless. The archives are committed, so git pins their bytes;
    this file pins their *meaning*.
    """
    fixtures.append(
        {
            "file": f"comics/{name}",
            "pins": why,
            "expectedPageCount": len(pages),
            "expectedPageOrder": pages,
            **extra,
        }
    )


# ── 1. Natural sort ──────────────────────────────────────────────────────────
# page10 must sort after page9, not after page1. The single most common way a
# comic reader gets page order wrong.
names = [f"page{i}.png" for i in range(1, 13)]
write_archive("natural-sort.cbz", [(n, page(i)) for i, n in enumerate(names, 1)])
register(
    "natural-sort.cbz",
    "page10 sorts after page9, not after page1",
    [f"page{i}.png" for i in range(1, 13)],
)

# ── 2. Nested chapter directories ────────────────────────────────────────────
# Ordered by full path with natural sort, so chapter folders stay in order.
nested = [
    ("ch1/p1.png", page(1)), ("ch1/p2.png", page(2)), ("ch1/p10.png", page(3)),
    ("ch2/p1.png", page(4)), ("ch2/p2.png", page(5)),
    ("ch10/p1.png", page(6)),
]
write_archive("nested-chapters.cbz", nested)
register(
    "nested-chapters.cbz",
    "pages order by full path with natural sort, so ch10 follows ch2",
    ["ch1/p1.png", "ch1/p2.png", "ch1/p10.png", "ch2/p1.png", "ch2/p2.png", "ch10/p1.png"],
)

# ── 3. Non-image entries ─────────────────────────────────────────────────────
# ComicInfo.xml, OS cruft and a macOS resource fork must never be a page.
noise = [
    ("ComicInfo.xml", COMIC_INFO),
    ("__MACOSX/._page1.png", b"resource fork junk"),
    ("Thumbs.db", b"\x00" * 32),
    (".DS_Store", b"\x00" * 32),
    ("page1.png", page(1)),
    ("page2.png", page(2)),
    ("notes.txt", b"not a page"),
]
write_archive("non-image-entries.cbz", noise)
register(
    "non-image-entries.cbz",
    "ComicInfo.xml, OS cruft and resource forks are excluded from the page list",
    ["page1.png", "page2.png"],
    hasComicInfo=True,
    expectedSeries="Fixture Series",
)

# ── 4. Format detected from content, not extension ───────────────────────────
# A ZIP named .cbr still opens. `publication-formats` requires this.
write_archive("mislabelled-zip.cbr", [(f"page{i}.png", page(i)) for i in range(1, 4)])
register(
    "mislabelled-zip.cbr",
    "a ZIP named .cbr opens, because format comes from content not extension",
    ["page1.png", "page2.png", "page3.png"],
    actualContainer="zip",
)

# ── 5. Single page ───────────────────────────────────────────────────────────
# The progress-fraction edge case: index 0 of 1 total is 100%, not a division
# by zero. Already unit-tested on both platforms; this is the file-level pin.
write_archive("single-page.cbz", [("only.png", page(1))])
register("single-page.cbz", "a one-page publication does not divide by zero", ["only.png"])

# ── 6. Double-page spread ────────────────────────────────────────────────────
# A materially wider-than-tall image is one spread, never split across two turns.
spread = [
    ("p1.png", page(1)),
    ("p2-spread.png", png(SPREAD_W, SPREAD_H, hue(2))),
    ("p3.png", page(3)),
]
write_archive("double-page-spread.cbz", spread)
register(
    "double-page-spread.cbz",
    "a wide image is one spread, not two pages",
    ["p1.png", "p2-spread.png", "p3.png"],
    spreadIndices=[1],
)

# ── 7. STORED entries (no compression) ─────────────────────────────────────
# A perfectly legal CBZ. Our reader must not assume DEFLATE.
stored_path = COMICS / "stored-entries.cbz"
if WRITE:
  with zipfile.ZipFile(stored_path, "w") as archive:
    for index in range(1, 4):
        info = zipfile.ZipInfo(f"p{index}.png", date_time=(2026, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_STORED
        archive.writestr(info, page(index))
register(
    "stored-entries.cbz",
    "STORED entries read correctly — a reader must not assume DEFLATE",
    ["p1.png", "p2.png", "p3.png"],
    compressionMethods=["stored"],
)

# ── 8. Zip64 structures ──────────────────────────────────────────────────────
# Zip64 extra fields, without a 4 GB file: `force_zip64` writes the 64-bit
# structures for a small entry, which is exactly the parsing path we need to
# exercise. ADR-0008 makes this ours to get right.
zip64_path = COMICS / "zip64.cbz"
if WRITE:
  with zipfile.ZipFile(zip64_path, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as archive:
    for index in range(1, 4):
        info = zipfile.ZipInfo(f"p{index}.png", date_time=(2026, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        with archive.open(info, "w", force_zip64=True) as entry:
            entry.write(page(index))
register(
    "zip64.cbz",
    "Zip64 extra fields parse — 64-bit sizes and offsets",
    ["p1.png", "p2.png", "p3.png"],
    usesZip64=True,
)

# ── 9. Archive comment pushing the EOCD away from the tail ───────────────────
# The EOCD is no longer the last 22 bytes, so a reader that assumes a fixed tail
# offset instead of scanning backwards for the signature fails here.
comment_path = COMICS / "archive-comment.cbz"
if WRITE:
  with zipfile.ZipFile(comment_path, "w", zipfile.ZIP_DEFLATED) as archive:
    for index in range(1, 4):
        info = zipfile.ZipInfo(f"p{index}.png", date_time=(2026, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, page(index))
    # 600 bytes of comment: enough that a naive tail read misses the EOCD.
    archive.comment = b"StoryArc fixture comment. " * 24
register(
    "archive-comment.cbz",
    "the EOCD is found by scanning backwards for its signature, not at a fixed offset",
    ["p1.png", "p2.png", "p3.png"],
    hasArchiveComment=True,
)

# ── 10. Data descriptors ─────────────────────────────────────────────────────
# Written to a stream that cannot seek, so sizes land in a trailing data
# descriptor and the local headers carry zeros. The central directory is the only
# authority — ADR-0008's central rule, and this is the fixture that proves it.
class _Unseekable:
    """A writable sink with no seek, so zipfile emits data descriptors."""

    def __init__(self, handle):
        self._handle = handle
        self._position = 0

    def write(self, payload: bytes) -> int:
        self._position += len(payload)
        return self._handle.write(payload)

    def tell(self) -> int:
        return self._position

    def flush(self) -> None:
        self._handle.flush()

    def seekable(self) -> bool:
        return False


descriptor_path = COMICS / "data-descriptor.cbz"
if WRITE:
 with descriptor_path.open("wb") as raw:
    sink = _Unseekable(raw)
    with zipfile.ZipFile(sink, "w", zipfile.ZIP_DEFLATED) as archive:
        for index in range(1, 4):
            info = zipfile.ZipInfo(f"p{index}.png", date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, page(index))
register(
    "data-descriptor.cbz",
    "local headers carry zero sizes; the central directory is the only authority",
    ["p1.png", "p2.png", "p3.png"],
    usesDataDescriptor=True,
)

# ── 11. A large page ─────────────────────────────────────────────────────────
# 2000x3000 — a realistic comic page dimension. Solid colour, so zlib squeezes it
# to a couple of kilobytes: the corpus stays tiny while downsampling has
# something real to do. The 2x3 pages elsewhere cannot exercise it.
write_archive("large-page.cbz", [("p1.png", png(2000, 3000, hue(5)))])
register(
    "large-page.cbz",
    "a 2000x3000 page: downsampling and memory-bounded decode have something to do",
    ["p1.png"],
    pageDimensions=[2000, 3000],
    # The page is one flat colour, which is what makes a cross-platform pixel
    # comparison meaningful: any difference is the decoder, never resampling of
    # detail that was never there. Both suites assert this exact triple, at full
    # size and downsampled.
    expectedPagePixel=list(hue(5)),
)

# ── 12. A real EPUB 3 ─────────────────────────────────────────────────────
# An EPUB is a ZIP with a mandated shape: an uncompressed `mimetype` entry first,
# then META-INF/container.xml pointing at the package document. Generated rather
# than borrowed so the corpus stays free of third-party content, and so the
# Readium comparison has something both platforms parse identically.
EPUB_CONTAINER = b"""<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""

EPUB_PACKAGE = b"""<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">urn:uuid:storyarc-fixture-0001</dc:identifier>
    <dc:title>Fixture Publication</dc:title>
    <dc:language>en</dc:language>
    <dc:creator>StoryArc Fixtures</dc:creator>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
    <item id="cover" href="cover.png" media-type="image/png" properties="cover-image"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>
"""

# `publication-formats` asks for a publication's publisher, description, series and series
# index to be read. EPUB states the first two plainly and the series two ways: EPUB 3 defines
# `belongs-to-collection` refined by `group-position`, and EPUB 2 defines nothing at all, so
# Calibre's `calibre:series` became the convention by weight of use. A parser has to read
# both, and this fixture carries both — disagreeing on purpose, so a test can say which wins.
EPUB_SERIES_PACKAGE = b"""<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">urn:uuid:storyarc-fixture-series</dc:identifier>
    <dc:title>The Second Volume</dc:title>
    <dc:language>en</dc:language>
    <dc:creator>StoryArc Fixtures</dc:creator>
    <dc:publisher>Fixture Press</dc:publisher>
    <dc:description>A book that states its series twice, and differently.</dc:description>
    <meta property="belongs-to-collection" id="c01">The Declared Series</meta>
    <meta refines="#c01" property="collection-type">series</meta>
    <meta refines="#c01" property="group-position">2</meta>
    <meta name="calibre:series" content="The Calibre Series"/>
    <meta name="calibre:series_index" content="7"/>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
  </spine>
</package>
"""

EPUB_NAV = b"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>Contents</title></head>
<body>
  <nav epub:type="toc" id="toc">
    <ol>
      <li><a href="ch1.xhtml">Chapter One</a></li>
      <li><a href="ch2.xhtml">Chapter Two</a></li>
    </ol>
  </nav>
</body>
</html>
"""


def chapter(number: int, title: str, paragraphs: int) -> bytes:
    body = "\n".join(
        f"    <p>Chapter {number}, paragraph {index}. "
        "Text long enough that pagination has something to do with it.</p>"
        for index in range(1, paragraphs + 1)
    )
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml">\n'
        f"<head><title>{title}</title></head>\n"
        f"<body>\n    <h1>{title}</h1>\n{body}\n</body>\n</html>\n"
    ).encode()


epub_path = COMICS.parent / "ebooks" / "fixture.epub"
if WRITE:
    epub_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(epub_path, "w") as archive:
        # `mimetype` must be first and STORED — the one hard requirement in the
        # EPUB container spec, and a reader that reorders it produces an invalid file.
        info = zipfile.ZipInfo("mimetype", date_time=(2026, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_STORED
        archive.writestr(info, b"application/epub+zip")
        for name, payload in [
            ("META-INF/container.xml", EPUB_CONTAINER),
            ("OEBPS/package.opf", EPUB_PACKAGE),
            ("OEBPS/nav.xhtml", EPUB_NAV),
            ("OEBPS/ch1.xhtml", chapter(1, "Chapter One", 40)),
            ("OEBPS/ch2.xhtml", chapter(2, "Chapter Two", 40)),
            ("OEBPS/cover.png", page(1)),
        ]:
            entry = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, payload)

# ── 12b. EPUB 2, and a fixed-layout EPUB 3 ───────────────────────────────────
# `publication-formats` promises "EPUB 2 and EPUB 3, reflowable and fixed-layout",
# which is four combinations, and the differences between them are exactly the
# ones a parser gets wrong:
#
#   - EPUB 2 has no nav document. Its table of contents is an NCX file, reached
#     through the spine's `toc` attribute rather than a manifest property.
#   - EPUB 2 marks its cover with `<meta name="cover" content="id"/>`, where
#     EPUB 3 uses `properties="cover-image"` on the manifest item.
#   - A fixed-layout EPUB says so with `rendition:layout`, and it must be read
#     with the image reader rather than the reflowable one — so getting this wrong
#     means offering font controls for a comic.


def epub(name: str, entries: list[tuple[str, bytes]]) -> None:
    """Writes an EPUB with `mimetype` first and STORED, as the container spec demands."""
    path = ROOT / "ebooks" / name
    if not WRITE:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w") as archive:
        first = zipfile.ZipInfo("mimetype", date_time=(2026, 1, 1, 0, 0, 0))
        first.compress_type = zipfile.ZIP_STORED
        archive.writestr(first, b"application/epub+zip")
        for entry_name, payload in entries:
            info = zipfile.ZipInfo(entry_name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, payload)


EPUB2_PACKAGE = b"""<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:identifier id="pub-id">urn:uuid:storyarc-fixture-0002</dc:identifier>
    <dc:title>Legacy Fixture</dc:title>
    <dc:language>fr</dc:language>
    <dc:creator opf:role="aut">Ancienne Autrice</dc:creator>
    <meta name="cover" content="cover"/>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
    <item id="cover" href="cover.png" media-type="image/png"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>
"""

EPUB2_NCX = b"""<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head><meta name="dtb:uid" content="urn:uuid:storyarc-fixture-0002"/></head>
  <docTitle><text>Legacy Fixture</text></docTitle>
  <navMap>
    <navPoint id="np1" playOrder="1">
      <navLabel><text>Premier chapitre</text></navLabel>
      <content src="ch1.xhtml"/>
    </navPoint>
    <navPoint id="np2" playOrder="2">
      <navLabel><text>Second chapitre</text></navLabel>
      <content src="ch2.xhtml"/>
    </navPoint>
  </navMap>
</ncx>
"""

epub(
    "epub2.epub",
    [
        ("META-INF/container.xml", EPUB_CONTAINER),
        ("OEBPS/package.opf", EPUB2_PACKAGE),
        ("OEBPS/toc.ncx", EPUB2_NCX),
        ("OEBPS/ch1.xhtml", chapter(1, "Premier chapitre", 40)),
        ("OEBPS/ch2.xhtml", chapter(2, "Second chapitre", 40)),
        ("OEBPS/cover.png", page(1)),
    ],
)

epub(
    "series.epub",
    [
        ("META-INF/container.xml", EPUB_CONTAINER),
        ("OEBPS/package.opf", EPUB_SERIES_PACKAGE),
        ("OEBPS/nav.xhtml", EPUB_NAV),
        ("OEBPS/ch1.xhtml", chapter(1, "Chapter One", 12)),
    ],
)

FIXED_PACKAGE = b"""<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id"
         prefix="rendition: http://www.idpf.org/vocab/rendition/#">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">urn:uuid:storyarc-fixture-0003</dc:identifier>
    <dc:title>Fixed Layout Fixture</dc:title>
    <dc:language>en</dc:language>
    <dc:creator>StoryArc Fixtures</dc:creator>
    <meta property="rendition:layout">pre-paginated</meta>
    <meta property="rendition:spread">landscape</meta>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="p1" href="p1.xhtml" media-type="application/xhtml+xml"/>
    <item id="p2" href="p2.xhtml" media-type="application/xhtml+xml"/>
    <item id="img1" href="page1.png" media-type="image/png" properties="cover-image"/>
    <item id="img2" href="page2.png" media-type="image/png"/>
  </manifest>
  <spine>
    <itemref idref="p1"/>
    <itemref idref="p2"/>
  </spine>
</package>
"""

FIXED_NAV = b"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>Pages</title></head>
<body>
  <nav epub:type="toc" id="toc">
    <ol><li><a href="p1.xhtml">Page 1</a></li></ol>
  </nav>
</body>
</html>
"""


def fixed_page(index: int) -> bytes:
    """A pre-paginated page: one image at an exact size, no reflowable text."""
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml">\n'
        f'<head><title>Page {index}</title>\n'
        f'<meta name="viewport" content="width={PAGE_W}, height={PAGE_H}"/></head>\n'
        f'<body><img src="page{index}.png" width="{PAGE_W}" height="{PAGE_H}"/></body>\n'
        "</html>\n"
    ).encode()


epub(
    "fixed-layout.epub",
    [
        ("META-INF/container.xml", EPUB_CONTAINER),
        ("OEBPS/package.opf", FIXED_PACKAGE),
        ("OEBPS/nav.xhtml", FIXED_NAV),
        ("OEBPS/p1.xhtml", fixed_page(1)),
        ("OEBPS/p2.xhtml", fixed_page(2)),
        ("OEBPS/page1.png", page(1)),
        ("OEBPS/page2.png", page(2)),
    ],
)

# An EPUB that names no cover at all. `publication-formats` says the first page of
# the spine is rendered as the cover when a publication declares none, and the
# overwhelmingly common shape of that first page — the one a converter emits and the
# one a fixed-layout publication has by construction — is an XHTML wrapper around a
# single image. So this file has a spine, an image its first page shows, and no
# `cover-image` property anywhere: the cover has to be found rather than read off.
SPINE_COVER_PACKAGE = b"""<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">urn:uuid:storyarc-fixture-spine-cover</dc:identifier>
    <dc:title>No Declared Cover</dc:title>
    <dc:language>en</dc:language>
    <dc:creator>StoryArc Fixtures</dc:creator>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="p1" href="p1.xhtml" media-type="application/xhtml+xml"/>
    <item id="p2" href="p2.xhtml" media-type="application/xhtml+xml"/>
    <item id="img1" href="page1.png" media-type="image/png"/>
    <item id="img2" href="page2.png" media-type="image/png"/>
  </manifest>
  <spine>
    <itemref idref="p1"/>
    <itemref idref="p2"/>
  </spine>
</package>
"""

epub(
    "spine-cover.epub",
    [
        ("META-INF/container.xml", EPUB_CONTAINER),
        ("OEBPS/package.opf", SPINE_COVER_PACKAGE),
        ("OEBPS/nav.xhtml", FIXED_NAV),
        ("OEBPS/p1.xhtml", fixed_page(1)),
        ("OEBPS/p2.xhtml", fixed_page(2)),
        ("OEBPS/page1.png", page(1)),
        ("OEBPS/page2.png", page(2)),
    ],
)

# An EPUB with the right mimetype and no container document. Returning an empty
# publication for this would put a book in the library that cannot be opened, so
# the reader has to name the problem instead.
epub("no-package.epub", [])

# --------------------------------------------------------------------------------
# Audiobooks
#
# `publication-formats` gained three audio entries and one named refusal, and none
# of them can be asserted against a comic. Every file below is a sine tone: no
# recording, no voice, nothing anybody owns.
# --------------------------------------------------------------------------------

# Sample rate and bitrate are as low as the encoders accept while still decoding
# everywhere, because the corpus is committed and a fixture nobody looks at should
# not weigh more than a page of one that gets read.
AUDIO_RATE = 22050
AUDIO_KBPS = 24


def _chapter_metadata(title: str, chapters: list[tuple[str, int, int]]) -> str:
    """An FFMETADATA document. Milliseconds, because that is what a listener reads."""
    parts = [";FFMETADATA1", f"title={title}", "artist=StoryArc Fixtures", ""]
    for name, start_ms, end_ms in chapters:
        parts += [
            "[CHAPTER]",
            "TIMEBASE=1/1000",
            f"START={start_ms}",
            f"END={end_ms}",
            f"title={name}",
            "",
        ]
    return "\n".join(parts)


def audio(
    name: str,
    *,
    seconds: float,
    codec: str,
    hz: int = 220,
    chapters: list[tuple[str, int, int]] | None = None,
    title: str = "Fixture Audiobook",
    extra: list[str] | None = None,
) -> None:
    """One audio fixture, written only when there is an ffmpeg to write it with."""
    if not (WRITE and FFMPEG):
        return
    path = AUDIOBOOKS / name
    path.parent.mkdir(parents=True, exist_ok=True)
    command = [
        FFMPEG, "-hide_banner", "-loglevel", "error", "-y",
        # Both flags, both layers: one strips the container's encoder string, the
        # other the codec's. Without the pair the bytes drift between ffmpeg builds
        # and the committed fixture churns on every contributor's machine.
        "-fflags", "+bitexact", "-flags", "+bitexact",
        "-f", "lavfi",
        "-i", f"sine=frequency={hz}:duration={seconds}:sample_rate={AUDIO_RATE}",
    ]
    if chapters:
        meta = AUDIOBOOKS / ".chapters.ffmetadata"
        meta.write_text(_chapter_metadata(title, chapters))
        command += ["-i", str(meta), "-map_metadata", "1"]
    command += ["-ac", "1", "-c:a", codec, "-b:a", f"{AUDIO_KBPS}k", "-bitexact"]
    command += extra or []
    command += [str(path)]
    subprocess.run(command, check=True)
    meta = AUDIOBOOKS / ".chapters.ffmetadata"
    if meta.exists():
        meta.unlink()


THREE_CHAPTERS = [("One", 0, 2000), ("Two", 2000, 4000), ("Three", 4000, 6000)]

# The chaptered M4B. Its chapter marks live in an MP4 atom, which is the form
# media3 cannot read below 1.11.0 — see the audiobooks change's design.md.
#
# `+faststart` moves the `moov` atom to the front, which is what a real audiobook
# meant to be streamed carries — and it is also what makes `truncated.m4b` below
# test the behaviour it claims to. Without it ffmpeg writes `moov` last, a cut file
# has no header at all, and the fixture pins "damaged beyond opening" rather than
# "plays what it can". The first version of this fixture did exactly that.
audio(
    "chaptered.m4b",
    seconds=6,
    codec="aac",
    chapters=THREE_CHAPTERS,
    extra=["-movflags", "+faststart"],
)

# The same three chapters as ID3 CHAP frames, which media3 **can** read at 1.10.0.
# Having both is the point: the two containers fail differently and a corpus that
# only carried one would hide it.
audio(
    "id3-chapters.mp3",
    seconds=6,
    codec="libmp3lame",
    hz=180,
    chapters=THREE_CHAPTERS,
    extra=["-write_id3v2", "1"],
)

# No chapters at all. `publication-formats` says this opens and reports nothing as
# missing, because an unchaptered audiobook is a normal audiobook.
audio(
    "unchaptered.m4a",
    seconds=5,
    codec="aac",
    hz=260,
    title="No Chapters",
    extra=["-movflags", "+faststart"],
)

# A folder of parts, named so that natural sort is the only ordering that works —
# the same trap `natural-sort.cbz` sets for pages.
for index, tone in ((1, 200), (2, 240), (10, 300)):
    audio(f"folder-parts/part{index}.mp3", seconds=1, codec="libmp3lame", hz=tone)

# Two audio files and one image: the majority decides, and the app says which it
# chose. Written last so the image lands in a directory that already exists.
for index, tone in ((1, 210), (2, 250)):
    audio(f"mixed-folder/part{index}.mp3", seconds=1, codec="libmp3lame", hz=tone)
if WRITE:
    (AUDIOBOOKS / "mixed-folder").mkdir(parents=True, exist_ok=True)
    (AUDIOBOOKS / "mixed-folder" / "cover.png").write_bytes(page(1))

# A file the app must refuse **by name**, and the least of a file that can be.
#
# It is an MP4 whose brand says `aax `, and it carries no encrypted audio, no key,
# no account and nobody's recording — because the behaviour under test is the
# refusal, and a refusal needs a signature to recognise and nothing behind it.
# StoryArc does not implement, circumvent or advise on removing a content
# protection, so a fixture that carried real protected audio would be the one file
# in this corpus the project has an actual reason not to have.
if WRITE and FFMPEG:
    stub = AUDIOBOOKS / "unchaptered.m4a"
    if stub.exists():
        raw = bytearray(stub.read_bytes())
        # The major brand sits at bytes 8..12 of the leading `ftyp` box.
        raw[8:12] = b"aax "
        (AUDIOBOOKS / "protected.aax").write_bytes(bytes(raw[: 4 * 1024]))

# Cut mid-stream, after the header and before the end. `publication-formats` says
# the app plays what it can and states how much it could not, by the same rule that
# opens a comic missing pages.
if WRITE and FFMPEG:
    whole = (AUDIOBOOKS / "chaptered.m4b")
    if whole.exists():
        data = whole.read_bytes()
        (AUDIOBOOKS / "truncated.m4b").write_bytes(data[: int(len(data) * 0.6)])


audiobooks: list[dict] = [
    {
        "file": "audiobooks/chaptered.m4b",
        "pins": "an M4B's chapter marks come from the container's own atom",
        "container": "mp4",
        "expectedPartCount": 3,
        "expectedPartTitles": ["One", "Two", "Three"],
        "expectedDurationSeconds": 6,
        "chapterSource": "container",
        "note": "MP4 chapter atoms are the form media3 cannot read below 1.11.0, so this fixture is what proves the bump landed.",
    },
    {
        "file": "audiobooks/id3-chapters.mp3",
        "pins": "the same three chapters as ID3 CHAP frames, which are readable without the media3 bump",
        "container": "mp3",
        "expectedPartCount": 3,
        "expectedPartTitles": ["One", "Two", "Three"],
        "expectedDurationSeconds": 6,
        "chapterSource": "id3",
        "note": "Carried alongside the M4B on purpose: the two containers fail differently and a corpus with only one would hide it.",
    },
    {
        "file": "audiobooks/unchaptered.m4a",
        "pins": "an audiobook with no chapter markers opens, and nothing is reported as missing",
        "container": "mp4",
        "expectedPartCount": 1,
        "expectedPartTitles": [],
        "expectedDurationSeconds": 5,
        "chapterSource": None,
        "note": "Also pins that an .m4a and an .m4b holding the same audio are treated identically — the extension is a hint and the contents are the fact.",
    },
    {
        "file": "audiobooks/folder-parts",
        "pins": "a folder of audio files is one audiobook, and part10 sorts after part2",
        "container": "folder",
        "expectedPartCount": 3,
        "expectedPartOrder": ["part1.mp3", "part2.mp3", "part10.mp3"],
        "expectedDurationSeconds": 3,
        "chapterSource": "parts",
    },
    {
        "file": "audiobooks/mixed-folder",
        "pins": "a folder holding both audio and images is the kind the majority of its entries are",
        "container": "folder",
        "expectedKind": "audiobook",
        "expectedPartCount": 2,
        "expectedPartOrder": ["part1.mp3", "part2.mp3"],
        "note": "Two audio files against one image. `publication-formats` requires the app to state which kind it chose rather than choosing silently.",
    },
    {
        "file": "audiobooks/protected.aax",
        "pins": "a protected audiobook is refused by name, with no prompt for a key or an account",
        "container": "mp4",
        "expectedRefusal": "contentProtection",
        "note": "4 KB of an unencrypted fixture with the ftyp brand rewritten to `aax `. Because the source carries `+faststart`, this stub still holds a valid header and a decodable AAC stream — rewrite the brand back to `M4A ` and ffprobe reads it as aac. That is deliberate: it means the refusal has to come from the **brand**, and a decoder that merely choked on a broken file would not satisfy it. There is no encrypted audio, no key, no account and nobody's recording here, because StoryArc neither implements nor circumvents a content protection.",
    },
    {
        "file": "audiobooks/truncated.m4b",
        "pins": "a truncated audiobook plays what it can and states how much it could not",
        "container": "mp4",
        "truncatedFrom": "audiobooks/chaptered.m4b",
        "note": "Cut to 60% of the whole, so the header parses and the stream does not finish.",
    },
]

ebooks: list[dict] = [
    {
        "file": "ebooks/fixture.epub",
        "pins": "a valid EPUB 3: mimetype first and STORED, two spine items, a nav document and a cover",
        "epubVersion": 3,
        "expectedSpineCount": 2,
        "expectedTitle": "Fixture Publication",
        "expectedAuthor": "StoryArc Fixtures",
        "expectedLanguage": "en",
        "expectedIdentifier": "urn:uuid:storyarc-fixture-0001",
        "expectedSpineHrefs": ["OEBPS/ch1.xhtml", "OEBPS/ch2.xhtml"],
        "expectedTocTitles": ["Chapter One", "Chapter Two"],
        "expectedCoverHref": "OEBPS/cover.png",
        "expectedSpineCoverHref": "OEBPS/cover.png",
        "hasNavDocument": True,
        "hasCoverImage": True,
        "isFixedLayout": False,
    },
    {
        "file": "ebooks/epub2.epub",
        "pins": "an EPUB 2: no nav document, an NCX reached through the spine, and a cover named by a metadata meta",
        "epubVersion": 2,
        "expectedSpineCount": 2,
        "expectedTitle": "Legacy Fixture",
        "expectedAuthor": "Ancienne Autrice",
        "expectedLanguage": "fr",
        "expectedIdentifier": "urn:uuid:storyarc-fixture-0002",
        "expectedSpineHrefs": ["OEBPS/ch1.xhtml", "OEBPS/ch2.xhtml"],
        "expectedTocTitles": ["Premier chapitre", "Second chapitre"],
        "expectedCoverHref": "OEBPS/cover.png",
        "expectedSpineCoverHref": "OEBPS/cover.png",
        "hasNavDocument": False,
        "hasCoverImage": True,
        "isFixedLayout": False,
        "note": "The two cover conventions and the two table-of-contents formats are the things an EPUB parser most often gets wrong, so both are pinned.",
    },
    {
        "file": "ebooks/series.epub",
        "pins": "a publication's publisher, description and series, stated both the way EPUB 3 defines and the way Calibre made conventional — disagreeing on purpose, so the defined form can be seen to win",
        "epubVersion": 3,
        "expectedSpineCount": 1,
        "expectedTitle": "The Second Volume",
        "expectedAuthor": "StoryArc Fixtures",
        "expectedLanguage": "en",
        "expectedIdentifier": "urn:uuid:storyarc-fixture-series",
        "expectedPublisher": "Fixture Press",
        "expectedDescription": "A book that states its series twice, and differently.",
        "expectedSeries": "The Declared Series",
        "expectedSeriesIndex": "2",
        "expectedSpineHrefs": ["OEBPS/ch1.xhtml"],
        "expectedTocTitles": ["Chapter One", "Chapter Two"],
        "expectedCoverHref": None,
        "expectedSpineCoverHref": None,
        "hasNavDocument": True,
        "hasCoverImage": False,
        "isFixedLayout": False,
        "note": "`belongs-to-collection` is what the format defines and `calibre:series` is what most files carry; a file with both is a file whose publisher knew better than its converter, so the defined one wins.",
    },
    {
        "file": "ebooks/fixed-layout.epub",
        "pins": "a fixed-layout EPUB declares rendition:layout, so it is read with the image reader and not offered font controls",
        "epubVersion": 3,
        "expectedSpineCount": 2,
        "expectedTitle": "Fixed Layout Fixture",
        "expectedAuthor": "StoryArc Fixtures",
        "expectedLanguage": "en",
        "expectedIdentifier": "urn:uuid:storyarc-fixture-0003",
        "expectedSpineHrefs": ["OEBPS/p1.xhtml", "OEBPS/p2.xhtml"],
        "expectedTocTitles": ["Page 1"],
        "expectedCoverHref": "OEBPS/page1.png",
        "expectedSpineCoverHref": "OEBPS/page1.png",
        "hasNavDocument": True,
        "hasCoverImage": True,
        "isFixedLayout": True,
        "note": "Getting this wrong means offering typography controls for a comic, which `ebook-reader` forbids.",
    },
    {
        "file": "ebooks/spine-cover.epub",
        "pins": "a publication that declares no cover takes one from the image its first spine item shows",
        "epubVersion": 3,
        "expectedSpineCount": 2,
        "expectedTitle": "No Declared Cover",
        "expectedAuthor": "StoryArc Fixtures",
        "expectedLanguage": "en",
        "expectedIdentifier": "urn:uuid:storyarc-fixture-spine-cover",
        "expectedSpineHrefs": ["OEBPS/p1.xhtml", "OEBPS/p2.xhtml"],
        "expectedTocTitles": ["Page 1"],
        "expectedCoverHref": None,
        "expectedSpineCoverHref": "OEBPS/page1.png",
        "hasNavDocument": True,
        "hasCoverImage": False,
        "isFixedLayout": False,
        "note": "The declared cover is what a well-made EPUB carries and what most files do not. A shelf of converted books whose covers are all placeholders is the failure this pins against.",
    },
    {
        "file": "ebooks/no-package.epub",
        "pins": "an EPUB with no container document is refused by name, not opened empty",
        "epubVersion": 0,
        "expectedSpineCount": 0,
        "expectedTitle": None,
        "expectedAuthor": None,
        "expectedLanguage": None,
        "expectedIdentifier": None,
        "expectedSpineHrefs": None,
        "expectedTocTitles": None,
        "expectedCoverHref": None,
        "expectedSpineCoverHref": None,
        "hasNavDocument": False,
        "hasCoverImage": False,
        "isFixedLayout": False,
        "expectedRefusal": "no package document",
    },
]

# ── 13. Truncated archive ─────────────────────────────────────────────────────
# The one that matters most. `publication-formats` requires opening what can be
# read and reporting what was skipped, rather than refusing the publication.
intact = COMICS / "natural-sort.cbz"
truncated = COMICS / "truncated.cbz"
if WRITE:
    truncated.write_bytes(intact.read_bytes()[: int(intact.stat().st_size * 0.6)])
fixtures.append(
    {
        "file": "comics/truncated.cbz",
        "pins": "a truncated archive opens what it can and reports what it skipped",
        "expectedPageCount": None,
        "expectedPageOrder": None,
        "isRecoverable": True,
        "note": "The central directory is gone. A reader must not refuse the whole file.",
    }
)

# ── 8. Empty archive ─────────────────────────────────────────────────────────
write_archive("no-pages.cbz", [("readme.txt", b"no images here")])
register("no-pages.cbz", "an archive with no images reports zero pages, not an error", [])

# ── 8b. A codec nothing decodes, and an entry with nothing in it ─────────────
# `publication-formats` promises two things about a page that will not come out:
# an unsupported codec "displays a placeholder naming the codec, and does not break
# pagination", and a damaged archive "states how many were skipped". Both need an
# archive that is otherwise perfectly well-formed, so that a failure here is about
# the page rather than about the container.
#
# The JPEG XL entry carries a real codestream signature (`FF 0A`) and nothing
# behind it: neither platform ships a JXL decoder, so what is behind the signature
# has never been reached. What matters is that both platforms *name* it, and the
# signature is what they name it from.
#
# The zero-length entry is the skipped page. It is a real thing to find in a comic
# that was copied while it was being written, and it is the cheapest way to pin a
# count that would otherwise depend on how a particular zlib truncates.
JXL_SIGNATURE = b"\xff\x0a" + b"\x00" * 30

write_archive(
    "unsupported-codec.cbz",
    [
        ("page1.png", page(1)),
        ("page2.jxl", JXL_SIGNATURE),
        ("page3.png", b""),
    ],
)
register(
    "unsupported-codec.cbz",
    "a page in a codec nothing decodes is listed and named, and an empty entry is counted as skipped",
    ["page1.png", "page2.jxl"],
    expectedSkippedPageCount=1,
    expectedUndecodableCodec="JPEG XL",
    note="Excluding the JXL entry from the page list would be the easy fix and the wrong one: a page nobody can be told about is a page the reader silently loses.",
)


# ── 14. RAR and TAR containers ───────────────────────────────────────────────
# Everything above is a ZIP. CBR and CBT are the other two containers the
# `publication-formats` spec accepts, and neither can be produced by the standard
# library — so the store-mode writers below produce them.
#
# Store mode only, deliberately. A RAR *compressor* is proprietary, but the RAR
# container is documented, and nothing in the corpus needs compressed data: the
# fixtures pin container parsing, entry order and the solid flag. libarchive
# reads a store-mode RAR through exactly the same reader it uses for a
# WinRAR-compressed one, which is what these fixtures exist to exercise.
#
# ponytail: store mode has no Huffman and no LZ window, so this is ~80 lines
# instead of a codec. If a fixture ever needs real compression, shell out to
# `rar` and commit the output by hand — do not grow this into an encoder.

MTIME = 1767225600  # 2026-01-01T00:00:00Z, fixed so the bytes never drift
DOS_TIME = 0x5C210000  # the same instant in MS-DOS format, for RAR4


def _vint(value: int) -> bytes:
    """RAR5 variable-length integer: 7 bits per byte, low group first."""
    out = bytearray()
    while True:
        group, value = value & 0x7F, value >> 7
        out.append(group | 0x80 if value else group)
        if not value:
            return bytes(out)


def _rar5_block(header_type: int, body: bytes, data: bytes = b"") -> bytes:
    """One RAR5 block. The CRC covers the header from its size field onwards."""
    tail = _vint(header_type) + _vint(0x0002 if data else 0)
    if data:
        tail += _vint(len(data))
    sized = _vint(len(tail + body)) + tail + body
    return struct.pack("<I", zlib.crc32(sized)) + sized + data


def rar5(entries: list[tuple[str, bytes]]) -> bytes:
    out = [b"Rar!\x1a\x07\x01\x00", _rar5_block(1, _vint(0))]
    for name, payload in entries:
        encoded = name.encode()
        body = (
            _vint(0x0002 | 0x0004)  # mtime present, data CRC32 present
            + _vint(len(payload))  # unpacked size
            + _vint(0o100644)  # attributes, Unix mode
            + struct.pack("<II", MTIME, zlib.crc32(payload))
            # CompressionInfo: version 0 (RAR 5.0), method 0 (store), not solid.
            + _vint(0x0000)
            + _vint(1)  # host OS: Unix
            + _vint(len(encoded))
            + encoded
        )
        out.append(_rar5_block(2, body, payload))
    out.append(_rar5_block(5, _vint(0)))  # end of archive
    return b"".join(out)


def _rar4_block(body: bytes) -> bytes:
    """RAR4 blocks carry a CRC16 of everything from the type byte onwards."""
    return struct.pack("<H", zlib.crc32(body) & 0xFFFF) + body


def rar4(entries: list[tuple[str, bytes]], solid: bool = False) -> bytes:
    """`solid` marks every entry after the first, as a real compressor does."""
    out = [
        b"Rar!\x1a\x07\x00",
        # Main header: type 0x73, MHD_SOLID is 0x0008, then HighPosAV and PosAV.
        _rar4_block(struct.pack("<BHHHI", 0x73, 0x0008 if solid else 0, 13, 0, 0)),
    ]
    for index, (name, payload) in enumerate(entries):
        encoded = name.encode()
        out.append(
            _rar4_block(
                struct.pack(
                    "<BHHIIBIIBBHI",
                    0x74,  # file header
                    0x8000 | (0x0010 if solid and index else 0),  # LONG_BLOCK, LHD_SOLID
                    32 + len(encoded),  # header size, CRC16 included
                    len(payload),  # packed size, equal to unpacked in store mode
                    len(payload),
                    3,  # host OS: Unix
                    zlib.crc32(payload),
                    DOS_TIME,
                    20,  # decoder version 2.0
                    0x30,  # method: store
                    len(encoded),
                    0o100644,
                )
                + encoded
            )
            + payload
        )
    out.append(_rar4_block(struct.pack("<BHH", 0x7B, 0x4000, 7)))  # end of archive
    return b"".join(out)


def cbt(entries: list[tuple[str, bytes]]) -> bytes:
    """A plain USTAR archive. tarfile is stdlib, so this needs no format work."""
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w", format=tarfile.USTAR_FORMAT) as archive:
        for name, payload in entries:
            info = tarfile.TarInfo(name)
            info.size, info.mtime, info.mode = len(payload), MTIME, 0o644
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            archive.addfile(info, io.BytesIO(payload))
    return buffer.getvalue()


def write_bytes(name: str, payload: bytes) -> None:
    if WRITE:
        (COMICS / name).write_bytes(payload)


three = [(f"page{i}.png", page(i)) for i in range(1, 4)]
chapters = [("ch1/p1.png", page(1)), ("ch1/p2.png", page(2)), ("ch2/p1.png", page(3))]

write_bytes("rar4-store.cbr", rar4(three))
register(
    "rar4-store.cbr",
    "a RAR4 container opens and its entries keep archive order",
    ["page1.png", "page2.png", "page3.png"],
    actualContainer="rar4",
    isStreamable=True,
)

write_bytes("rar5-store.cbr", rar5(three))
register(
    "rar5-store.cbr",
    "a RAR5 container opens; RAR4 and RAR5 are different formats behind one extension",
    ["page1.png", "page2.png", "page3.png"],
    actualContainer="rar5",
    isStreamable=True,
)

# The solid fixture, and the reason it is RAR4 rather than RAR5.
#
# libarchive 3.8.1 refuses a solid RAR4 outright: read_header() in
# archive_read_support_format_rar.c returns ARCHIVE_FATAL on any file header
# carrying FHD_SOLID, with no compression-method check and no fallback. So a
# solid RAR4 is *unsupported*, not merely un-streamable — downloading it changes
# nothing. The reader must recognise the flag itself and say so, because
# libarchive's own failure arrives as a generic fatal error after the first entry
# has already been listed.
#
# There is no solid RAR5 counterpart here on purpose. libarchive does implement
# solid RAR5, but only through the LZ window that store mode never allocates, so
# a store-mode solid RAR5 fails as "no window buffer initialized yet" — an
# artefact of this writer, not a real limitation. Solid is also meaningless
# without compression, so no real compressor emits that combination. A solid
# RAR5 fixture needs a real compressor and stays a hand-made item.
write_bytes("rar4-solid.cbr", rar4(three, solid=True))
fixtures.append(
    {
        "file": "comics/rar4-solid.cbr",
        "pins": "a solid RAR4 is refused by name; libarchive cannot read one at all",
        "expectedPageCount": None,
        "expectedPageOrder": None,
        "actualContainer": "rar4",
        "isSolid": True,
        "isStreamable": False,
        "expectedRefusal": "This comic uses solid compression, which cannot be opened",
        "note": "The first entry is not solid, so a reader that delegates straight to libarchive lists page1.png and then fails fatally. Detection must read FHD_SOLID from the headers first.",
    }
)

write_bytes("tar-store.cbt", cbt(three))
register(
    "tar-store.cbt",
    "a TAR container opens; CBT is a supported format, not a mislabelled CBZ",
    ["page1.png", "page2.png", "page3.png"],
    actualContainer="tar",
    isStreamable=True,
)

write_bytes("tar-nested-chapters.cbt", cbt(chapters))
register(
    "tar-nested-chapters.cbt",
    "chapter directories inside a TAR order by full path, as they do inside a ZIP",
    ["ch1/p1.png", "ch1/p2.png", "ch2/p1.png"],
    actualContainer="tar",
    isStreamable=True,
)

# ── 15. CB7, the named refusal ───────────────────────────────────────────────
# 7-Zip is out of scope. The spec requires a *named* refusal — "7z archives are
# not supported", never a generic parse failure — so the fixture only has to
# carry a real 7z signature for detection to fire on.
#
# ponytail: a valid empty 7z end header, 32 bytes. Writing a 7z that contains
# pages would need an LZMA container writer for a format we refuse to read.
_seven_zip_start = struct.pack("<QQI", 0, 0, zlib.crc32(b""))
write_bytes(
    "refused.cb7",
    b"7z\xbc\xaf\x27\x1c\x00\x04" + struct.pack("<I", zlib.crc32(_seven_zip_start)) + _seven_zip_start,
)
fixtures.append(
    {
        "file": "comics/refused.cb7",
        "pins": "a 7z container is refused by name, not by a generic parse failure",
        "expectedPageCount": None,
        "expectedPageOrder": None,
        "actualContainer": "7z",
        "expectedRefusal": "7z archives are not supported",
        "note": "Detection fires on the 7z signature before any entry is read, so this fixture carries a valid empty 7z header and no pages.",
    }
)

# ── 14b. ComicInfo.xml, fully populated ──────────────────────────────────────
# `publication-formats` requires thirteen fields out of ComicInfo.xml, plus a
# reading direction, plus the right to designate a cover that is not page 1.
# `non-image-entries.cbz` carries a minimal ComicInfo to prove it is excluded from
# the page list; this one exists to be *read*.
#
# Deliberately a manga, because the reading-direction rule is the part with real
# logic in it: an explicit declaration wins, and Japanese with nothing declared
# opens right-to-left.
MANGA_COMIC_INFO = b"""<?xml version="1.0" encoding="utf-8"?>
<ComicInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <Series>Fixture Manga</Series>
  <Number>3</Number>
  <Volume>2</Volume>
  <Title>The Third Chapter</Title>
  <Summary>A summary with an &amp; in it, to prove entities are decoded.</Summary>
  <Writer>First Writer, Second Writer</Writer>
  <Penciller>A Penciller</Penciller>
  <Publisher>Fixture Press</Publisher>
  <Year>2026</Year>
  <Month>1</Month>
  <Day>15</Day>
  <PageCount>4</PageCount>
  <LanguageISO>ja</LanguageISO>
  <Manga>YesAndRightToLeft</Manga>
  <Pages>
    <Page Image="0" Type="Story"/>
    <Page Image="1" Type="FrontCover"/>
    <Page Image="2" Type="Story" DoublePage="true"/>
    <Page Image="3" Type="Story"/>
  </Pages>
</ComicInfo>
"""

write_archive(
    "manga-metadata.cbz",
    [("ComicInfo.xml", MANGA_COMIC_INFO)]
    + [(f"p{index}.png", page(index)) for index in range(1, 5)],
)
register(
    "manga-metadata.cbz",
    "every ComicInfo field the spec names is read, including a cover that is not page 1",
    ["p1.png", "p2.png", "p3.png", "p4.png"],
    hasComicInfo=True,
    expectedSeries="Fixture Manga",
    expectedComicInfo={
        "series": "Fixture Manga",
        "number": "3",
        "volume": 2,
        "title": "The Third Chapter",
        "summary": "A summary with an & in it, to prove entities are decoded.",
        "writers": ["First Writer", "Second Writer"],
        "penciller": "A Penciller",
        "publisher": "Fixture Press",
        "year": 2026,
        "month": 1,
        "day": 15,
        "pageCount": 4,
        "language": "ja",
        "readingDirection": "rightToLeft",
        # Page 2 in reading order, so index 1. `publication-formats` lets
        # ComicInfo override the default of "first page in reading order".
        "coverPageIndex": 1,
        "doublePageIndices": [2],
    },
)

# The direction rule has three branches, and only one of them is a declaration.
# This fixture takes the second: nothing declared, Japanese language.
JAPANESE_NO_DIRECTION = b"""<?xml version="1.0" encoding="utf-8"?>
<ComicInfo>
  <Series>Undeclared Direction</Series>
  <LanguageISO>ja-JP</LanguageISO>
</ComicInfo>
"""

write_archive(
    "japanese-no-direction.cbz",
    [("ComicInfo.xml", JAPANESE_NO_DIRECTION), ("p1.png", page(1))],
)
register(
    "japanese-no-direction.cbz",
    "Japanese with no declared direction opens right-to-left",
    ["p1.png"],
    hasComicInfo=True,
    expectedSeries="Undeclared Direction",
    expectedComicInfo={
        "series": "Undeclared Direction",
        "language": "ja-JP",
        "readingDirection": "rightToLeft",
    },
)

# ── 15b. The solid RAR5 fixture, vendored rather than generated ──────────────
# The one fixture in the corpus this script does not write. Solid means nothing
# without compression, and a RAR *compressor* is proprietary, so an honest solid
# RAR5 cannot be generated here — see the ponytail note on the RAR writers.
#
# Provenance: `test_read_format_rar5_solid.rar` from libarchive 3.8.1's own test
# suite (`libarchive/test/test_read_format_rar5_solid.rar.uu`), BSD-2-Clause,
# 1050 bytes, committed verbatim as `rar5-solid.cbr`. Better provenance than a
# hand-made file: known origin, known licence, and it is the exact archive
# libarchive's own suite reads.
#
# Its entries are `.bin` files rather than images, so it pins solid **parsing**
# and the solid flag — not "a solid comic opens". That distinction matters,
# because RAR4 and RAR5 differ here: libarchive cannot read a solid RAR4 at all,
# and reads a solid RAR5 completely.
_solid_rar5 = COMICS / "rar5-solid.cbr"
if ARGS.check and not _solid_rar5.is_file():
    raise SystemExit(
        "comics/rar5-solid.cbr is missing. It is vendored, not generated — "
        "restore it from git rather than expecting this script to write it."
    )
fixtures.append(
    {
        "file": "comics/rar5-solid.cbr",
        "pins": "a solid RAR5 parses completely, unlike a solid RAR4",
        "expectedPageCount": 0,
        "expectedPageOrder": [],
        "actualContainer": "rar5",
        "isSolid": True,
        "isStreamable": False,
        "isVendored": True,
        "expectedEntryNames": [
            "test.bin", "test1.bin", "test2.bin", "test3.bin",
            "test4.bin", "test5.bin", "test6.bin",
        ],
        "note": "Vendored from libarchive 3.8.1's test suite, BSD-2-Clause; see generate.py for why it is not generated. Its entries are .bin, not images, so the page count is zero by design: it pins solid RAR5 parsing and the solid flag, not a solid comic opening.",
    }
)

# ── 15c. Compressed RAR, also vendored ───────────────────────────────────────
# The fixtures that prove the *decoder*, as opposed to the header reader. Same
# reason as 15b: producing a compressed RAR needs a proprietary compressor.
#
# Provenance, both from libarchive 3.8.1's own test suite, BSD-2-Clause:
#   rar4-compressed.cbr  <- test_read_format_rar.rar
#   rar5-compressed.cbr  <- test_read_format_rar5_compressed.rar
#
# What makes these worth vendoring rather than round-tripping our own output is
# that their expected *contents* are known independently, from libarchive's test
# assertions rather than from our decoder:
#   - rar4's `test.txt` is the exact string "test text document\r\n".
#   - rar5's `test.bin` is 1200 bytes of a formula: each little-endian 32-bit word
#     at index i is max(0, k*k - 3*k + 1) for k = i + 1.
# Asserting against those is a real check on decompression. Asserting against
# bytes our own decoder produced would only prove it agrees with itself.
#
# Their entries are not images, so the page count is zero by design here too.
for _name, _entries, _pins in [
    (
        "rar4-compressed.cbr",
        ["test.txt", "testlink", "testdir/test.txt", "testdir", "testemptydir"],
        "RAR4 compression decodes to known bytes, not just to the right length",
    ),
    (
        "rar5-compressed.cbr",
        ["test.bin"],
        "RAR5 compression decodes to known bytes, not just to the right length",
    ),
]:
    if ARGS.check and not (COMICS / _name).is_file():
        raise SystemExit(
            f"comics/{_name} is missing. It is vendored, not generated — "
            "restore it from git rather than expecting this script to write it."
        )
    fixtures.append(
        {
            "file": f"comics/{_name}",
            "pins": _pins,
            "expectedPageCount": 0,
            "expectedPageOrder": [],
            "actualContainer": "rar4" if _name.startswith("rar4") else "rar5",
            "isVendored": True,
            "expectedEntryNames": _entries,
            "note": "Vendored from libarchive 3.8.1's test suite, BSD-2-Clause. Its entries are not images, so the page count is zero by design: it pins decompression against contents known from libarchive's own assertions.",
        }
    )

# ── 16. PDF ──────────────────────────────────────────────────────────────────
# PDF is its own container: no archive, no entries, a cross-reference table at
# the end. Both platforms render it with a system framework — PDFKit on iOS,
# PdfRenderer on Android — so the fixtures exist to pin what those frameworks
# must agree about: page count, page geometry, and whether a text layer exists.
#
# Written here rather than produced by a tool, for the same reasons as every
# other fixture: deterministic bytes, no real artwork, and single-digit
# kilobytes. A minimal PDF is a handful of objects and an offset table.

PDFS: list[dict] = []


def _pdf(objects: list[bytes], root: int, extra_trailer: str = "") -> bytes:
    """Assemble numbered objects into a PDF with a correct xref table.

    `objects` is 1-indexed by position: objects[0] becomes `1 0 obj`.
    """
    out = bytearray(b"%PDF-1.7\n")
    # A binary comment marks the file as containing binary data, which is what
    # tells a reader not to apply newline translation.
    out += b"%\xe2\xe3\xcf\xd3\n"
    offsets: list[int] = []
    for index, body in enumerate(objects, 1):
        offsets.append(len(out))
        out += f"{index} 0 obj\n".encode() + body + b"\nendobj\n"

    xref_at = len(out)
    out += f"xref\n0 {len(objects) + 1}\n".encode()
    out += b"0000000000 65535 f \n"
    for offset in offsets:
        out += f"{offset:010d} 00000 n \n".encode()
    out += (
        f"trailer\n<< /Size {len(objects) + 1} /Root {root} 0 R {extra_trailer}>>\n"
        f"startxref\n{xref_at}\n%%EOF\n"
    ).encode()
    return bytes(out)


def _stream(dictionary: str, payload: bytes) -> bytes:
    """A stream object. `Length` must be the exact byte count or readers refuse."""
    return (
        f"<< {dictionary} /Length {len(payload)} >>\nstream\n".encode()
        + payload
        + b"\nendstream"
    )


# ── 16a. A text PDF: a text layer, and an outline ────────────────────────────
# `ebook-reader` requires text selection and in-publication search on both
# platforms, and the document outline on whichever platform's PDF library
# exposes one — iOS only, per ADR-0011. A fixture that genuinely has a text
# layer is what makes "hidden, not disabled" testable for the ones that do not.
PDF_PAGE_W, PDF_PAGE_H = 612, 792  # US Letter, in points
PDF_TEXT_PAGES = ["Chapter One", "Chapter Two", "Chapter Three"]

# Object numbers are fixed so the outline can point at pages by reference.
# 1 catalog, 2 page tree, 3 font, 4 outline root, then three objects per page:
# the page, its content stream, and its outline item. So page 0 is object 5.
_page_object = {index: 5 + index * 3 for index in range(len(PDF_TEXT_PAGES))}
_contents_object = {index: 6 + index * 3 for index in range(len(PDF_TEXT_PAGES))}
_outline_object = {index: 7 + index * 3 for index in range(len(PDF_TEXT_PAGES))}

_objects: list[bytes] = [
    b"<< /Type /Catalog /Pages 2 0 R /Outlines 4 0 R /PageMode /UseOutlines >>",
    (
        "<< /Type /Pages /Kids ["
        + " ".join(f"{_page_object[i]} 0 R" for i in range(len(PDF_TEXT_PAGES)))
        + f"] /Count {len(PDF_TEXT_PAGES)} >>"
    ).encode(),
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
    (
        f"<< /Type /Outlines /First {_outline_object[0]} 0 R "
        f"/Last {_outline_object[len(PDF_TEXT_PAGES) - 1]} 0 R "
        f"/Count {len(PDF_TEXT_PAGES)} >>"
    ).encode(),
]

for _index, _title in enumerate(PDF_TEXT_PAGES):
    _text = f"BT /F1 24 Tf 72 700 Td ({_title}) Tj ET"
    _objects.append(
        (
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {PDF_PAGE_W} {PDF_PAGE_H}] "
            f"/Contents {_contents_object[_index]} 0 R "
            f"/Resources << /Font << /F1 3 0 R >> >> >>"
        ).encode()
    )
    _objects.append(_stream("", _text.encode()))
    _links = f"/Next {_outline_object[_index + 1]} 0 R " if _index + 1 < len(PDF_TEXT_PAGES) else ""
    _links += f"/Prev {_outline_object[_index - 1]} 0 R " if _index else ""
    _objects.append(
        (
            f"<< /Title ({_title}) /Parent 4 0 R "
            f"/Dest [{_page_object[_index]} 0 R /Fit] {_links}>>"
        ).encode()
    )

write_bytes("text-pages.pdf", _pdf(_objects, root=1))
PDFS.append(
    {
        "file": "comics/text-pages.pdf",
        "pins": "a PDF with a real text layer and an outline",
        "expectedPageCount": len(PDF_TEXT_PAGES),
        "expectedPageSizePoints": [PDF_PAGE_W, PDF_PAGE_H],
        "hasTextLayer": True,
        "expectedPageText": PDF_TEXT_PAGES,
        "expectedOutlineTitles": PDF_TEXT_PAGES,
        "note": "Both platforms must offer selection and search. Only iOS reads the outline; Android hides that control rather than showing it empty (ADR-0011).",
    }
)

# ── 16b. An image-only PDF: the scanned comic case ───────────────────────────
# `ebook-reader` requires an image-only PDF to be read with comic-reader
# behaviour on *both* platforms, with text controls hidden, because there is no
# text layer to expose. The page box matches the image aspect so the
# cross-platform fit assertion has an exact number to check.
PDF_IMAGE_W, PDF_IMAGE_H = 200, 300  # points, the same 2:3 as every fixture page

_image_objects: list[bytes] = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    (
        "<< /Type /Pages /Kids [3 0 R 6 0 R 9 0 R] /Count 3 >>"
    ).encode(),
]
for _index in range(3):
    # Raw RGB samples, deflated. PDF has no PNG filter, so the pixels go in as
    # FlateDecode samples rather than as the corpus's PNG bytes.
    _rgb = bytes(hue(_index + 1)) * (PAGE_W * PAGE_H)
    _image_objects.append(
        (
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {PDF_IMAGE_W} {PDF_IMAGE_H}] "
            f"/Contents {4 + _index * 3} 0 R "
            f"/Resources << /XObject << /Im0 {5 + _index * 3} 0 R >> >> >>"
        ).encode()
    )
    _image_objects.append(
        _stream("", f"q {PDF_IMAGE_W} 0 0 {PDF_IMAGE_H} 0 0 cm /Im0 Do Q".encode())
    )
    _image_objects.append(
        _stream(
            f"/Type /XObject /Subtype /Image /Width {PAGE_W} /Height {PAGE_H} "
            f"/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode",
            zlib.compress(_rgb, 9),
        )
    )

write_bytes("image-pages.pdf", _pdf(_image_objects, root=1))
PDFS.append(
    {
        "file": "comics/image-pages.pdf",
        "pins": "an image-only PDF reads as a comic on both platforms, with text controls hidden",
        "expectedPageCount": 3,
        "expectedPageSizePoints": [PDF_IMAGE_W, PDF_IMAGE_H],
        "hasTextLayer": False,
        "expectedAspect": [PAGE_W, PAGE_H],
        "note": "No text layer at all, so neither platform may offer selection or search, on any device. Page box is 2:3, matching every other fixture page.",
    }
)

# ── 17. Filename metadata ────────────────────────────────────────────────────
# `publication-formats` requires series, volume, chapter and year to be parsed
# from the filename when a publication carries no embedded metadata, and requires
# the results to be *marked as inferred* so a later authoritative source can
# replace them without asking the user to resolve a conflict.
#
# There is no file to commit for this: it is a pure function over a string. What
# the corpus can pin is the table of cases, so both platforms agree on what
# "common naming patterns" means rather than each inventing its own list.
#
# Every case here is a real-world shape. The awkward ones are deliberate: a year
# that could be mistaken for an issue number, a series whose own name contains
# digits, and scanlation-group brackets that are not part of the title.
FILENAME_CASES = [
    {
        "filename": "Saga 003 (2012).cbz",
        "series": "Saga",
        "number": "3",
        "volume": None,
        "year": 2012,
        "why": "the common shape: series, zero-padded issue, year in parentheses",
    },
    {
        "filename": "003.cbz",
        "series": None,
        "number": "3",
        "volume": None,
        "year": None,
        "why": (
            "a bare number is the whole name. Common inside a per-series folder, "
            "where the folder holds the series and the file holds only the issue — "
            "so the series is deliberately absent rather than guessed as '003'"
        ),
    },
    {
        "filename": "Invincible v02 #011 (2004).cbr",
        "series": "Invincible",
        "number": "11",
        "volume": 2,
        "year": 2004,
        "why": "volume and issue together, issue marked with a hash",
    },
    {
        "filename": "One Piece - c1044 (v104) [Scan Group].cbz",
        "series": "One Piece",
        "number": "1044",
        "volume": 104,
        "year": None,
        "why": "manga chapter naming, and bracketed groups are not part of the title",
    },
    {
        "filename": "Akira Vol. 3.cbz",
        "series": "Akira",
        "number": None,
        "volume": 3,
        "year": None,
        "why": "a spelled-out volume with no issue at all",
    },
    {
        "filename": "Blame! 2001 (2001).cbz",
        "series": "Blame! 2001",
        "number": None,
        "volume": None,
        "year": 2001,
        "why": "a series whose own name ends in digits — the parenthesised year is the year, and the title keeps its number",
    },
    {
        "filename": "Watchmen.cbz",
        "series": "Watchmen",
        "number": None,
        "volume": None,
        "year": None,
        "why": "a single volume with nothing to infer beyond the title",
    },
    {
        "filename": "Sandman #01 (1989).cbz",
        "series": "Sandman",
        "number": "1",
        "volume": None,
        "year": 1989,
        "why": "a leading zero is dropped, so #01 and #1 are the same issue",
    },
    {
        "filename": "Berserk - Chapter 364.cbz",
        "series": "Berserk",
        "number": "364",
        "volume": None,
        "year": None,
        "why": "a spelled-out chapter, separated by a dash",
    },
]

manifest = {
    "$description": "The shared publication corpus. Both test suites read this file and assert the same expected parse — it is what keeps two independent implementations from disagreeing about what correct means.",
    "$generatedBy": "packages/test-fixtures/scripts/generate.py",
    "$doNotEdit": "Generated. Change the script, run it, commit the result.",
    "$noHashes": "Deliberately records no file hashes or sizes: DEFLATE output differs between zlib builds, so either would make this manifest machine-specific. The archives are committed, so git pins their bytes; this file pins their meaning.",
    "pageAspect": {"portrait": [PAGE_W, PAGE_H], "spread": [SPREAD_W, SPREAD_H]},
    "comics": fixtures,
    "ebooks": ebooks,
    "audiobooks": audiobooks,
    "pdfs": PDFS,
    "$filenamesNote": "Cases for filename metadata inference, which needs no file on disk — it is a pure function over a string. Both platforms assert this same table so neither invents its own idea of what a common naming pattern is. Every value inferred from a filename must be marked inferred, so an authoritative source can replace it later without a conflict prompt.",
    "filenames": FILENAME_CASES,
}


def render() -> str:
    return json.dumps(manifest, indent=2) + "\n"


manifest_path = ROOT / "manifest.json"
rendered = render()

if ARGS.check:
    current = manifest_path.read_text() if manifest_path.exists() else ""
    if current != rendered:
        raise SystemExit("manifest.json is stale — run scripts/generate.py and commit the result")
    print(f"Fixture corpus is current: {len(fixtures)} archives.")
else:
    manifest_path.write_text(rendered)
    total = sum(
        (COMICS / pathlib.Path(f["file"]).name).stat().st_size
        for f in fixtures
        if (COMICS / pathlib.Path(f["file"]).name).is_file()
    )
    print(f"Wrote {len(fixtures)} archives, {total} bytes total, plus manifest.json")
    for f in fixtures:
        size = (COMICS / pathlib.Path(f["file"]).name).stat().st_size
        print(f"  {size:>6}  {f['file']:<34}  {f['pins']}")
