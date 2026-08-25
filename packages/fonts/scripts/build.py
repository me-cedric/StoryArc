#!/usr/bin/env python3
"""Fetch, subset and instance the bundled reading typefaces.

`reader-theming-and-page-transitions` task 6.1 asks for five families subset to
Latin, Latin Extended, Greek and Cyrillic, and task 6.4 asks for the size of each
to be a visible cost rather than an accident. This script is how both stay true:
run it and the numbers in `README.md` are reproducible rather than remembered.

Two reductions, both of which change nothing a reader can see.

* **Subsetting** to the four named scripts. Google Fonts ships Vietnamese,
  polytonic Greek and more in the same file; a reading app that offers four
  scripts should carry four.
* **Instancing** the optical-size axis away. Literata and Source Serif 4 vary on
  `opsz` as well as `wght`, and a reader never animates optical size — the right
  value for body text is the body-text value. Dropping the axis halves both files.
  The weight range is narrowed to what the interface can ask for.

    python3 packages/fonts/scripts/build.py          # fetch, subset, write, report
    python3 packages/fonts/scripts/build.py --check  # report only, write nothing

Requires `fonttools`. Install with `python3 -m pip install --user fonttools`.
"""

from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
UPSTREAM = "https://raw.githubusercontent.com/google/fonts/main/ofl"

# Latin, Latin Extended, Greek and Cyrillic, as Google Fonts draws those lines,
# plus the punctuation and currency any of them needs. Polytonic Greek
# (U+1F00–1FFF) is deliberately absent: the task names Greek, and polytonic is a
# separate subset that costs EB Garamond alone a couple of hundred kilobytes.
UNICODES = ",".join([
    "U+0000-024F",   # Basic Latin, Latin-1, Latin Extended-A and -B
    "U+0259",        # schwa, used by several Latin orthographies
    "U+0300-036F",   # combining diacritics
    "U+0370-03FF",   # Greek and Coptic
    "U+0400-052F",   # Cyrillic and Cyrillic Supplement
    "U+1E00-1EFF",   # Latin Extended Additional
    "U+2000-206F",   # General Punctuation
    "U+2070-209F",   # super- and subscripts
    "U+20A0-20CF",   # currency
    "U+2100-214F",   # letterlike symbols
    "U+2C60-2C7F",   # Latin Extended-C
    "U+A720-A7FF",   # Latin Extended-D
    "U+FB00-FB4F",   # ligature presentation forms
    "U+FEFF",        # byte-order mark
    "U+FFFD",        # replacement character
])

#: family -> (upstream directory, [(upstream file, local file, instancer axes)])
FAMILIES: dict[str, tuple[str, list[tuple[str, str, list[str]]]]] = {
    "Literata": ("literata", [
        ("Literata[opsz,wght].ttf", "Literata.ttf", ["opsz=12", "wght=300:700"]),
        ("Literata-Italic[opsz,wght].ttf", "Literata-Italic.ttf", ["opsz=12", "wght=300:700"]),
    ]),
    "Source Serif 4": ("sourceserif4", [
        ("SourceSerif4[opsz,wght].ttf", "SourceSerif4.ttf", ["opsz=12", "wght=300:700"]),
        ("SourceSerif4-Italic[opsz,wght].ttf", "SourceSerif4-Italic.ttf", ["opsz=12", "wght=300:700"]),
    ]),
    "EB Garamond": ("ebgaramond", [
        ("EBGaramond[wght].ttf", "EBGaramond.ttf", ["wght=400:700"]),
        ("EBGaramond-Italic[wght].ttf", "EBGaramond-Italic.ttf", ["wght=400:700"]),
    ]),
    "Bitter": ("bitter", [
        ("Bitter[wght].ttf", "Bitter.ttf", ["wght=300:700"]),
        ("Bitter-Italic[wght].ttf", "Bitter-Italic.ttf", ["wght=300:700"]),
    ]),
    # Four statics rather than a variable font: Atkinson Hyperlegible ships that
    # way, and at 50 kB a face there is nothing to gain by asking for more.
    "Atkinson Hyperlegible": ("atkinsonhyperlegible", [
        ("AtkinsonHyperlegible-Regular.ttf", "AtkinsonHyperlegible-Regular.ttf", []),
        ("AtkinsonHyperlegible-Italic.ttf", "AtkinsonHyperlegible-Italic.ttf", []),
        ("AtkinsonHyperlegible-Bold.ttf", "AtkinsonHyperlegible-Bold.ttf", []),
        ("AtkinsonHyperlegible-BoldItalic.ttf", "AtkinsonHyperlegible-BoldItalic.ttf", []),
    ]),
}


def fetch(directory: str, name: str, into: pathlib.Path) -> None:
    url = f"{UPSTREAM}/{directory}/{urllib.parse.quote(name)}"
    with urllib.request.urlopen(url, timeout=120) as response:
        into.write_bytes(response.read())


def run(*command: str) -> None:
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        tail = (result.stderr or result.stdout).strip().splitlines()
        raise SystemExit(f"failed: {' '.join(command)}\n{tail[-1] if tail else ''}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="report only, write nothing")
    arguments = parser.parse_args()

    try:
        import fontTools  # noqa: F401
    except ImportError:
        print("fonttools is required: python3 -m pip install --user fonttools", file=sys.stderr)
        return 1

    if arguments.check:
        total = 0
        for family, (_, files) in FAMILIES.items():
            size = sum((ROOT / name).stat().st_size for _, name, _ in files if (ROOT / name).exists())
            total += size
            print(f"  {size / 1024:8.0f} kB  {family}")
        print(f"  {total / 1024:8.0f} kB  total")
        return 0

    work = ROOT / ".work"
    work.mkdir(exist_ok=True)
    report: list[tuple[str, int, int]] = []

    for family, (directory, files) in FAMILIES.items():
        before = after = 0
        for upstream, local, axes in files:
            raw = work / f"raw-{local}"
            print(f"  fetching {family} · {local}")
            fetch(directory, upstream, raw)
            before += raw.stat().st_size

            subset = work / f"sub-{local}"
            run(
                sys.executable, "-m", "fontTools.subset", str(raw),
                f"--output-file={subset}", f"--unicodes={UNICODES}",
                "--layout-features=*", "--name-IDs=*", "--notdef-outline", "--recalc-bounds",
            )

            destination = ROOT / local
            if axes:
                run(
                    sys.executable, "-m", "fontTools.varLib.instancer",
                    str(subset), *axes, "-o", str(destination),
                )
            else:
                destination.write_bytes(subset.read_bytes())
            after += destination.stat().st_size

        # The licence travels with the family. `reading-themes` requires every OFL
        # notice in acknowledgements, and a licence in the same directory as the
        # files it covers is the version that does not get separated from them.
        fetch(directory, "OFL.txt", ROOT / f"OFL-{directory}.txt")
        report.append((family, before, after))

    for path in work.iterdir():
        path.unlink()
    work.rmdir()

    print()
    print(f"  {'family':24} {'upstream':>10} {'bundled':>10}  saving")
    for family, before, after in report:
        print(
            f"  {family:24} {before / 1024:9.0f} kB {after / 1024:9.0f} kB"
            f"  {100 - after * 100 // before:3d}%"
        )
    total_before = sum(b for _, b, _ in report)
    total_after = sum(a for _, _, a in report)
    print(
        f"  {'total':24} {total_before / 1024:9.0f} kB {total_after / 1024:9.0f} kB"
        f"  {100 - total_after * 100 // total_before:3d}%"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
