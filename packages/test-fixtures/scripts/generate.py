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
import struct
import tarfile
import zipfile
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
COMICS = ROOT / "comics"

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

ebooks: list[dict] = [
    {
        "file": "ebooks/fixture.epub",
        "pins": "a valid EPUB 3: mimetype first and STORED, two spine items, a nav document and a cover",
        "expectedSpineCount": 2,
        "expectedTitle": "Fixture Publication",
        "expectedLanguage": "en",
        "hasNavDocument": True,
        "hasCoverImage": True,
    }
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
# Pins the iOS-only capabilities. `ebook-reader` requires text selection,
# in-publication search and the outline on iOS, and requires Android to *hide*
# those controls rather than show them disabled — so a fixture that genuinely has
# a text layer is what makes "hidden, not disabled" testable.
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
        "pins": "a PDF with a real text layer and an outline — the iOS-only capabilities",
        "expectedPageCount": len(PDF_TEXT_PAGES),
        "expectedPageSizePoints": [PDF_PAGE_W, PDF_PAGE_H],
        "hasTextLayer": True,
        "expectedPageText": PDF_TEXT_PAGES,
        "expectedOutlineTitles": PDF_TEXT_PAGES,
        "note": "iOS must offer selection, search and the outline. Android must hide those controls rather than disable them.",
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
        "note": "No text layer at all, so neither platform may offer selection or search. Page box is 2:3, matching every other fixture page.",
    }
)

manifest = {
    "$description": "The shared publication corpus. Both test suites read this file and assert the same expected parse — it is what keeps two independent implementations from disagreeing about what correct means.",
    "$generatedBy": "packages/test-fixtures/scripts/generate.py",
    "$doNotEdit": "Generated. Change the script, run it, commit the result.",
    "$noHashes": "Deliberately records no file hashes or sizes: DEFLATE output differs between zlib builds, so either would make this manifest machine-specific. The archives are committed, so git pins their bytes; this file pins their meaning.",
    "pageAspect": {"portrait": [PAGE_W, PAGE_H], "spread": [SPREAD_W, SPREAD_H]},
    "comics": fixtures,
    "ebooks": ebooks,
    "pdfs": PDFS,
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
    total = sum((COMICS / pathlib.Path(f["file"]).name).stat().st_size for f in fixtures)
    print(f"Wrote {len(fixtures)} archives, {total} bytes total, plus manifest.json")
    for f in fixtures:
        size = (COMICS / pathlib.Path(f["file"]).name).stat().st_size
        print(f"  {size:>6}  {f['file']:<34}  {f['pins']}")
