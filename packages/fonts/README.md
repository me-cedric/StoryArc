# Bundled reading typefaces

Five families the EPUB reader offers beyond the system faces, from
`reader-theming-and-page-transitions`. All five are
[OFL](https://openfontlicense.org)-licensed; each licence sits beside the files it
covers as `OFL-<family>.txt`.

One copy on disk, read by both apps. iOS gets it as a SwiftPM resource target and
Android as an asset source directory — the same arrangement as
[`packages/test-fixtures`](../test-fixtures/README.md) and
[`third_party/libarchive`](../../third_party/libarchive/VENDORING.md), and for the
same reason: two copies of a binary asset drift.

## What is here, and what it costs

Sizes are the bundled files, per app. Task 6.4 of the change asks for this to be a
visible cost rather than an accident.

| Family | Bundled | Upstream | Why it is in |
| --- | --- | --- | --- |
| Literata | 889 kB | 1814 kB | Designed for screen reading. The default for Paper. |
| Source Serif 4 | 1091 kB | 2017 kB | Clean, wide weight range. Carries Bold. |
| EB Garamond | 1194 kB | 1568 kB | Classical. Gives Calm a genuinely different voice. |
| Bitter | 563 kB | 631 kB | Slab; holds legibility at small sizes and in Focus's narrow measure. |
| Atkinson Hyperlegible | 196 kB | 215 kB | Designed for low vision, and **labelled as such** in the picker. |
| **Total** | **3934 kB** | **6245 kB** | |

3.9 MB, against the 2–3 MB the design estimated. The estimate was optimistic and
the number is the number: EB Garamond alone is 1.2 MB because its glyph set is
large and it varies only on weight, so there is no second axis to drop.

## How the reduction works

[`scripts/build.py`](scripts/build.py) fetches from
[google/fonts](https://github.com/google/fonts), then does two things, neither of
which changes anything a reader can see.

**Subsets to Latin, Latin Extended, Greek and Cyrillic** — the four scripts the
task names. Google Fonts ships Vietnamese and polytonic Greek in the same files; an
app that offers four scripts should carry four.

**Instances the optical-size axis away.** Literata and Source Serif 4 vary on
`opsz` as well as `wght`. A reader never animates optical size — the right value
for body text is simply the body-text value — so the axis is pinned at 12 pt and
dropped, which halves both families. The weight range is narrowed to 300–700, which
is what the interface can ask for. EB Garamond and Bitter have no second axis,
which is why they barely move.

## Refreshing them

```bash
python3 -m pip install --user fonttools
python3 packages/fonts/scripts/build.py          # fetch, subset, write, report
python3 packages/fonts/scripts/build.py --check  # report the current sizes
```

Commit the regenerated `.ttf` files and the refreshed size table together. A table
that disagrees with the files is worse than no table.
