#!/usr/bin/env python3
"""Lays down a budget library for tasks 5.9 and 5.10: COUNT comics made from the corpus.

Each publication is the pages of one corpus CBZ with a ComicInfo.xml of its own (a series of
twenty-five issues, a number, a title), so every file is different bytes and a different book:
copies of one file are folded into one publication by the library, which is right for a reader
and useless for a budget. Written into the sandboxed app's container, where the budget walk
(`Tests/BudgetWalkTests.swift`) adds the folder; the app may read its own container. Removing
the folder afterwards is the owner's step.

Usage: python3 -I apps/desktop-macos/scripts/budget-library.py COUNT
"""
import pathlib
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
CORPUS = ROOT / "packages/test-fixtures/comics"
SOURCES = ["natural-sort.cbz", "stored-entries.cbz", "single-page.cbz", "double-page-spread.cbz",
           "data-descriptor.cbz", "archive-comment.cbz"]
CONTAINER = pathlib.Path.home() / "Library/Containers/com.mecedric.storyarc/Data/tmp"


def comic_info(index: int) -> bytes:
    series, number = divmod(index, 25)
    return (f'<?xml version="1.0"?><ComicInfo><Series>Budget Series {series + 1:03d}</Series>'
            f'<Number>{number + 1}</Number><Title>Budget {index + 1:05d}</Title></ComicInfo>').encode()


def main() -> None:
    count = int(sys.argv[1])
    folder = CONTAINER / f"budget-library-{count}"
    folder.mkdir(parents=True, exist_ok=True)
    pages = []
    for name in SOURCES:
        with zipfile.ZipFile(CORPUS / name) as source:
            pages.append([(item, source.read(item)) for item in source.namelist()
                          if not item.endswith("/") and item.lower() != "comicinfo.xml"])
    for index in range(count):
        target = folder / f"Budget {index + 1:05d}.cbz"
        if target.exists():
            continue
        with zipfile.ZipFile(target, "w", zipfile.ZIP_STORED) as archive:
            for item, data in pages[index % len(pages)]:
                archive.writestr(item, data)
            archive.writestr("ComicInfo.xml", comic_info(index))
    print(f"{count} publications in {folder}")


if __name__ == "__main__":
    main()
