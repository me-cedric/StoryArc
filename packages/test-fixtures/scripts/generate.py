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
import json
import pathlib
import struct
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

# ── 11. Truncated archive ─────────────────────────────────────────────────────
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

manifest = {
    "$description": "The shared publication corpus. Both test suites read this file and assert the same expected parse — it is what keeps two independent implementations from disagreeing about what correct means.",
    "$generatedBy": "packages/test-fixtures/scripts/generate.py",
    "$doNotEdit": "Generated. Change the script, run it, commit the result.",
    "$noHashes": "Deliberately records no file hashes or sizes: DEFLATE output differs between zlib builds, so either would make this manifest machine-specific. The archives are committed, so git pins their bytes; this file pins their meaning.",
    "pageAspect": {"portrait": [PAGE_W, PAGE_H], "spread": [SPREAD_W, SPREAD_H]},
    "comics": fixtures,
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
