# Covers on the ladder — Android, 2026-09-06

Frames from `storyarc-j6` (1080 × 2400, 411 × 914 dp, `-gpu host`), taken with
`scripts/capture-android.mjs`. The 2026-09-05 design review's finding 11: *eight Android
surfaces are off the cover-size ladder* — a hard-coded width in no tier, no accessibility step,
no maximum. `docs/design.md` §4's table of eight now says what each does; these are the frames
for the ones a phone with the generated corpus can reach.

| Frame | Route | Surface | What to look at |
| --- | --- | --- | --- |
| `android-detail-series.png` | `Publication page > series` | `DetailSeriesShelf` | *Other issues in this series* at 108 dp a cell |
| `android-detail-series-ax.png` | the same, `--font-scale 2.0` | `DetailSeriesShelf` | The same cells at 151 dp: the shelf stepped with the text, so `#1` and `#3` still sit under their covers |
| `android-library-list.png` | `Library > list layout` | `CoverList` | Rows with a 44 dp thumbnail |
| `android-library-list-ax.png` | the same, `--font-scale 2.0` | `CoverList` | The thumbnail at 62 dp beside a title that doubled, rather than shrinking against it |
| `android-shelves.png` | `Shelves` | `ShelvesScreen` | **The empty state, not the lattice**: this device has no collection and no reading list, so no four-cover lattice is drawn |
| `android-shelves-ax.png` | the same, `--font-scale 2.0` | `ShelvesScreen` | The same empty state with its text doubled; kept because it was owed and to say plainly what it is |

## What the frames settle, and what only the arithmetic does

At an ordinary text size every one of these surfaces draws exactly as before: the step is the
change, and it is visible only at font scale 1.3 and above, which is why each surface has a
`--font-scale 2.0` twin. `CoverLadderStepTest` asserts the five pure functions at 1.0, 1.29,
1.3 and 2.0 — `seriesCellWidth`, `listThumbnailWidth`, `coverOptionMinimumWidth` /
`coverOptionMaximumWidth`, `shelfLatticeMinimumWidth` / `shelfLatticeMaximumWidth`,
`catalogueGroupCoverWidth`.

Three surfaces have no frame of their step here and say so. **The shelves lattice**
(`ShelvesScreen`) is drawn only when a shelf exists, and the generated corpus registers none, so
its 150 / 220 → 210 / 308 step rests on the test; creating a collection through `Shelves > create
dialog` would give a shelf of one cover, not a lattice of four. **The shelf cover picker**
(`ShelfCoverChoice`) has no capture route, so its 92 → 129 step rests on the test alone. **The three remote grids
and the catalogue groups row** need a registered source, which the corpus does not give this
device; they now ask `rememberCoverColumns()`, the same call the Downloads shelf has always
made, and the guard `ShelvesAskOneRuleTest` names each of them as a full-width shelf entitled
to the window's width.

## How to retake them

```bash
L=docs/designs/screenshots/android-cover-ladder-2026-09-06
node scripts/capture-android.mjs "Publication page > series" --out $L/android-detail-series.png
node scripts/capture-android.mjs "Publication page > series" --out $L/android-detail-series-ax.png --font-scale 2.0
node scripts/capture-android.mjs "Library > list layout" --out $L/android-library-list.png
node scripts/capture-android.mjs "Library > list layout" --out $L/android-library-list-ax.png --font-scale 2.0
node scripts/capture-android.mjs "Shelves" --out $L/android-shelves.png
node scripts/capture-android.mjs "Shelves" --out $L/android-shelves-ax.png --font-scale 2.0
```

`--font-scale 2.0` is two arguments. Passed as one quoted word it reads as a route name, and the
script answers "the route map may be stale" — which is how the first pass at the scaled pair
photographed nothing.
